#!/usr/bin/env bash
# install.sh — installs the ZCode Task Monitor plugin + menu-bar app.
#
# What it does:
#   1. Copies ZCodeTaskMonitor.app into /Applications (or ~/Applications).
#   2. Copies the plugin into ~/.zcode/cli/plugins/cache/zcode-plugins-official/task-monitor/0.1.0/.
#   3. Registers the plugin in marketplace.json (format-preserving).
#   4. Enables it in ~/.zcode/cli/config.json (format-preserving).
#   5. Installs a LaunchAgent so the app also auto-starts at login.
#   6. Launches the app right now.
#
# Idempotent: safe to re-run.
set -euo pipefail

PLUGIN_NAME="task-monitor"
PLUGIN_VERSION="0.1.0"
MARKETPLACE="zcode-plugins-official"
APP_BUNDLE="ZCodeTaskMonitor.app"

# Resolve repo root (this script lives in <repo>/scripts/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGIN_SRC="$REPO_ROOT/plugin"
APP_SRC="$REPO_ROOT/dist/$APP_BUNDLE"

ZCODE_HOME="${ZCODE_HOME:-$HOME/.zcode}"
CACHE_DIR="$ZCODE_HOME/cli/plugins/cache/$MARKETPLACE/$PLUGIN_NAME/$PLUGIN_VERSION"
MARKETPLACE_FILE="$ZCODE_HOME/cli/plugins/marketplaces/$MARKETPLACE/marketplace.json"
CONFIG_FILE="$ZCODE_HOME/cli/config.json"
LAUNCH_AGENT_LABEL="dev.zcode.taskmonitor"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

# ANSI helpers
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*" >&2; }

# ---- preflight ---------------------------------------------------------------
# If the prebuilt .app isn't present (e.g. a fresh git clone, where dist/ is
# gitignored), build it from source on the fly. Requires Swift 5.9+ / Xcode.
if [[ ! -d "$APP_SRC" ]]; then
  if [[ ! -d "$REPO_ROOT/app/Package.swift" ]] && [[ ! -f "$REPO_ROOT/app/Package.swift" ]]; then
    red "ERROR: neither a prebuilt app nor app sources found."
    red "Expected $APP_SRC or $REPO_ROOT/app/Package.swift"
    exit 1
  fi
  if ! command -v swift >/dev/null 2>&1; then
    red "ERROR: no prebuilt app at $APP_SRC and 'swift' not found."
    red "Install Xcode Command Line Tools, or download a Release build."
    exit 1
  fi
  green "  • No prebuilt app found — building from source (needs Swift/Xcode)…"
  ( cd "$REPO_ROOT" && ./scripts/build-app.sh ) || {
    red "ERROR: build-app.sh failed."
    exit 1
  }
fi

if [[ ! -d "$PLUGIN_SRC/.zcode-plugin" ]]; then
  red "ERROR: plugin manifest not found at $PLUGIN_SRC/.zcode-plugin"
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { red "python3 is required"; exit 1; }

green "==> Installing ZCode Task Monitor…"

# ---- 1. copy the .app --------------------------------------------------------
APP_DEST=""
if [[ -w "/Applications" ]]; then
  APP_DEST="/Applications/$APP_BUNDLE"
else
  mkdir -p "$HOME/Applications"
  APP_DEST="$HOME/Applications/$APP_BUNDLE"
fi
green "  • Copying app -> $APP_DEST"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

# ---- 2. copy the plugin ------------------------------------------------------
green "  • Copying plugin -> $CACHE_DIR"
mkdir -p "$CACHE_DIR"
# Copy plugin contents (manifest, hooks, seed) but NOT the .plist (that's for the agent).
cp -R "$PLUGIN_SRC/." "$CACHE_DIR/"
# Remove the LaunchAgent template from the installed plugin dir; it's not needed there.
rm -f "$CACHE_DIR/dev.zcode.taskmonitor.plist"

