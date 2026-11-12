#!/usr/bin/env bash
# gork daemon installer — self-hosts the daemon on:
#   * a real Debian/Ubuntu VPS (systemd)
#   * native Termux on Android (no root, optional termux-services)
#   * a proot/chroot Debian on an Android box (the classic FAKE systemctl shim:
#     "ERROR:systemctl:not found /etc/initrd-release" -> no real systemd there)
#   * any other Linux without systemd
#
# Non-interactive configuration (environment variables):
#   GORK_BACKEND    force: systemd | termux-services | ctl
#   GORK_PORT       listen port                    (default 8787)
#   GORK_API_KEY    your LLM key                   (BYOK, stays on the box)
#   GORK_BASE_URL   OpenAI-compatible base url     (default https://api.openai.com/v1)
#   GORK_MODEL      model id                       (default gpt-4o-mini)
#   NTFY_TOPIC      optional free push channel topic
#   GORK_SECRET     shared secret for the phone app (generated if unset)
#   GORK_NO_START=1 install everything but do not start
#
# The installer NEVER claims success without proof: the daemon must answer
# /health before the final green line is printed.
set -euo pipefail

# --- detection ---------------------------------------------------------------
IS_TERMUX=0
IS_ANDROID=0
[ -n "${TERMUX_VERSION:-}" ] && IS_TERMUX=1
[ "$(uname -o 2>/dev/null || true)" = "Android" ] && IS_ANDROID=1

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

has_real_systemd() {
  command -v systemctl >/dev/null 2>&1 || return 1
  # The proot fakes do NOT have systemd's run directory. This directory only
  # exists when systemd is genuinely PID 1 — it is the authoritative check.
  [ -d "${GORK_TEST_SYSTEMD_DIR:-/run/systemd/system}" ]
}

has_termux_services() {
  [ -n "${PREFIX:-}" ] || return 1
  command -v sv >/dev/null 2>&1 || return 1
  [ -d "$PREFIX/var/service" ]
}

# Prints exactly one backend name on stdout (tests parse it); logs -> stderr.
choose_backend() {
  local forced="${GORK_BACKEND:-}"
  case "$forced" in
    systemd|termux-services|ctl) echo "$forced"; return 0 ;;
    "") ;;
    *) echo "GORK_BACKEND='$forced' is not valid, auto-detecting" >&2 ;;
  esac
  if has_real_systemd; then echo "systemd"; return 0; fi
  if has_termux_services; then echo "termux-services"; return 0; fi
  echo "ctl"
}

# --- config ------------------------------------------------------------------
gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# Writes $GORK_HOME/config.env. Never clobbers an existing config.
write_config() {
  local dir="${GORK_HOME:?GORK_HOME must be set}"
  mkdir -p "$dir"
  if [ -f "$dir/config.env" ]; then
    echo "   config kept: $dir/config.env (re-runs never overwrite your key)" >&2
    return 0
  fi
  {
    echo "# gork daemon configuration — edit me, then restart the daemon"
    echo "GORK_PORT=\"${GORK_PORT:-8787}\""
    echo "GORK_SECRET=\"${GORK_SECRET:-$(gen_secret)}\""
    [ -n "${GORK_API_KEY:-}" ]  && echo "GORK_API_KEY=\"$GORK_API_KEY\""
    [ -n "${GORK_BASE_URL:-}" ] && echo "GORK_BASE_URL=\"$GORK_BASE_URL\""
    [ -n "${GORK_MODEL:-}" ]    && echo "GORK_MODEL=\"$GORK_MODEL\""
    [ -n "${NTFY_TOPIC:-}" ]    && echo "NTFY_TOPIC=\"$NTFY_TOPIC\""
    [ -n "${GORK_SRC_DIR:-}" ]  && echo "GORK_SRC_DIR=\"$GORK_SRC_DIR\""
  } > "$dir/config.env"
  chmod 600 "$dir/config.env" 2>/dev/null || true
  echo "   config written: $dir/config.env" >&2
}

