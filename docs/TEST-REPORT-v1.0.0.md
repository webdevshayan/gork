# gork v1.0.0 — Test & Release Report

Date: 2026-11-12 · Built and verified in the gork build box (Debian 13.4 "trixie").

## What ships in v1.0.0

| Area | Status |
|---|---|
| BYOK chat (OpenAI, OpenRouter, Gemini, Anthropic, custom OpenAI-compatible) | done |
| Agent tool loop: memory, projects, tasks, panels, vault, weather | done |
| Service integrations: GitHub, Slack, Strava, Spotify, Gmail, PayPal (BYO token) | done |
| Proactive Inbox with one-tap (and confirm-first) actions | done |
| Panels: live weather + manual dashboards, ambient theming | done |
| Projects workspaces · encrypted Vault · persistent memory | done |
| Scheduled tasks + local notifications | done |
| Cloud Computer: AgentVPS / Browser Use Cloud / openbrowse | done |
| 24/7 Handoff: companion daemon sync + shared-secret auth | done |
| First-run onboarding · light/dark ambient UI (WCAG-checked) | done |

## Verification against the release commit (3c09b15 + report PR)

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings (16 info-level lints) |
| `flutter test` (app) | **125 / 125 passed** |
| `dart test` (companion daemon) | **6 / 6 passed** |
| Release build `flutter build apk --release` | succeeded |

Coverage includes: unit tests for every store/service, mocked-HTTP tests for
every external API (LLM providers, GitHub, Slack, Strava, Spotify, Gmail,
PayPal, Open-Meteo, daemon REST), widget tests for all screens and flows,
and WCAG contrast checks for both themes.

## The APK

| Property | Value |
|---|---|
| File | `gork-v1.0.0.apk` |
| Size | 52.5 MB (52,480,081 bytes) |
| SHA-256 | `9f3d4759b226422efcbee1d4b9d099a7f412dd92c1fbec60c6ef30d599baf5ad` |
| Package | `dev.shayan.gork` |
| Version | 1.0.0 (versionCode 1) |
| ABIs | arm64-v8a, armeabi-v7a, x86_64 |
| Target SDK | 36 (Android 16), minSdk 23 (Android 6) |
| Signing | debug keystore (sideload-install testing build) |

Install: copy the APK to the phone, open it, allow "install unknown apps"
when prompted. No network permissions beyond what the LLM providers and
integrations you configure need; API keys and tokens never leave the device
except to the service they belong to.

## Known limitations (by design, free & open-source)

- Gmail/Spotify tokens are user-supplied OAuth **access tokens** and expire;
  paste a fresh one when they do (no embedded OAuth browser flow — keeps the
  app free of any hosted component).
- PayPal uses client-credentials; prefix the token with `sandbox:` to target
  the PayPal sandbox.
- 24/7 operation requires your own VPS running `daemon/` (one-line install
  script included; optional `GORK_SECRET` protects the endpoints).
- Scheduled tasks fire only while the app/daemon can run; Android may throttle
  background work on aggressive OEMs.
