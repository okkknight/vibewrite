#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VibeWrite"
SCHEME="VibeWrite"
PROJECT="VibeWrite.xcodeproj"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    build
}

launch_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stream_logs() {
  /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
}

case "$MODE" in
  run)
    stop_app
    build_app
    launch_app
    ;;
  --debug|debug)
    stop_app
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_app
    build_app
    launch_app
    stream_logs
    ;;
  --telemetry|telemetry)
    stop_app
    build_app
    launch_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"com.knightspace.vibewrite\""
    ;;
  --verify|verify)
    stop_app
    build_app
    launch_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
