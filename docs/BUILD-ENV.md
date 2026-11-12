# Build environment (Movement 1)

The machine that forges every APK. Verified 2026-11-11.

| Piece | Value |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), 13.4 |
| Architecture | x86_64, 2 cores, 4 GB RAM |
| Flutter | 3.50.0 stable |
| Dart | 3.13.7 |
| JDK | OpenJDK 21.0.13 (Debian) |
| Android cmdline-tools | 19.0 |
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
