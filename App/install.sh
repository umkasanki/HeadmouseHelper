#!/bin/bash
# Build and install HeadmouseHelper into /Applications, then relaunch it.
# Installing to a stable location (not build/) keeps the Input Monitoring grant
# and login-item registration attached to one path.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

./App/build-app.sh

echo "Installing to /Applications..."
osascript -e 'quit app "HeadmouseHelper"' 2>/dev/null || true
killall HeadmouseHelper 2>/dev/null || true
sleep 1
rm -rf /Applications/HeadmouseHelper.app
cp -R build/HeadmouseHelper.app /Applications/HeadmouseHelper.app

open /Applications/HeadmouseHelper.app
echo "Installed and launched /Applications/HeadmouseHelper.app"
