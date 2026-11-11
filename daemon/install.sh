#!/usr/bin/env bash
# gork daemon one-liner installer for a fresh Debian/Ubuntu VPS.
# Run on the VPS:  curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

echo "== gork daemon installer =="

echo "-- Installing base packages..."
$SUDO apt-get update -y
$SUDO apt-get install -y curl git unzip apt-transport-https

echo "-- Installing Dart SDK..."
if ! command -v dart >/dev/null 2>&1; then
  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/dart.gpg
  echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" \
    | $SUDO tee /etc/apt/sources.list.d/dart.list
  $SUDO apt-get update -y
  $SUDO apt-get install -y dart
fi

echo "-- Cloning gork..."
if [ ! -d /opt/gork ]; then
  $SUDO git clone https://github.com/webdevshayan/gork.git /opt/gork
else
  cd /opt/gork && $SUDO git pull || true
fi

echo "-- Installing daemon dependencies..."
cd /opt/gork/daemon
dart pub get

echo "-- Installing systemd service..."
$SUDO cp gork-daemon.service /etc/systemd/system/gork-daemon.service
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now gork-daemon

echo ""
echo "== Done. The daemon is listening on port 8787 =="
echo "Check it:    curl http://127.0.0.1:8787/health"
echo "Configure:   edit /etc/systemd/system/gork-daemon.service (GORK_API_KEY, NTFY_TOPIC), then:"
echo "             sudo systemctl daemon-reload && sudo systemctl restart gork-daemon"