# --- packages ----------------------------------------------------------------
install_packages() {
  if [ "$IS_TERMUX" -eq 1 ]; then
    echo "-- Termux: installing dart, git, curl via pkg..."
    pkg install -y dart git curl 2>&1 | tail -n 1 || true
  else
    echo "-- Installing base packages..."
    $SUDO apt-get update -y >/dev/null 2>&1 || true
    $SUDO apt-get install -y curl git unzip gpg ca-certificates >/dev/null 2>&1 || true
    if ! command -v dart >/dev/null 2>&1; then
      echo "-- Installing Dart SDK..."
      $SUDO apt-get install -y gpg >/dev/null 2>&1 || true
      curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
        | $SUDO gpg --dearmor -o /usr/share/keyrings/dart.gpg
      echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
        | $SUDO tee /etc/apt/sources.list.d/dart.list >/dev/null
      $SUDO apt-get update -y >/dev/null 2>&1 || true
      $SUDO apt-get install -y dart || {
        echo "   could not apt-install dart; install it manually, then re-run." >&2
        return 1
      }
    fi
  fi
  command -v dart >/dev/null 2>&1 || {
    echo "ERROR: dart is not installed. Install it and re-run this installer." >&2
    echo "  Termux:        pkg install dart" >&2
    echo "  Debian/Ubuntu: see https://dart.dev/get-dart" >&2
    return 1
  }
}

# --- repo --------------------------------------------------------------------
install_repo() { # prints ONLY the daemon source dir on stdout; logs -> stderr
  local root
  if [ "$IS_TERMUX" -eq 1 ]; then
    root="$HOME/.gork"
  elif [ -w /opt ] || [ "$(id -u)" -eq 0 ]; then
    root=/opt/gork
  else
    root="$HOME/.gork"
  fi
  if [ -d "$root/.git" ]; then
    echo "-- Updating gork in $root..." >&2
    (cd "$root" && git pull --ff-only >/dev/null 2>&1 || true)
  else
    echo "-- Cloning gork into $root..." >&2
    git clone --depth 1 https://github.com/webdevshayan/gork.git "$root" >&2
  fi
  echo "-- Installing daemon dependencies..." >&2
  (cd "$root/daemon" && dart pub get >/dev/null)
  echo "$root/daemon"
}

