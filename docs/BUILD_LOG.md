# The movement log

Every change to gork lands as a *movement*: one branch, one pull request, one
squash commit, green tests before anything ships. This is the full history.
The README stays clean — the receipts live here.

| Movement | What landed |
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
| #19 | Gork Pro glass UI rebuild: ambient backdrop + glass shell (nav pill, bottom input), spec-exact Home / Chat / System Preferences |
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
| #32 | Images see: vision payloads ride to multimodal providers — base64 parts for OpenAI-compatible and Anthropic, honest markers when a file can't load |
| #33 | Update from within: GitHub releases check + APK download + honest system-installer handoff |
| #34 | Dark glass everywhere: Wallet rename, one-click connectors, app→daemon config sync |
| #35 | Slim release: strip the engine, gate the size, warn on bloat (v1.5.0 had shipped a 180 MB APK) |
| #36 | Release pipeline: `scripts/release_apk.sh` reads the version from pubspec, passes `--dart-define=GORK_VERSION`, runs the slim size gate — v1.6.0 is the first release built by the script and the first to carry Movements 34+35 to the phone |
| #37 | Build-box receipts: the full toolchain-rebuild recipe on paper (JRE-only JDK → extracted jdk21-root, llvm-19 debs → llvm19-root, NDK stub + strip shims, Aliyun patch, lint off) — tested, so the next rebuild cannot forget them |
| #38 | Profile is real: editable name/email form (persisted, defaults stay), one-click Google — pick an account, EVERY Google service binds at once — and an account selection screen; the menu gains Google + Theme rows |
| #47 | AI responses selectable; Updates page: full markdown notes, button on top |
| #48 | VPS request persistence: server job queue + app outbox; device death/app inactive can't cancel work |
| #49 | Cloud Console credentials sealed on the VPS (never read back); setup guide; YouTube frame+transcript ingestion |
| #45 | Chat home: the Chat tab is a recent-threads list (title, snippet, WhatsApp time); ChatPage + BottomInputBar shared components; compose opens new threads |
| #46 | One Projects UI: pushed screen = glass folder list; shared showProjectEditor sheet; ChatPage fallback hook; onAfterPush refresh |
| #41 | WhatsApp chat list: sticky date badges (PinnedHeaderSliver), time-only stamps, no Read receipts, synchronous history preload |
| #42 | One glass theme everywhere: Screen = glass scaffold (sky + chevron back) for ALL pushed screens, glass sheets, sliding nav pill + black active label, gork card removed |
| #43 | Separate screens + scoped search: top-left = search on every tab, slide-up overlay with scope chips, project chats push as full screens, backdrop RepaintBoundary |
| #44 | Accessibility loop: TalkBack labels, tab-control semantics, WCAG token guards, reusable GlassBackButton |
| #40 | UI fixes from v1.7.0 screenshots: a const home short-circuited the shell rebuild on theme change (stale dark glass over the light backdrop, unreadable white name) — de-const the gate chain; and the attach box now matches the mic box so the + no longer rides 4dp low on a single line |
| #39 | Theme modes become real: Light mode gets light glass (light fills, light borders, dark text), Dark stays, System follows the OS, **Auto follows the local clock** — one resolver drives MaterialApp, glass colors and the backdrop |
| #50 | Chat + dropdown, wallet row removed, black & white rounded theme, Security screen (PR #46) |
| #51 | Global chat: the Chat tab IS one never-deleted conversation; room-based memory on the VPS, one-call retrieval/mutation/add (PR #47) |
| #52 | Accounts screen (every site account the browser logged into) + AI full browser on the VPS + secure paste-fill — AI never sees secrets (PR #48) |
| #53 | Dynamic intro: one VPS request generates all first-run messages, played as separate animated bubbles (direct commit) |
| #54 | Google Messages chat polish (PR #49): date badges go INLINE (only the badge for the messages being viewed is visible, never two pinned), 16dp side padding on the message list, every message is a theme-aware solid bubble (ink user / surface AI, tighter sender-side corner), active top-tab chip is ink + white label in light mode, avatar ring follows the palette (dark in dark mode, never white), and ALL glass chrome repaints the frame the theme resolves — send arrow flips tone too |
| #55 | Screenshot-receipt fixes: Google Cloud Console card was painted UNDER the backdrop (invisible — the Menu → Google → Cloud Console → Upload path now works); Android system nav + status bars follow the theme (no white nav bar in dark mode); menu lists EVERY settings screen (Inbox / Panels / Cloud Computer added); attachments and compose land in THE global chat — nothing creates a new chat; chat viewport clips (no painting behind the nav pill); README + this log corrected against the code (keys-never-leave claim, 3→6 agent rounds, tab-pill wording, movement numbering) |
| #56 | Rename sweep Hark→Gork everywhere (files, classes, strings, docs); credentials upload picker shows ALL files — the FileType.custom ['json'] MIME filter hid browser-downloaded credentials.json (application/octet-stream), the "can't upload any file" bug — with the .json extension validated in-app; mic button in the message box wired to speech_to_text dictation (RECORD_AUDIO permission + RecognitionService query for Android 13+, partial results typed into the draft, tap again to stop, unavailable-snackbar fallback — it was a bare Padding with no handler); card-gap audit locked by tests — every screen stacking cards in a row or column keeps an 8–16px gap between pairs |
