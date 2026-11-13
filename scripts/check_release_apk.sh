#!/usr/bin/env bash
# Movement 35 release gate — a bloated release must never ship silently.
#
# Regression being guarded: gork v1.5.0 shipped a 180 MB APK because the
# release build packaged the unstripped Flutter engine (libflutter.so =
# 169 MB of debug symbols) instead of the normal ~11 MB stripped engine.
# The engine artifact on download.flutter.io ships unstripped upstream and
# AGP's strip step is what slims it; v1.5.0's build disabled that strip to
# avoid the NDK, so nothing in the build log screamed — the artifact size
# is the only honest signal we get.
#
# Usage: scripts/check_release_apk.sh <path-to.apk>
# Exit 0 = sane release. Exit 1 = BLOATED RELEASE BLOCKED.
set -euo pipefail

APK="${1:-}"
LIBFLUTTER_MAX_BYTES=16777216  # 16 MiB — stripped engine is ~11-13 MB
APK_MAX_BYTES=125829120        # 120 MiB — stripped builds historically 19-35 MB

fail() { echo "BLOATED RELEASE BLOCKED: $*" >&2; exit 1; }

[ -f "$APK" ] || fail "no APK at '$APK'"
unzip -l "$APK" >/dev/null 2>&1 || fail "'$APK' is not a readable zip archive"

apk_bytes=$(stat -c%s "$APK")
echo "APK: $APK ($apk_bytes bytes)"
if [ "$apk_bytes" -gt "$APK_MAX_BYTES" ]; then
  fail "whole APK is $apk_bytes bytes (limit $APK_MAX_BYTES) — debug symbols are almost certainly riding along"
fi

libflutter_bytes=$(unzip -l "$APK" 'lib/*/libflutter.so' 2>/dev/null \
  | awk '/libflutter\.so/ { sum += $1 } END { print sum + 0 }')
echo "libflutter.so total: $libflutter_bytes bytes"
if [ "$libflutter_bytes" -gt "$LIBFLUTTER_MAX_BYTES" ]; then
  fail "libflutter.so is $libflutter_bytes bytes (limit $LIBFLUTTER_MAX_BYTES) — the unstripped engine got packaged (v1.5.0 regression)"
fi

echo "Size gate passed: slim release, no debug engine aboard."
