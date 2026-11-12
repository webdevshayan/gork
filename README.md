# gork

A free, open-source personal AI assistant for Android — an open-source
alternative inspired by Hark Pro. Built in public, one pull request at a time.

## Principles

- **BYOK** — bring your own API key (OpenAI, OpenRouter, Gemini, Anthropic,
  or any OpenAI-compatible endpoint). Keys stay on the device, encrypted in
  the Android keystore. Nothing is sent to our servers (there are none).
- **Every merged PR is a small, working, tested step.** No APK ships until
  the whole test suite passes.
- **Android APK only** — no accounts, no payments, no app store.
- **24/7 via your own VPS** — the companion daemon runs on hardware you own.

## Features (v0.1.0)

| Area | What works today |
|---|---|
| Chat | Full chat UI over one unified LLM client; history persisted; provider picker |
| BYOK providers | 5 providers per spec table; per-provider namespaced secure keys; Test Connection |
| Agent | Tool calling loop (up to 3 rounds, OpenAI tool protocol): memory, projects, tasks, panels, vault, weather |
| Memory | Cross-session facts, injected into every conversation |
| Projects | Workspaces with notes and text files |
| Vault | Encrypted secrets with reveal/copy, keystore-backed |
| Scheduled tasks | Timed prompts, results as local notifications |
| Cloud Computer | AgentVPS (self-hosted) / Browser Use Cloud / openbrowse, with health check |
| Daemon | Dart companion server: `/health`, task CRUD, scheduler, ntfy push, systemd installer |
| Panels | Mini-dashboards: live Open-Meteo weather panel (no key) + manual panels |
| Inbox | Proactive suggestions from live signals; sensitive actions confirm first |
| Ambient UI | Time-of-day accent shifts + weather-aware tint, contrast-checked |

## Test suite

Every PR runs `flutter test` (63+ tests: units, widget flows, mocked HTTP,
WCAG contrast checks) and `dart test` for the daemon.

## The APK

Download the latest release APK from the
[Releases page](https://github.com/webdevshayan/gork/releases), or build it:

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Install: copy the APK to your Android phone and open it (allow
"install unknown apps" for your file manager when prompted).

## Build log

| PR | What landed |
|---|---|
| bootstrap | README + build environment report (`flutter doctor` ✓ Android) |
| #1 | Flutter app skeleton + first passing test (red → green) |
| #2 | Design system: tokens (spacing/colors/typography/radius/elevation) + Screen/Button/Card |
| #3 | BYOK core: provider table, secure vault, unified LLM client |
| #4 | App shell + Providers settings + Test Connection |
| #5 | Chat UI + persisted history + persistent memory |
| #6 | Projects workspaces + encrypted Vault |
| #7 | Scheduled tasks + scheduler + local notifications |
| #8 | Cloud Computer settings + companion daemon |
| #9 | Panels + live weather + ambient theming |
| #10 | Agent tool loop + Inbox with real actions |
| #11 | Release polish + first release APK |
| #12 | Integration framework + GitHub integration (notifications, issues) |
| #13 | Slack, Strava, Spotify integrations with agent tools |
| #14 | Gmail + PayPal integrations (unread mail, transactions) |
| #15 | 24/7 Handoff: task sync with the daemon + shared-secret auth |
