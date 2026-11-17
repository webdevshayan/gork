# gork daemon

The companion daemon that makes gork work 24/7 — even when the phone is
asleep. It runs on **hardware you own** and holds the schedule, calls your
LLM when tasks are due, and pushes the results to your phone through ntfy
(free, no account).

It is **self-hostable anywhere**:

| Environment | Service backend | Notes |
|---|---|---|
| Debian/Ubuntu VPS (real systemd) | `systemd` unit | auto-enabled on boot |
| Native **Termux** on Android | `termux-services` (runit) if installed, else `gork daemon start` | no root; wake-lock + boot hooks |
| proot/chroot Debian on Android (fake `systemctl`) | `gork daemon start` | the fake shim is detected and ignored |
| Any other Linux without systemd | `gork daemon start` | pidfile + health-checked starts |

Everything is driven by **one command**: `gork`. The lifecycle, the config,
the tasks, the agent browser and the sealed vault all live behind it.
(`gork-daemonctl` from older installs still exists as a forwarding shim.)
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

What the installer does: installs Dart (apt or `pkg`) and chromium when the
repos have it (the agent browser), clones this repo to `/opt/gork` (root) or
`~/.gork` (Termux / non-root), runs `dart pub get`, registers the best
service backend for the detected platform, installs the **one** `gork`
command, wires boot-time auto-start (`gork autostart`), starts the daemon
and verifies `/health` before reporting success.

## Auto-start — guaranteed, whatever starts

`gork autostart` (run by the installer, idempotent, safe to re-run) layers
every boot path, so the daemon comes up no matter which one fires:

- **systemd** — the `gork-daemon` unit (WantedBy=multi-user.target).
- **Termux:Boot** — `~/.termux/boot/gork-daemon.sh` (the directory is
  created even if the Boot app is not installed yet; installing it later
  picks the script up). Includes `termux-wake-lock`.
- **Shell profiles** — `~/.bashrc` + `~/.profile` hooks, and
  `/etc/profile.d/gork-autostart.sh` where writable — this covers plain
  Termux and proot/chroot distro shells with no Boot app at all.
- **cron** — a `@reboot` line when crontab exists.

`gork daemon start` is a fast no-op when `/health` already answers, so any
number of layers firing is harmless. Hooks are silent and backgrounded —
opening a terminal never blocks.

## Configure

One config file, wherever the installer put it:

- systemd: `/etc/gork-daemon/config.env` (state: `/var/lib/gork-daemon`)
- Termux / ctl: `~/.gork-daemon/config.env` (state lives in the same folder)

After editing, restart (see below). Re-running the installer never
overwrites an existing config. No file editing is ever required —
`gork config set KEY VALUE` upserts keys in place, `gork config list` shows
everything masked.

## Manage

```bash
# the one command, everywhere:
gork daemon start | stop | restart | status | health | logs [n]
gork start            # shorthand for gork daemon start

# systemd additionally:
systemctl status gork-daemon && journalctl -u gork-daemon -f

# termux-services additionally:
sv status gork-daemon && sv restart gork-daemon
```

`gork daemon start` is honest too: it refuses to fake success. It only
reports "started" after `/health` answers; otherwise you get the log path.

## CLI — the one command

The installer ships exactly ONE command: `gork`. No file editing, ever:

```bash
gork daemon start | stop | restart | status | logs   # the lifecycle
gork autostart                        # (re)install every boot hook, idempotent
gork llm providers                    # real OpenAI-compatible presets
gork llm set openai                   # writes BASE_URL + MODEL to config
gork config set GORK_API_KEY sk-...   # your key, stays on this box
gork llm test                         # live 1-token call: proves it works
gork tasks add "Morning brief" "summarize my inbox" 60
gork tasks list | remove <id> | run
gork browser status                   # the agent browser, from the shell
gork browser open https://example.com
gork browser read [css-selector]
gork vault set gmail-login            # value comes from STDIN — never argv
gork vault list | rm <label>          # labels only; values are never shown
gork status                           # liveness + task count
gork secret                           # the pairing secret for the phone app
```

### The agent browser (private · persistent · lightweight)

A headless Chromium the AI drives exactly like a human — navigate, click,
type, read, back, scroll, screenshot — over the phone's tool registry
(`POST /v1/browser/op`). Three guarantees:

- **Private**: a dedicated profile at `$GORK_HOME/browser-profile`
  (mode 0700), never the host user's browser; secrets come from the sealed
  vault (`gork vault set`, value via stdin) and are injected into the
  focused input without ever appearing in a response, a log, or the model's
  context.
- **Persistent**: cookies and logins survive daemon restarts because the
  profile directory does.
- **Lightweight**: raw CDP over one WebSocket — no Playwright, no Node, no
  Selenium. The browser spawns lazily on the first op and dies with the
  daemon.

Needs a Chromium-family binary (`chromium` / `google-chrome`), or set
`GORK_BROWSER=/path/to/binary`. Debian: `apt install chromium`; Termux:
`pkg install chromium` (x11 repo).

## REST API

| Method | Path | What |
|--------|------|------|
| GET    | `/health`  | liveness check (no secret needed) |
| GET    | `/tasks`   | list tasks |
| POST   | `/tasks`   | add task `{title, prompt, repeatMinutes}` |
| DELETE | `/tasks/{id}` | remove a task |
| POST   | `/run`     | run all due tasks now |
| GET    | `/config`  | read config back (secrets redacted) |
| POST   | `/config`  | the phone's Sync-to-daemon action |
| GET    | `/v1/browser/status` | agent browser state + sessions |
| POST   | `/v1/browser/op` | `{session, action, ...args}` — one browser op |

All endpoints except `/health` require the `X-Gork-Secret` header or an
`Authorization: Bearer <secret>` when `GORK_SECRET` is set. The phone app
talks to the same API (set the endpoint in **Cloud Computer → AgentVPS**).

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
  not real systemd. The installer now detects this and uses `gork daemon
  start` instead; older installs left a dead unit behind, which is why
  nothing was listening.
- **`port 8787 already serves /health, but no pidfile points at it`** — a
  stale daemon from a previous install still owns the port. Find it with
  `ss -tlnp | grep 8787`, kill it, start again (or change `GORK_PORT`).
- **`found .../bin/gork_daemon.dart but dart is not installed`** —
  `pkg install dart` (Termux) or follow dart.dev (Debian).
- **Nothing is listening** — run `gork daemon logs` (or
  `journalctl -u gork-daemon -n 50`) and fix what the log says.
- **The browser tool answers `no browser binary found`** — no Chromium on
  the box: `apt install chromium` (Debian) / `pkg install chromium`
  (Termux, needs the x11 repo), or set `GORK_BROWSER=/path/to/chrome`.
