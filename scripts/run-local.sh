#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="capcap"
APP_BUNDLE="build/$APP_NAME.app"

echo "==> Building $APP_NAME (local bundle, not /Applications)..."
bash scripts/bundle.sh

echo "==> Stopping running $APP_NAME..."
pkill -x "$APP_NAME" 2>/dev/null || true
for i in $(seq 1 30); do
    pgrep -x "$APP_NAME" >/dev/null || break
    sleep 0.1
done
pkill -9 -x "$APP_NAME" 2>/dev/null || true

xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "==> Launching $APP_BUNDLE"
# --skip-permission-gate lets the menu bar come up even if TCC still
# reports unauthorized (ad-hoc / first grant). Screenshot still needs
# a real Screen Recording grant for the overlay to capture.
open "$APP_BUNDLE" --args --skip-permission-gate

for i in $(seq 1 50); do
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "==> $APP_NAME is running (PID: $(pgrep -x "$APP_NAME"))"
        echo "    binary: $(ps -o command= -p "$(pgrep -x "$APP_NAME")")"
        exit 0
    fi
    sleep 0.1
done

echo "==> $APP_NAME did not start within 5 seconds."
exit 1
