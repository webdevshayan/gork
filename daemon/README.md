# gork daemon

The companion daemon that makes gork work 24/7 — even when the phone is
asleep. It runs on **hardware you own** and holds the schedule, calls your
LLM when tasks are due, and pushes the results to your phone through ntfy
(free, no account).

It is **self-hostable anywhere**:

| Environment | Service backend | Notes |
|---|---|---|
| Debian/Ubuntu VPS (real systemd) | `systemd` unit | auto-enabled on boot |
| Native **Termux** on Android | `termux-services` (runit) if installed, else `gork-daemonctl` | no root; wake-lock + boot script when possible |
| proot/chroot Debian on Android (fake `systemctl`) | `gork-daemonctl` | the fake shim is detected and ignored |
| Any other Linux without systemd | `gork-daemonctl` | pidfile + nohup + health-checked starts |

The installer **never claims success without proof**: the final line is only
printed after `/health` actually answered. If it did not, you get the log
tail and a non-zero exit instead of a lie.

## Install (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash
```

Non-interactive configuration via environment variables:

```bash
GORK_API_KEY=sk-... GORK_MODEL=gpt-4o-mini NTFY_TOPIC=gork-a-long-random-name \
  curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash
```

- `GORK_API_KEY` — your LLM key (BYOK, stays on the box).
- `GORK_BASE_URL` / `GORK_MODEL` — any OpenAI-compatible endpoint.
- `NTFY_TOPIC` — optional; pick a long random name and subscribe to it in the
  ntfy app to get task results as push notifications.
- `GORK_SECRET` — shared secret for the phone app; generated automatically if
  unset and printed at the end (the app needs the same value in
  **Cloud Computer → secret**). `/health` stays open for liveness checks;
  every other endpoint requires the `X-Gork-Secret` header.
- `GORK_PORT` — listen port (default 8787). `GORK_BACKEND` — force
  `systemd` / `termux-services` / `ctl`. `GORK_NO_START=1` — install without
  starting.

What the installer does: installs Dart (apt or `pkg`), clones this repo to
`/opt/gork` (root) or `~/.gork` (Termux / non-root), runs `dart pub get`,
registers the best service backend for the detected platform, starts the
daemon and verifies `/health` before reporting success.

## Configure

One config file, wherever the installer put it:

- systemd: `/etc/gork-daemon/config.env` (state: `/var/lib/gork-daemon`)
- Termux / ctl: `~/.gork-daemon/config.env` (state lives in the same folder)

After editing, restart (see below). Re-running the installer never
overwrites an existing config.

## Manage

```bash
# systemd
systemctl status gork-daemon
journalctl -u gork-daemon -f
sudo systemctl restart gork-daemon

# termux-services (pkg install termux-services)
sv status gork-daemon
sv restart gork-daemon

# everywhere else (Termux, proot, plain Linux)
gork-daemonctl status | health | logs | restart | stop | start
```

`gork-daemonctl start` is honest too: it refuses to fake success. If the
port is already owned by something it did not start, it tells you instead of
silently shadowing it; if the daemon dies, you get the last log lines.

### Termux tips

- `pkg install termux-services` gives you real supervision (`sv`) and
  auto-start; without it the ctl script + wake-lock do the job.
- The installer grabs `termux-wake-lock` so Android does not kill the daemon.
- If the Termux:Boot app is installed (`~/.termux/boot` exists), a boot
  script is added automatically; otherwise a `@reboot` cron line is used when
  crontab exists.

## CLI — configure everything from the terminal

The installer ships a `gork` command next to `gork-daemonctl`. No file
editing, ever:

```bash
gork llm providers                 # real OpenAI-compatible presets
gork llm set openai                # writes BASE_URL + MODEL to config
gork config set GORK_API_KEY sk-...   # your key, stays on this box
gork llm test                      # live 1-token call: proves it works
gork tasks add "Morning brief" "summarize my inbox" 60
gork tasks list | remove <id> | run
gork status                        # liveness + task count
gork secret                        # the pairing secret for the phone app
gork config list                   # everything, masked
```

## REST API

| Method | Path       | What                       |
|--------|------------|----------------------------|
| GET    | `/health`  | liveness check (no secret needed) |
| GET    | `/tasks`   | list tasks                 |
| POST   | `/tasks`   | add task `{title, prompt, repeatMinutes}` |
| DELETE | `/tasks/{id}` | remove a task           |
| POST   | `/run`     | run all due tasks now      |

All endpoints except `/health` require the `X-Gork-Secret` header when
`GORK_SECRET` is set. The phone app talks to the same API (set the endpoint
in **Cloud Computer → AgentVPS**).

## Tests

```bash
cd daemon
dart test                     # server + scheduler logic
bash test/installer_test.sh   # backend detection, ctl lifecycle, honest starts,
                              # config handling, real end-to-end daemon boot
```

## Troubleshooting

- **`systemctl` prints `not found /etc/initrd-release` or
  `/proc/net/stat: Permission denied`** — that is the proot fake systemctl,
  not real systemd. The installer now detects this and uses
  `gork-daemonctl` instead; older installs left a dead unit behind, which is
  why nothing was listening.
- **`port 8787 already serves /health, but no pidfile points at it`** — a
  stale daemon from a previous install still owns the port. Find it with
  `ss -tlnp | grep 8787`, kill it, start again (or change `GORK_PORT`).
- **`found .../bin/gork_daemon.dart but dart is not installed`** —
  `pkg install dart` (Termux) or follow dart.dev (Debian).
- **Nothing is listening** — run `gork-daemonctl logs` (or
  `journalctl -u gork-daemon -n 50`) and fix what the log says.