# --- backends ----------------------------------------------------------------
poll_health() { # $1 url  $2 timeout-seconds -> exit 0 iff /health answers
  local deadline=$(( $(date +%s) + ${2:-30} ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsS --max-time 3 "$1" >/dev/null 2>&1 && return 0
    elif command -v wget >/dev/null 2>&1; then
      wget -q -T 3 -O /dev/null "$1" 2>/dev/null && return 0
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c "import urllib.request,sys;urllib.request.urlopen(sys.argv[1],timeout=3)" "$1" >/dev/null 2>&1 && return 0
    else
      return 2
    fi
    sleep 0.5
  done
  return 1
}

install_systemd() { # $1 = daemon src dir
  local src="$1" cfg="/etc/gork-daemon"
  local dart_bin; dart_bin="$(command -v dart)"
  echo "-- Writing systemd unit + $cfg/config.env..."
  $SUDO mkdir -p "$cfg" /var/lib/gork-daemon
  GORK_HOME="$cfg" write_config
  $SUDO tee /etc/systemd/system/gork-daemon.service >/dev/null <<UNIT
[Unit]
Description=gork companion daemon (scheduled AI tasks, 24/7)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$src
Environment=GORK_HOME=/var/lib/gork-daemon
EnvironmentFile=-$cfg/config.env
ExecStart=$dart_bin run bin/gork_daemon.dart
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  $SUDO systemctl daemon-reload
  if [ "${GORK_NO_START:-0}" = "1" ]; then
    $SUDO systemctl enable gork-daemon
    echo "-- GORK_NO_START=1: unit enabled but not started."
    return 0
  fi
  $SUDO systemctl enable gork-daemon
  $SUDO systemctl restart gork-daemon
  sleep 2
  $SUDO systemctl is-active --quiet gork-daemon
}

install_termux_services() { # $1 = daemon src dir
  local src="$1" home="$HOME/.gork-daemon"
  [ -n "${PREFIX:-}" ] && command -v sv >/dev/null 2>&1 || return 1
  [ -d "$PREFIX/var/service" ] || return 1
  echo "-- Registering termux-services unit: $PREFIX/var/service/gork-daemon"
  GORK_HOME="$home" write_config
  mkdir -p "$PREFIX/var/service/gork-daemon"
  cat > "$PREFIX/var/service/gork-daemon/run" <<RUN
#!$PREFIX/bin/sh
# gork daemon (runit/termux-services)
export GORK_HOME="$home"
. "\$GORK_HOME/config.env"
export GORK_PORT GORK_API_KEY GORK_BASE_URL GORK_MODEL GORK_SECRET NTFY_TOPIC
cd "$src"
exec dart run bin/gork_daemon.dart
RUN
  chmod +x "$PREFIX/var/service/gork-daemon/run"
  if [ "${GORK_NO_START:-0}" = "1" ]; then
    echo "-- GORK_NO_START=1: service registered but not started."
    return 0
  fi
  sv up gork-daemon 2>/dev/null || sv restart gork-daemon 2>/dev/null || return 1
  sleep 2
  sv status gork-daemon >/dev/null 2>&1
}

install_ctl() { # $1 = daemon src dir ; returns 0 iff daemon verified running
  local src="$1" home="$HOME/.gork-daemon" bindir
  echo "-- Installing gork-daemonctl (no init system needed)..."
  GORK_HOME="$home" GORK_SRC_DIR="$src" write_config
  if [ -n "${PREFIX:-}" ] && [ -w "$PREFIX/bin" ]; then
    bindir="$PREFIX/bin"                                  # Termux
  elif [ "$(id -u)" -eq 0 ] || [ -w /usr/local/bin ]; then
    bindir=/usr/local/bin
  else
    bindir="$HOME/.local/bin"                             # proot / non-root
    mkdir -p "$bindir"
    case ":$PATH:" in
      *":$bindir:"*) ;;
      *) echo "   NOTE: add $bindir to your PATH to use 'gork-daemonctl' directly." >&2 ;;
    esac
  fi
  install -m 0755 "$src/gork-daemonctl" "$bindir/gork-daemonctl" 2>/dev/null \
    || { cp "$src/gork-daemonctl" "$bindir/gork-daemonctl" && chmod 0755 "$bindir/gork-daemonctl"; }

  if [ "${GORK_NO_START:-0}" = "1" ]; then
    echo "-- GORK_NO_START=1: installed but not started."
    return 0
  fi

  # Termux niceties: keep Android from killing us, start on boot if possible.
  if [ "$IS_TERMUX" -eq 1 ] && command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
  fi
  if [ "$IS_TERMUX" -eq 1 ] && [ -d "$HOME/.termux/boot" ]; then
    cat > "$HOME/.termux/boot/gork-daemon.sh" <<BOOT
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
"$bindir/gork-daemonctl" start
BOOT
    chmod +x "$HOME/.termux/boot/gork-daemon.sh"
    echo "-- Termux:Boot script installed (~/.termux/boot/gork-daemon.sh)"
  fi
  if command -v crontab >/dev/null 2>&1 && ! crontab -l 2>/dev/null | grep -q gork-daemonctl; then
    (crontab -l 2>/dev/null; echo "@reboot $bindir/gork-daemonctl start >> $home/gork-daemon.log 2>&1") | crontab - 2>/dev/null \
      && echo "-- @reboot cron entry added (start on boot)." || true
  fi

  "$bindir/gork-daemonctl" start
}

