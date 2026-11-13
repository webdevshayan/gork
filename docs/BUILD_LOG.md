# The movement log

Every change to gork lands as a *movement*: one branch, one pull request, one
squash commit, green tests before anything ships. This is the full history.
The README stays clean — the receipts live here.

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
| #16 | First-run onboarding wizard |
| #17 | Release v1.0.0 |
| #18 | v1.0.0 test & release report |
| #19 | Hark Pro glass UI rebuild: ambient backdrop + glass shell (nav pill, bottom input), spec-exact Home / Chat / System Preferences |
| #20 | Daemon self-hosts anywhere: Termux + proot + no-systemd backends (gork-daemonctl), missing bin entrypoint fixed, /health-gated honest installs |
| #21 | Navigation corrections: contextual left button (+ dropdown / settings / back), profile-driven settings, offline avatar (person icon), auto-resizing input |
| #22 | Offline ambient backdrop (bundled sky, no black flash) + contrast overlays (white in light, black in dark) + new glass-g launcher icon |
| #23 | Projects are folders: chats + files + images live inside, shell-scoped conversations |
| #24 | Safe markdown for AI responses: CommonMark + GFM, zero web views, HTML inert, no fetches |
| #25 | gork CLI: configure LLMs, tasks, secrets and everything from the terminal — no file editing |
| #27 | Attachments are real: Camera / Photos / Files from the + menu land in the thread and mirror into project folders |
| #28 | README rebuilt for humans: build log hidden, MIT license |
| #29 | Chat search: the menu Search pill opens real conversation search with honest empty states |
| #30 | NDK-free release builds: official repos first, Aliyun before central, no gradle daemon |
| #31 | Attachments speak: text files feed the agent their real content — binaries and images stay honest markers |
