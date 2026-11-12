#!/usr/bin/env bash
# installer_test.sh — TDD suite for daemon/install.sh + daemon/gork-daemonctl.
#
# Covers the "self-host anywhere" contract:
#   * fake/absent systemd (Termux proot boxes) must fall back to the ctl backend
#   * real systemd, termux-services, and forced backends are detected correctly
#   * gork-daemonctl start/stop/status/health works and never lies about success
#   * config.env is never clobbered by a re-run
#   * end-to-end: the real Dart daemon boots from source and /health answers
#
# Run: bash daemon/test/installer_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DAEMON="$ROOT/daemon"
INSTALLER="$DAEMON/install.sh"
CTL="$DAEMON/gork-daemonctl"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ok - $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
summary() {
  echo ""
  echo "installer_test.sh: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---- fakes -----------------------------------------------------------------
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/systemctl" <<'EOF'
#!/usr/bin/env bash
# A *real* systemd would have /run/systemd/system; this fake only exists to
# satisfy `command -v systemctl` (mimics the proot shim on Android boxes).
exit 0
EOF
chmod +x "$FAKEBIN/systemctl"
cat > "$FAKEBIN/sv" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKEBIN/sv"
cat > "$TMP/fake_daemon.py" <<'EOF'
# Stand-in daemon: serves /health on the port given as argv[1].
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{"status":"ok","service":"fake"}')
    def log_message(self, *a):
        pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
EOF

# run_install_snippet SOURCED-CMDS -> runs `source install.sh` + CMDS in a
# clean bash so the installer's `set -euo pipefail` never leaks into us.
# stdout and stderr stay separate, and HOME points at a fresh sandbox dir so
# install_repo/write_config never see (or leave) state from another test.
run_install_snippet() {
  GORK_INSTALLER_TEST=1 HOME="$TMP/fakehome" bash -c "
    mkdir -p '$TMP/fakehome'
    export PATH=\"$FAKEBIN:\$PATH\"
    source '$INSTALLER'
    $1
  "
}

echo "# backend detection"

test_no_systemd_dir_means_ctl() {
  local out
  out="$(run_install_snippet 'choose_backend')"
  expect_eq "ctl" "$out" "fake systemctl shim without /run/systemd/system falls back to ctl"
}

test_real_systemd_detected() {
  local dir="$TMP/runsystemd" out
  mkdir -p "$dir"
  out="$(run_install_snippet "GORK_TEST_SYSTEMD_DIR='$dir' choose_backend")"
  expect_eq "systemd" "$out" "systemctl + systemd run dir detected as systemd"
}

test_termux_services_detected() {
  local prefix="$TMP/termprefix" out
  mkdir -p "$prefix/var/service"
  out="$(run_install_snippet "PREFIX='$prefix' GORK_TEST_SYSTEMD_DIR=/nonexistent choose_backend")"
  expect_eq "termux-services" "$out" "PREFIX + sv + var/service detected as termux-services"
}

test_forced_backend_wins() {
  local out
  out="$(run_install_snippet "GORK_BACKEND=ctl choose_backend")"
  expect_eq "ctl" "$out" "GORK_BACKEND override is honored (systemd present)"
}

test_no_termux_prefix_means_not_services() {
  local out
  out="$(run_install_snippet "unset PREFIX; GORK_TEST_SYSTEMD_DIR=/nonexistent choose_backend")"
  expect_eq "ctl" "$out" "sv present but no PREFIX -> not termux-services"
}

# ---- config ----------------------------------------------------------------

echo "# config.env handling"

test_config_written_and_kept() {
  local dir="$TMP/cfg"; mkdir -p "$dir"
  local out1 out2
  out1="$(run_install_snippet "GORK_HOME='$dir' write_config")" || fail "write_config (first run) exited non-zero"
  [ -f "$dir/config.env" ] && pass "config.env created on first run" || fail "config.env missing after first run"
  grep -q "GORK_SECRET=" "$dir/config.env" && pass "a GORK_SECRET is generated" || fail "GORK_SECRET missing"
  echo 'GORK_API_KEY=keepme-please' >> "$dir/config.env"
  out2="$(run_install_snippet "GORK_HOME='$dir' write_config")" || fail "write_config (second run) exited non-zero"
  grep -q "GORK_API_KEY=keepme-please" "$dir/config.env" \
    && pass "re-run never clobbers an existing config" \
    || fail "re-run clobbered user config"
}

test_gen_secret_is_hex() {
  local s
  s="$(run_install_snippet 'gen_secret')"
  if [ ${#s} -ge 32 ] && printf '%s' "$s" | grep -Eq '^[0-9a-f]+$'; then
    pass "gen_secret returns >=32 hex chars"
  else
    fail "gen_secret output not long hex: '$s'"
  fi
}

test_install_repo_stdout_is_only_path() {
  # install_repo's stdout is captured by main; ANY log line there poisons the
  # install. Regression guard: stub git/dart, require exactly one path line.
  cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  clone) mkdir -p "$5/.git" "$5/daemon" 2>/dev/null || true ;;
esac
exit 0
EOF
  chmod +x "$FAKEBIN/git"
  cat > "$FAKEBIN/dart" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKEBIN/dart"
  local out lines
  out="$(run_install_snippet 'install_repo')"
  lines="$(printf '%s' "$out" | grep -c . )"
  case "$out" in
    */daemon)
      [ "$lines" -eq 1 ] && pass "install_repo stdout = exactly the daemon dir" \
        || fail "install_repo printed $lines lines (logs leaked into stdout): '$out'" ;;
    *) fail "install_repo stdout does not end in /daemon: '$out'" ;;
  esac
}

# ---- gork-daemonctl ---------------------------------------------------------

