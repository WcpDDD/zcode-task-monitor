#!/usr/bin/env bash
# uninstall.sh — reverses install.sh.
set -euo pipefail

PLUGIN_NAME="task-monitor"
PLUGIN_VERSION="0.1.0"
MARKETPLACE="zcode-plugins-official"
APP_BUNDLE="ZCodeTaskMonitor.app"

ZCODE_HOME="${ZCODE_HOME:-$HOME/.zcode}"
CACHE_DIR="$ZCODE_HOME/cli/plugins/cache/$MARKETPLACE/$PLUGIN_NAME/$PLUGIN_VERSION"
MARKETPLACE_FILE="$ZCODE_HOME/cli/plugins/marketplaces/$MARKETPLACE/marketplace.json"
CONFIG_FILE="$ZCODE_HOME/cli/config.json"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/dev.zcode.taskmonitor.plist"

green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }

green "==> Uninstalling ZCode Task Monitor…"

# Stop + remove the LaunchAgent.
if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
  green "  • Removing LaunchAgent"
  launchctl unload "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT_PLIST"
fi

# Kill the running app.
green "  • Stopping the app"
pkill -f "/MacOS/ZCodeTaskMonitor" >/dev/null 2>&1 || true

# Remove the plugin from cache.
green "  • Removing plugin from cache"
rm -rf "$CACHE_DIR"
# Also remove the now-empty parent dirs if nothing else is there.
rmdir "$ZCODE_HOME/cli/plugins/cache/$MARKETPLACE/$PLUGIN_NAME" 2>/dev/null || true

# Unregister from marketplace.json.
if [[ -f "$MARKETPLACE_FILE" ]]; then
  green "  • Unregistering from marketplace.json"
  python3 - "$MARKETPLACE_FILE" "$PLUGIN_NAME" <<'PY'
import json, os, sys, tempfile
path, name = sys.argv[1:3]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
plugins = data.get("plugins", [])
new_plugins = [p for p in plugins if p.get("name") != name]
if len(new_plugins) != len(plugins):
    data["plugins"] = new_plugins
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print("    removed")
else:
    print("    not present")
PY
fi

# Disable in config.json.
if [[ -f "$CONFIG_FILE" ]]; then
  green "  • Disabling in config.json"
  python3 - "$CONFIG_FILE" "$PLUGIN_NAME" "$MARKETPLACE" <<'PY'
import json, os, sys, tempfile
path, name, marketplace = sys.argv[1:4]
plugin_id = f"{name}@{marketplace}"
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
enabled = data.get("plugins", {}).get("enabledPlugins", {})
if plugin_id in enabled:
    del enabled[plugin_id]
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
    print("    disabled")
else:
    print("    already absent")
PY
fi

# Remove the .app.
for candidate in "/Applications/$APP_BUNDLE" "$HOME/Applications/$APP_BUNDLE"; do
  if [[ -d "$candidate" ]]; then
    green "  • Removing $candidate"
    rm -rf "$candidate"
  fi
done

green "$(printf '✅ Uninstalled.')"
