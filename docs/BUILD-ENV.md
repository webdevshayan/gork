# Build environment (Movement 1)

The machine that forges every APK. Rebuilt from zero and re-verified 2026-11-14 — the receipts below are the recipe for the next rebuild.

| Piece | Value |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), 13.4 |
| Architecture | x86_64, 2 cores, 4 GB RAM |
| Flutter | 3.50.0 stable (`/home/z/tools/flutter`) |
| Dart | 3.13.7 |
| JDK | OpenJDK 21.0.13, locally extracted at `/home/z/tools/jdk21-root` (the sandbox ships a **JRE** — no `javac`) |
| Android cmdline-tools | latest (12.x) at `/home/z/tools/android-sdk/cmdline-tools/latest` |
| Android platform | android-36 |
| Android build-tools | 36.0.0 |
| Android licenses | accepted |
| Editor | student's own — never specified |

## flutter doctor

```
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.50.0, on Debian GNU/Linux 13 (trixie) 5.10.134-013.15.kangaroo.al8.x86_64, locale en_US)
[✓] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
[✗] Chrome - develop for the web (Cannot find Chrome executable at google-chrome)
    ! Cannot find Chrome. Try setting CHROME_EXECUTABLE to a Chrome executable.
[✗] Linux toolchain - develop for Linux desktop
    ✗ clang++ is required for Linux development.
      It is likely available from your distribution (e.g.: apt install clang), or can be downloaded from https://releases.llvm.org/
    ✗ CMake is required for Linux development.
      It is likely available from your distribution (e.g.: apt install cmake), or can be downloaded from https://cmake.org/download/
    ✗ ninja is required for Linux development.
      It is likely available from your distribution (e.g.: apt install ninja-build), or can be downloaded from https://github.com/ninja-build/ninja/releases
    ✗ GTK 3.0 development libraries are required for Linux development.
      They are likely available from your distribution (e.g.: apt install libgtk-3-dev)
    ! Unable to access driver information using 'eglinfo'.
      It is likely available from your distribution (e.g.: apt install mesa-utils)
[✓] Connected device (1 available)
[✓] Network resources

! Doctor found issues in 2 categories.
```

Note: the Chrome (web) and Linux desktop rows are unchecked on purpose.
This project builds Android APKs only.

## Build-system notes (added in Movement 11)

- Gradle runs with capped memory (`-Xmx1536m`) — the box has 4 GB RAM, no swap.
- Maven Central rate-limits this network (HTTP 429); Gradle uses the Aliyun
  mirrors first (public + google) in `settings.gradle.kts` and the root
  `build.gradle.kts`.
- The build target is `arm64-v8a`:
  `flutter build apk --release --split-per-abi --target-platform android-arm64`
- The NDK is a stub (`source.properties` only): no plugin ships native code
  after pinning the non-jni plugin versions. `llvm-strip`/`llvm-objcopy` are
  shims over a locally extracted `llvm-19` (Debian .debs), because GNU
  binutils here is x86-64-only.
- `core library desugaring` is enabled (required by flutter_local_notifications).
- Minimum SDK is 23 (`flutter_secure_storage` requirement).

## Toolchain notes (re-verified 2026-11-13)

- The included flutter_tools gradle build does NOT inherit this repo's Aliyun
  ordering — upstream ships `packages/flutter_tools/gradle/settings.gradle.kts`
  with `google() + mavenCentral()` only, so `kotlin-build-tools-impl` 429s and
  `assembleRelease` dies before compiling anything. After every flutter
  install/upgrade run `scripts/patch_flutter_tools_repos.sh` once (idempotent;
  leaves a `.bak-gork` backup).
- cmdline-tools 19.0 deprecates the `sdkmanager` binary — the shim now warns
  and delegates to the bundled `android` CLI. Licenses and package installs
  still work through it; the warning is noise.
- The NDK stays a stub (`source.properties` only, revision
  28.2.13676358 — Flutter 3.50's pin in `FlutterExtension.kt`), with
  `llvm-strip`/`llvm-objcopy` shims running over an extracted llvm-19
  (Debian `llvm-19` + `libllvm19` debs, `LD_LIBRARY_PATH` set in the shim).

## Rebuild receipts (2026-11-14 — full toolchain rebuild from zero)

Every step below was needed and each missed step cost a failed release
build. There is no root apt on this box and `sudo` asks for a password it
will never get: system packages are installed by downloading Debian .debs
(`apt-get download <pkg>` — no root needed) and extracting them locally
with `dpkg-deb -x <deb> <dir>`.

1. **Flutter** — stable tarball into `/home/z/tools/flutter`, on PATH via
   `/home/z/my-project/scripts/env.sh` (exports `GORK_ROOT TOOLS JAVA_HOME
   ANDROID_HOME GRADLE_USER_HOME PUB_CACHE PATH`; source it in every shell).
2. **Android SDK** — cmdline-tools under `/home/z/tools/android-sdk`,
   then `yes | sdkmanager --licenses` and
   `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"`.
3. **flutter_tools repository patch** — run
   `scripts/patch_flutter_tools_repos.sh` once (Aliyun before mavenCentral
   in the included build; otherwise `kotlin-build-tools-impl` 429s and
   `assembleRelease` dies in 15 s — this killed v1.6.0 build attempt #1).
4. **JDK with `javac`** — the sandbox's `/usr/lib/jvm/java-21-openjdk-amd64`
   is JRE-only; gradle dies with "does not provide the required
   capabilities: [JAVA_COMPILER]" after five minutes of real work
   (v1.6.0 attempt #2). Fix: `apt-get download openjdk-21-jdk-headless
   openjdk-21-jre-headless`, extract both into `/home/z/tools/jdk21-root`,
   point `JAVA_HOME` there (env.sh does). The JRE deb is required — the
   JDK deb alone lacks `libjli.so` and `javac` cannot even start.
5. **llvm-19 for the strip shims** — `apt-get download llvm-19 libllvm19`,
   extract into `/home/z/tools/llvm19-root`. GNU binutils here is
   x86-64-only; AGP's strip step needs an arm64-capable `llvm-strip`.
6. **NDK stub** — create `/home/z/tools/android-sdk/ndk/28.2.13676358/`
   with a `source.properties` containing `Pkg.Revision = 28.2.13676358`
   (Flutter 3.50's pin). Without it gradle tries to fetch a multi-GB NDK.
   Then lay the shims at
   `ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/`:
   `llvm-strip`/`llvm-objcopy` scripts that set
   `LD_LIBRARY_PATH=/home/z/tools/llvm19-root/usr/lib/llvm-19/lib` and exec
   `/home/z/tools/llvm19-root/usr/lib/llvm-19/bin/<tool>`.
7. **Release lint off** — `checkReleaseBuilds = false` (see
   `android/app/build.gradle.kts`); lint-vital OOMs the capped 1 GB gradle
   JVM in metaspace after a full compile (v1.6.0 attempt #3).
8. **Build** — `scripts/release_apk.sh` (reads the version from pubspec,
   passes `--dart-define=GORK_VERSION`, runs the size gate). Proven twice:
   v1.6.0 (attempt #4, green) and v1.6.1.