echo "# gork-daemonctl"

new_ctl_env() { # $1 = home dir  -> prints env prefix
  printf 'GORK_HOME=%s GORK_SRC_DIR=%s GORK_HEALTH_TIMEOUT=8' "$1" "$DAEMON"
}

test_ctl_start_stop_status_with_fake_daemon() {
  local home="$TMP/ctlhome" port=18801; mkdir -p "$home"
  eval "$(new_ctl_env "$home") GORK_PORT=$port GORK_DAEMON_CMD='python3 $TMP/fake_daemon.py $port' bash '$CTL' start"
  [ $? -eq 0 ] && pass "ctl start (fake daemon, health verified) exits 0" || fail "ctl start exited non-zero"
  [ -f "$home/gork-daemon.pid" ] && pass "pidfile written" || fail "pidfile missing"
  eval "$(new_ctl_env "$home") bash '$CTL' status" >/dev/null 2>&1 \
    && pass "ctl status reports running" || fail "ctl status failed while running"
  eval "$(new_ctl_env "$home") GORK_PORT=$port GORK_DAEMON_CMD='python3 $TMP/fake_daemon.py $port' bash '$CTL' start" >/dev/null 2>&1 \
    && pass "second start is a no-op (already running)" || fail "double start broke"
  eval "$(new_ctl_env "$home") bash '$CTL' stop" >/dev/null 2>&1 \
    && pass "ctl stop exits 0" || fail "ctl stop failed"
  eval "$(new_ctl_env "$home") bash '$CTL' status" >/dev/null 2>&1 \
    && fail "ctl status claims running after stop" || pass "ctl status reports stopped"
  sleep 0.3
  pgrep -f 'fake_daemon.py' >/dev/null && fail "daemon process still alive after stop" || pass "process really killed"
}

test_ctl_start_reports_failure_honestly() {
  local home="$TMP/ctlbad"; mkdir -p "$home"
  eval "$(new_ctl_env "$home") GORK_DAEMON_CMD='false' GORK_HEALTH_TIMEOUT=2 bash '$CTL' start" >/dev/null 2>&1
  [ $? -ne 0 ] && pass "ctl start exits non-zero when the daemon dies" || fail "ctl start lied about success"
}

test_ctl_start_reports_dead_port_honestly() {
  local home="$TMP/ctlsilent"; mkdir -p "$home"
  # Daemon that runs but never serves /health on the expected port.
  eval "$(new_ctl_env "$home") GORK_DAEMON_CMD='sleep 30' GORK_PORT=1 GORK_HEALTH_TIMEOUT=2 bash '$CTL' start" >/dev/null 2>&1
  [ $? -ne 0 ] && pass "unreachable /health makes start fail loudly" || fail "start claimed success with no health"
  eval "$(new_ctl_env "$home") bash '$CTL' stop" >/dev/null 2>&1 || true
}

test_ctl_start_refuses_stale_port_owner() {
  local home="$TMP/ctlstale" port=18802; mkdir -p "$home"
  # A stale daemon (or any other program) already owns the port, and we have
  # no pidfile for it. Starting must REFUSE — otherwise the new daemon dies
  # on 'port in use' while the stale one answers our health checks.
  python3 "$TMP/fake_daemon.py" "$port" & local stale=$!
  sleep 0.7
  eval "$(new_ctl_env "$home") GORK_PORT=$port GORK_DAEMON_CMD='sleep 30' GORK_HEALTH_TIMEOUT=3 bash '$CTL' start" >/dev/null 2>&1
  [ $? -ne 0 ] && pass "start refuses when an untracked listener owns the port" \
    || fail "start was fooled by a stale port owner"
  kill "$stale" 2>/dev/null || true
}

# ---- end-to-end with the real daemon ----------------------------------------

echo "# end-to-end (real dart daemon)"

test_real_daemon_boots_and_answers_health() {
  command -v dart >/dev/null 2>&1 || { fail "dart not on PATH for e2e test"; return; }
  (cd "$DAEMON" && dart pub get >/dev/null 2>&1) || { fail "dart pub get failed"; return; }
  local home="$TMP/e2e" port=$((19400 + RANDOM % 500))
  mkdir -p "$home"
  printf 'GORK_PORT=%s\n' "$port" > "$home/config.env"
  eval "$(new_ctl_env "$home") GORK_HEALTH_TIMEOUT=40 GORK_DAEMON_CMD='dart run bin/gork_daemon.dart' bash '$CTL' start"
  [ $? -eq 0 ] && pass "real daemon started via ctl (source mode)" || fail "real daemon failed to start"
  local body
  body="$(eval "$(new_ctl_env "$home") bash '$CTL' health" 2>/dev/null)"
  case "$body" in
    *'"status":"ok"'*) pass "/health answers with status ok" ;;
    *) fail "/health did not answer ok: '$body'" ;;
  esac
  eval "$(new_ctl_env "$home") bash '$CTL' stop" >/dev/null 2>&1 \
    && pass "real daemon stopped cleanly" || fail "stop failed on real daemon"
}

# ---- run --------------------------------------------------------------------
for t in test_no_systemd_dir_means_ctl test_real_systemd_detected \
         test_termux_services_detected test_forced_backend_wins \
         test_no_termux_prefix_means_not_services test_config_written_and_kept \
         test_gen_secret_is_hex test_install_repo_stdout_is_only_path \
         test_ctl_start_stop_status_with_fake_daemon \
         test_ctl_start_reports_failure_honestly \
         test_ctl_start_reports_dead_port_honestly \
         test_ctl_start_refuses_stale_port_owner \
         test_real_daemon_boots_and_answers_health; do
  echo "## $t"
  "$t"
done
summary
