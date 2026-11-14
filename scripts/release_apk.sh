#!/usr/bin/env bash
# Movement 36 — one command, honest release.
#
# Why this exists: kAppVersion is only real when --dart-define=GORK_VERSION
# reaches the build. No script in the repo passed it, so every release so
# far was built by hand — and a hand build without the define reports
# kAppVersion='dev', against which the in-app updater never offers a newer
# release (parseVersion('dev') is empty → "up to date" forever). Movement
# 35's slim build also sat unreleased because rebuilding meant re-deriving
# the whole ritual from memory. This script IS the ritual:
#
#   pubspec version → flutter build apk --release --dart-define=GORK_VERSION
#                   → scripts/check_release_apk.sh (bloat gate)
#
# A bloated APK (the v1.5.0 regression, 180 MB) can no longer ship silently
# and an unversioned APK can no longer ship at all.
#
# Usage:
#   scripts/release_apk.sh            # build + gate
#   scripts/release_apk.sh --dry-run  # print the plan, touch nothing
#   DRY_RUN=1 scripts/release_apk.sh  # same as --dry-run
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root, wherever it is invoked from

VERSION=$(sed -n 's/^version: \([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml)
BUILD=$(sed -n 's/^version: [0-9][0-9.]*+\([0-9]*\)$/\1/p' pubspec.yaml)
if [ -z "$VERSION" ] || [ -z "$BUILD" ]; then
  echo "FATAL: pubspec.yaml has no parseable 'version: X.Y.Z+N' line" >&2
  exit 1
fi

APK="build/app/outputs/flutter-apk/app-release.apk"

if [ "${1:-}" = "--dry-run" ] || [ "${DRY_RUN:-0}" = "1" ]; then
  echo "version: $VERSION+$BUILD"
  echo "dart-define: GORK_VERSION=$VERSION"
  echo "build: flutter build apk --release --dart-define=GORK_VERSION=$VERSION"
  echo "gate: scripts/check_release_apk.sh $APK"
  exit 0
fi

flutter build apk --release --dart-define=GORK_VERSION="$VERSION"
scripts/check_release_apk.sh "$APK"
echo "release ready: $APK — gork $VERSION+$BUILD, size gate passed."
