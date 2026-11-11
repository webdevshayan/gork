# Build environment (Movement 1)

The machine that forges every APK. Verified 2026-11-11.

| Piece | Value |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), 13.4 |
| Architecture | x86_64, 2 cores, 4 GB RAM |
| Flutter | 3.47.9 stable |
| Dart | 3.13.7 |
| JDK | Temurin OpenJDK 17.0.21+9 |
| Android cmdline-tools | 19.0 |
| Android platform | android-36 |
| Android build-tools | 36.0.0 |
| Android licenses | accepted |
| Editor | student's own — never specified |

## flutter doctor

```
Doctor summary (to see all details, run flutter doctor -v):
[✓] Flutter (Channel stable, 3.47.9, on Debian GNU/Linux 13 (trixie) 5.10.134-013.15.kangaroo.al8.x86_64, locale en_US)
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
