#!/bin/bash
# Captures the README screenshots from a Debug build of Macfin, signed in to the demo server.
#
# Run scripts/demo-library.sh first. The app is built with its own bundle ID, so it has its own
# keychain item, preferences and sandbox container, and never touches an installed copy of Macfin.
# Each screen is opened in the background (open -g) and captured by window ID: nothing takes focus.
#
# Usage: scripts/screenshots.sh [language]   (default: en; for example fr)
# Output: docs/screenshots/{home,library,details,player}.png (docs/screenshots/<language>/ if not en)

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEMO=${MACFIN_DEMO_DIR:-$ROOT/.demo}
PORT=${MACFIN_DEMO_PORT:-8097}
LANGUAGE=${1:-en}
WINDOW=1440x900          # window content size, in points
WIDTH=1920               # width of the published PNGs, in pixels
BUNDLE_ID="$(awk '/PRODUCT_BUNDLE_IDENTIFIER:/ {print $2}' "$ROOT/project.yml").demo"
OUT="$ROOT/docs/screenshots"; [[ "$LANGUAGE" != en ]] && OUT="$OUT/$LANGUAGE"
RAW="$DEMO/screenshots/$LANGUAGE"
APP="$DEMO/build/Build/Products/Debug/Macfin.app"

log() { printf '\033[1m%s\033[0m\n' "$*"; }

curl -fsS -m 2 "http://127.0.0.1:$PORT/System/Info/Public" >/dev/null \
  || { echo "The demo server isn't running: run scripts/demo-library.sh first." >&2; exit 1; }

log "Building the demo copy ($BUNDLE_ID)"
cd "$ROOT"
[[ -d Macfin.xcodeproj ]] || xcodegen generate >/dev/null
xcodebuild -project Macfin.xcodeproj -scheme Macfin -configuration Debug -derivedDataPath "$DEMO/build" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build > "$DEMO/build.log" 2>&1 \
  || { tail -20 "$DEMO/build.log"; exit 1; }
mkdir -p "$DEMO/bin" "$RAW" "$OUT"
swiftc -O "$ROOT/scripts/window-id.swift" -o "$DEMO/bin/window-id"

# shot <name> <screen> [seconds to wait] [extra VAR=value...]
shot() {
  local name=$1 screen=$2 wait=${3:-6}; shift 3 || shift $#
  local envs=(--env MACFIN_DEMO_SERVER="http://127.0.0.1:$PORT" --env MACFIN_DEMO_USER=demo
              --env MACFIN_DEMO_PASSWORD=demo --env MACFIN_DEMO_WINDOW="$WINDOW" --env MACFIN_DEMO_SCREEN="$screen")
  for extra in "$@"; do envs+=(--env "$extra"); done
  open -g -n -F "${envs[@]}" "$APP" --args -AppleLanguages "($LANGUAGE)"
  local pid=""
  for _ in $(seq 1 40); do pid=$(pgrep -n -f "$APP/Contents/MacOS/Macfin" || true); [[ -n "$pid" ]] && break; sleep 0.25; done
  [[ -z "$pid" ]] && { echo "Macfin didn't start." >&2; exit 1; }
  sleep "$wait"
  local id; id=$("$DEMO/bin/window-id" "$pid")
  screencapture -x -o -l "$id" "$RAW/$name.png"
  kill "$pid"; while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
  log "  $name.png"
}

log "Capturing ($LANGUAGE)"
shot home home 8
shot library grid 8
shot details "detail:Sintel" 6
shot player "player:Spring@54" 9 MACFIN_DEMO_PREVIEW=0.19

log "Optimizing"
python3 - "$RAW" "$OUT" "$WIDTH" <<'PY'
import sys, pathlib
from PIL import Image
raw, out, width = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3])
for src in sorted(raw.glob("*.png")):
    image = Image.open(src).convert("RGB")
    image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
    # Full color: a 256-color palette bands the backdrops' gradients and skin tones.
    image.save(out / src.name, optimize=True)
    print(f"  {src.name}: {(out / src.name).stat().st_size // 1024} KB, {image.width}x{image.height}")
PY
