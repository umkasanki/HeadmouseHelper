#!/bin/bash
# Assemble a runnable HeadmouseHelper.app WITHOUT Xcode — Command Line Tools only.
# Run on macOS:
#   ./App/build-app.sh && open build/HeadmouseHelper.app
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

APP="build/HeadmouseHelper.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "[1/4] Building core (swift build)..."
swift build

echo "[2/4] Assembling $APP..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "[3/4] Compiling app layer against AppKit / SwiftUI / IOKit..."
swiftc \
    -framework AppKit \
    -framework SwiftUI \
    -framework IOKit \
    -I .build/debug/Modules \
    $(find App/HeadmouseHelper -name "*.swift") \
    .build/debug/HeadmouseCore.build/*.o \
    -o "$MACOS/HeadmouseHelper"

cp App/Info.plist "$APP/Contents/Info.plist"

# Bundle resources if any exist (icons etc.).
if [ -d App/HeadmouseHelper/Resources ]; then
    cp -R App/HeadmouseHelper/Resources/ "$RES/" 2>/dev/null || true
fi

echo "[4/4] Code signing..."
# Prefer the stable self-signed identity so the Input Monitoring grant persists
# across rebuilds; fall back to ad-hoc (grant resets each build) if not set up.
IDENTITY="HeadmouseHelper Self-Signed"
KC="$HOME/Library/Keychains/headmousehelper.keychain-db"
if [ -f "$KC" ] && security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
    echo "  using stable identity: $IDENTITY"
    security unlock-keychain -p headmousehelper "$KC" 2>/dev/null || true
    codesign --force --sign "$IDENTITY" --keychain "$KC" "$APP"
else
    echo "  stable identity not found -> ad-hoc (grant will reset each build)."
    echo "  run ./App/setup-signing.sh once to make the Input Monitoring grant persist."
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
echo "  Launch:  open $APP"
