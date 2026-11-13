<div align="center">

# gork

**A free, open-source personal AI operating system for Android.**

One chat that knows your life. Projects that hold your work. A daemon that
runs 24/7 on hardware you own. Bring your own API key — there are no accounts,
no servers, no subscriptions.

[Download the APK](https://github.com/webdevshayan/gork/releases) ·
[Self-host the daemon](#self-host-the-247-daemon) ·
[Contributing](#contributing)

![Release](https://img.shields.io/github/v/release/webdevshayan/gork?style=flat-square&color=black)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square)
![Built with](https://img.shields.io/badge/built_with-Flutter-02569B?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-black?style=flat-square)

</div>

---

## Why gork exists

The best AI assistants today rent you access to *your own context*. Your
history lives in someone else's cloud, your automations run on their schedule,
and the moment the subscription ends, the memory of your life walks out the
door with them.

gork is the opposite bet. **Your keys never leave your phone** (encrypted in
the Android keystore), **your history lives in your device storage**, and the
piece that needs to run 24/7 — the companion daemon — runs on a VPS or a Termux
box *you* control, reachable through a shared secret only your phone knows.
The app talks to whatever OpenAI-compatible endpoint you point it at: OpenAI,
OpenRouter, Gemini, Anthropic, a local llama.cpp server, anything.

And it is built in public, one *movement* at a time: every pull request is a
small, working, fully tested step, merged only when the whole suite is green.
No roadmap theater — the [movement log](docs/BUILD_LOG.md) is the roadmap.

## What's inside

| Area | What works today |
|---|---|
| Chat | Glass chat UI, safe markdown answers (CommonMark + GFM, no web view, HTML inert), persisted history, provider picker |
| Attachments | The + menu really attaches: Camera, Photos and Files land in the thread and mirror into the project folder |
| Agent | Tool-calling loop (memory, projects, tasks, panels, vault, weather) — up to 3 rounds on the OpenAI tool protocol |
| Memory | Cross-session facts, injected into every conversation |
| Projects | Folders that hold their own chats plus shared resources — files, images, notes |
| Search | The menu Search pill opens real chat search — hits across conversations, feature jumps, recent threads |
| Vault | Encrypted secrets with reveal/copy, keystore-backed |
| Scheduled tasks | Timed prompts, results delivered as local notifications |
| Integrations | GitHub, Slack, Strava, Spotify, Gmail, PayPal — BYO token, each an agent tool |
| Panels | Mini-dashboards: live Open-Meteo weather (no key) + manual panels |
| Daemon | Dart companion server for 24/7 operation: REST + scheduler + ntfy push, installs anywhere (systemd, Termux, plain ctl) |
| CLI | `gork` — configure LLMs, secrets, ports and tasks entirely from the terminal |

The interface follows one rule: **every pixel answers to the reference
design.** Frosted glass over an offline ambient sky (bundled asset — nothing
fetched), white wash in light mode, dark scrim in dark mode, a black pill for
the active tab, and no black flash on cold start.

## Get the app

Grab the latest APK from the
[Releases page](https://github.com/webdevshayan/gork/releases) and open it on
your phone (allow *install unknown apps* for your file manager when prompted).

Or build it yourself:

```bash
git clone https://github.com/webdevshayan/gork.git
cd gork
flutter pub get
flutter test            # every commit ships green
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

## Self-host the 24/7 daemon

The daemon is what lets a phone assistant actually *do* things while you
sleep. It installs itself — detecting systemd, Termux/runit, or falling back
to a plain pidfile controller — and health-gates every success message, so a
broken install fails honestly instead of pretending.

```bash
curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash
```

Then configure everything from the terminal — **no file editing, ever**:

```bash
gork llm providers                      # see the supported endpoints
gork llm set openrouter                 # base URL + model, one command
gork config set GORK_API_KEY sk-...     # your key, stored 0600-local
gork llm test                           # ok (openrouter/gpt-oss-120b @ ...)
gork tasks add "Morning brief" "summarize my inbox" 60
gork status                             # daemon liveness + task count
gork secret                             # pairing secret for the phone app
```

Pairs with the app through **Cloud Computer → AgentVPS** using that secret.
Full details, including Termux and no-systemd boxes, live in
[`daemon/README.md`](daemon/README.md).

## Privacy & security

- **Keys**: encrypted in the Android keystore, per-provider namespaced. Never
  logged, never synced.
- **Network**: the only traffic is you → your LLM endpoint and you → the
  integrations you configure. The ambient backdrop is a bundled asset.
- **Daemon**: local REST API guarded by a shared secret (`/health` is the one
  unauthenticated liveness endpoint, by design).
- **Markdown**: rendered with a hand-built widget tree on the `markdown`
  parser — no web view exists in the app, so no script can ever execute and
  nothing is ever fetched from an answer.

## Contributing

gork moves in movements, and the bar is simple:

1. Branch from `main`.
2. Write the failing test first, then make it pass.
3. `flutter test` (app) and `dart test` (daemon) must be fully green.
4. One pull request, one concern; it squash-merges and the branch is deleted.

The [movement log](docs/BUILD_LOG.md) shows what a finished movement looks
like. If you are fixing a bug, the regression test *is* the pull request —
everything else is commentary.

## License

[MIT](LICENSE) — © Shayan Ali Jalbani. Do anything; attribution appreciated.