# ---- 3. register in marketplace.json ----------------------------------------
green "  • Registering in marketplace.json"
mkdir -p "$(dirname "$MARKETPLACE_FILE")"
python3 - "$MARKETPLACE_FILE" "$CACHE_DIR" "$PLUGIN_NAME" "$PLUGIN_VERSION" "$MARKETPLACE" <<'PY'
import json, os, sys, tempfile
path, cache_dir, name, version, marketplace = sys.argv[1:6]
entry = {"cachePath": cache_dir, "name": name, "source": "filesystem", "version": version}

def default_marketplace():
    return {"name": marketplace, "version": 1, "plugins": []}

data = default_marketplace()
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = default_marketplace()
data.setdefault("plugins", [])
# Replace any existing entry with the same name, else append.
data["plugins"] = [p for p in data["plugins"] if p.get("name") != name] + [entry]

# Atomic write.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print("    marketplace.json updated")
PY

# ---- 4. enable in config.json ------------------------------------------------
green "  • Enabling plugin in config.json"
mkdir -p "$(dirname "$CONFIG_FILE")"
python3 - "$CONFIG_FILE" "$PLUGIN_NAME" "$MARKETPLACE" <<'PY'
import json, os, sys, tempfile
path, name, marketplace = sys.argv[1:4]
plugin_id = f"{name}@{marketplace}"

data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
plugins = data.setdefault("plugins", {})
enabled = plugins.setdefault("enabledPlugins", {})
if enabled.get(plugin_id) is True:
    print("    already enabled")
else:
    enabled[plugin_id] = True

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
print("    config.json updated")
PY

# ---- 5. install LaunchAgent (login autostart) --------------------------------
green "  • Installing LaunchAgent"
mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"
cp "$PLUGIN_SRC/dev.zcode.taskmonitor.plist" "$LAUNCH_AGENT_PLIST"
launchctl unload "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
launchctl load "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true

# ---- 6. detect launch context & guide accordingly ---------------------------
# IMPORTANT: the floating panel CANNOT render when launched as a child of a
# ZCode host process (the host sandbox blocks child GUI windows). So if this
# script is running inside a ZCode session, we do NOT attempt to launch the app
# here (it would start but stay invisible). Instead we tell the user to launch
# from a context outside ZCode (system Terminal / Finder / login).
in_zcode=0
if [[ -n "${ZCODE_SANDBOX:-}" || -n "${ZCODE_PROJECT_DIR:-}" ]] \
   || pgrep -f "zcode-host" >/dev/null 2>&1; then
  in_zcode=1
fi

if [[ "$in_zcode" -eq 0 ]]; then
  green "  • Launching ZCodeTaskMonitor"
  /usr/bin/open -a "$APP_DEST" >/dev/null 2>&1 || true
fi

if [[ "$in_zcode" -eq 1 ]]; then
cat <<EOF

$(green "✅ Installation complete — but ONE manual step remains:")

You're running this inside a ZCode session. ZCode's host process sandboxes its
children, so the floating panel launched from here would be invisible. To see
the panel, launch it from OUTSIDE ZCode — either:

  • Open the macOS Terminal app (not the one inside ZCode) and run:
      open $APP_DEST

  • Or just log out and back in — the LaunchAgent will start it at login
    (parent = launchd, not ZCode), and it will render correctly.

  • Or double-click ZCodeTaskMonitor in /Applications from Finder.

$(yellow "Once started this way, the panel will float top-right over everything and")
$(yellow "auto-relaunch at every login via the LaunchAgent.")

$(yellow "Uninstall: ./scripts/uninstall.sh")
EOF
else
cat <<EOF

$(green "✅ Done.")

A floating panel should now appear in the top-right corner of your screen,
showing all in-progress ZCode tasks (status dot, elapsed time, and a "⚠ 可能阻塞"
badge when a task looks stuck / waiting for input). Click a task to open its
workspace in ZCode; click the × to hide the panel (reopen via the menu-bar icon).

It also auto-launches at login via the LaunchAgent.

$(yellow "Note: the first launch may prompt for notification permission — allow it to")
$(yellow "get HITL alerts when a task starts waiting for your input.")

$(yellow "Uninstall: ./scripts/uninstall.sh")
EOF
fi
