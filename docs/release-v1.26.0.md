# v1.26.0 — Movement 70: Anything, Securely

The agent can now finish sign-ins and arbitrary web tasks end-to-end — and gained a real command line on its own VPS — with every security invariant intact.

## The browser can finally SEE
- New `describe` action: screenshot on the VPS → the phone's own vision model → an exhaustive, literal text description of every field, button, link and visible prompt. The AI stops guessing what a form asks for and never needs the user to read the page aloud.
- Both engines return the same `base64` PNG shape (agent-browser CLI and the daemon fallback).

## The browser stops dying mid-load
- Daemon 0.6.0 self-heal: if the browser process exits before the page loads (OOM, crash), the next op relaunches it and replays once — reported honestly as `revived: true`. (Fixes "browser exited before the page loaded".)
- New `wait` action: poll for milliseconds, a selector, or visible text — instead of guessing.
- New `press` action: real key events (Enter to submit, Tab, Escape, arrows) for forms that ignore clicks.
- Server 1.13: read-only browser ops replay once on transient death; side-effecty ops (click/fill/drag) never double-run.
- Movement 69.1 (already shipped): `drag`/`slide` for slider puzzles.

## A command line on its own VPS — gated
- New `vps_shell` tool: the agent can install packages, run scripts, manage files on the user's VPS.
- **OFF by default.** Enable with `GORK_SHELL=1` in the server environment. When off, the AI gets the honest error and tells you how to enable it.
- When on: same bearer auth as every endpoint, a CLEAN child environment (the server's tokens never reach a command), 1–300 s hard timeout, 100 KB output cap, every call audited to the server log.

## Security invariants (unchanged, re-tested)
- Secret values NEVER cross the AI wire — vault labels only; `fill_secret` fills the focused input.
- The vision prompt is fixed server-side/app-side; the AI sees a description, never the page's password fields unmasked by context.
- Shell commands never see server secrets; output is redacted on errors.

## Internals
- 452 app tests + 101 daemon tests + 31 server tests, all green.
- Fixed a v1.25.0 regression: the browser-driver factory reference was deleted (every browser op would have failed).
- Daemon 0.6.0 ships via `gork daemon update`; the Python server updates via `git pull` on the VPS.

**Install paths for the browser engine:** normal Linux VPS (x64/arm64, glibc/musl): `npm i -g agent-browser && agent-browser install --with-deps`. Termux/arm64: `pkg install chromium` — the daemon's built-in browser is used automatically, no CLI needed.
