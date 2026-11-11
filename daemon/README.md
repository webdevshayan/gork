# gork daemon

The companion daemon that makes gork work 24/7 — even when the phone is
asleep. It runs on **your own VPS** (any Debian/Ubuntu box, ~4 EUR/month is
plenty), holds the schedule, calls your LLM when tasks are due, and pushes
the results to your phone through ntfy (free, no account).

## Install (one-liner on a fresh VPS)

```bash
curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash
```

What it does: installs Dart, clones this repo to `/opt/gork`, installs the
daemon's dependencies, registers a systemd service and starts it on port
8787.

## Configure

Edit `/etc/systemd/system/gork-daemon.service`:

- `GORK_API_KEY` — your LLM key (stays on your VPS, never anywhere else).
- `GORK_BASE_URL` + `GORK_MODEL` — any OpenAI-compatible provider
  (OpenAI, OpenRouter, Gemini's OpenAI shim, a local LLM, …).
- `NTFY_TOPIC` — optional. Pick a long random topic name, then subscribe to
  that topic in the ntfy app on your phone. Task results arrive as push
  notifications.

Then: `sudo systemctl daemon-reload && sudo systemctl restart gork-daemon`

## REST API

| Method | Path       | What                       |
|--------|------------|----------------------------|
| GET    | `/health`  | liveness check             |
| GET    | `/tasks`   | list tasks                 |
| POST   | `/tasks`   | add task `{title, prompt, repeatMinutes}` |
| DELETE | `/tasks/{id}` | remove a task           |
| POST   | `/run`     | run all due tasks now      |

The phone app talks to the same API (set the endpoint in
**Cloud Computer → AgentVPS**).