# --- summary -----------------------------------------------------------------
print_summary() { # $1 backend $2 src-dir $3 config-file
  local backend="$1" src="$2" cfg="$3"
  echo ""
  echo "== gork daemon is UP and /health answered. =="
  echo "   source : $src"
  echo "   config : $cfg   (LLM key, model, ntfy topic, secret)"
  if [ -f "$cfg" ]; then
    echo "   secret : $(grep -E '^GORK_SECRET=' "$cfg" | cut -d= -f2- | tr -d '"')"
    echo "            ^ set the same value in the app (Cloud Computer -> secret)."
  fi
  case "$backend" in
    systemd)
      echo "   logs   : journalctl -u gork-daemon -f"
      echo "   restart: sudo systemctl restart gork-daemon   (after editing config)"
      echo "   status : systemctl status gork-daemon" ;;
    termux-services)
      echo "   logs   : tail -f $HOME/.gork-daemon/gork-daemon.log"
      echo "   restart: sv restart gork-daemon   (after editing config)"
      echo "   status : sv status gork-daemon" ;;
    *)
      echo "   logs   : gork-daemonctl logs"
      echo "   restart: gork-daemonctl restart   (after editing config)"
      echo "   status : gork-daemonctl status" ;;
  esac
}

print_failure() { # $1 backend $2 log-hint
  echo "" >&2
  echo "!! INSTALL FINISHED BUT THE DAEMON DID NOT COME UP." >&2
  echo "   Backend: $1.  $2" >&2
  echo "   Fix the problem, then start it and re-verify:" >&2
  echo "     curl http://127.0.0.1:${GORK_PORT:-8787}/health" >&2
  exit 1
}

# --- main ----------------------------------------------------------------------
main() {
  echo "== gork daemon installer =="
  echo "   platform: $([ "$IS_TERMUX" -eq 1 ] && echo 'native Termux' || { [ "$(uname -o 2>/dev/null || true)" = Android ] && echo 'Android (proot/chroot)' || echo "$(uname -s) $(uname -m)"; })"
  echo "   systemd : $(has_real_systemd && echo yes || echo 'no -> fallback backend')"

  local backend src
  backend="$(choose_backend)"
  echo "   backend : $backend"

  install_packages

  src="$(install_repo)"
  GORK_SRC_DIR="$src"

  local ok=0 used="$backend"
  case "$backend" in
    systemd)
      if install_systemd "$src"; then ok=1
      else echo "   systemd setup failed -> falling back to ctl" >&2; used=ctl; fi ;;
    termux-services)
      if install_termux_services "$src"; then ok=1
      else echo "   termux-services setup failed -> falling back to ctl" >&2; used=ctl; fi ;;
  esac
  if [ "$ok" -ne 1 ] && [ "$used" = "ctl" ]; then
    install_ctl "$src" && ok=1
  fi
  [ "$ok" -eq 1 ] || true   # failures are reported by the final health gate

  if [ "${GORK_NO_START:-0}" = "1" ]; then
    echo ""
    echo "== Installed (not started). Start it: =="
    case "$used" in
      systemd)         echo "   sudo systemctl start gork-daemon" ;;
      termux-services) echo "   sv up gork-daemon" ;;
      *)               echo "   gork-daemonctl start" ;;
    esac
    return 0
  fi

  # Final, honest gate: proof or failure.
  local cfgfile="/etc/gork-daemon/config.env"
  [ "$used" = "ctl" ] && cfgfile="$HOME/.gork-daemon/config.env"
  [ "$used" = "termux-services" ] && cfgfile="$HOME/.gork-daemon/config.env"
  if poll_health "http://127.0.0.1:${GORK_PORT:-8787}/health" 40; then
    print_summary "$used" "$src" "$cfgfile"
  else
    print_failure "$used" "Check: journalctl -u gork-daemon -n 50 / sv status gork-daemon / gork-daemonctl logs"
  fi
}

if [ "${GORK_INSTALLER_TEST:-0}" != "1" ]; then
  main "$@"
fi
