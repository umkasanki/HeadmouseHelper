#!/bin/bash
# Save / apply / list tremor-stabilization presets, for A/B testing which
# algorithm + parameters feel best. Presets live in presets/tremor/<name>.json
# and contain a TremorSettings object (enabled, algorithm, strength, deadzone).
#
#   ./tools/tremor-preset.sh list
#   ./tools/tremor-preset.sh save <name>    # snapshot the app's current tremor
#   ./tools/tremor-preset.sh apply <name>   # load a preset + relaunch the app
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="presets/tremor"
SETTINGS="$HOME/Library/Application Support/HeadmouseHelper/settings.json"
CMD="${1:-list}"

case "$CMD" in
  list)
    echo "Presets in $DIR:"
    ls "$DIR" 2>/dev/null | sed 's/\.json$//' | sed 's/^/  /' || echo "  (none)"
    ;;

  save)
    NAME="${2:?usage: tremor-preset.sh save <name>}"
    mkdir -p "$DIR"
    python3 - "$SETTINGS" "$DIR/$NAME.json" <<'PY'
import json, sys, os
settings_path, out = sys.argv[1], sys.argv[2]
s = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
tremor = s.get("tremor", {})
json.dump(tremor, open(out, "w"), indent=2)
print("saved:", json.dumps(tremor))
PY
    echo "Saved current tremor as '$NAME'."
    ;;

  apply)
    NAME="${2:?usage: tremor-preset.sh apply <name>}"
    PRESET="$DIR/$NAME.json"
    [ -f "$PRESET" ] || { echo "No preset: $PRESET"; "$0" list; exit 1; }
    osascript -e 'quit app "HeadmouseHelper"' 2>/dev/null || true
    killall HeadmouseHelper 2>/dev/null || true
    sleep 1
    python3 - "$PRESET" "$SETTINGS" <<'PY'
import json, sys, os
preset_path, settings_path = sys.argv[1], sys.argv[2]
s = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
s["tremor"] = json.load(open(preset_path))
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
json.dump(s, open(settings_path, "w"), indent=2)
print("applied:", json.dumps(s["tremor"]))
PY
    open /Applications/HeadmouseHelper.app
    echo "Applied preset '$NAME' and relaunched."
    ;;

  *)
    echo "usage: tremor-preset.sh {list | save <name> | apply <name>}"
    exit 1
    ;;
esac
