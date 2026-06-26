#!/usr/bin/env bash
# install-from-release.sh — downloads the latest GitHub Release and installs.
# Designed to be curl|bash friendly:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/WcpDDD/zcode-task-monitor/main/scripts/install-from-release.sh)"
set -euo pipefail

REPO="WcpDDD/zcode-task-monitor"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

green() { printf "\033[32m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*" >&2; }

green "==> Fetching latest release from $REPO…"

# Find the release asset URL via the GitHub API.
ASSET_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | python3 -c 'import json,sys; rel=json.load(sys.stdin); print(next(a["browser_download_url"] for a in rel["assets"] if a["name"].endswith(".zip")))')"

if [[ -z "$ASSET_URL" ]]; then
  red "Could not find a release .zip asset."
  exit 1
fi

green "  • Downloading $ASSET_URL"
curl -fsSL "$ASSET_URL" -o "$TMPDIR/release.zip"
( cd "$TMPDIR" && unzip -q release.zip )

# The release zip contains: dist/ZCodeTaskMonitor.app and plugin/
if [[ ! -d "$TMPDIR/dist/ZCodeTaskMonitor.app" ]]; then
  # Handle nested layout where zip root is the repo dir.
  if [[ -d "$TMPDIR/zcode-task-monitor/dist/ZCodeTaskMonitor.app" ]]; then
    cd "$TMPDIR/zcode-task-monitor"
  else
    red "Release zip did not contain dist/ZCodeTaskMonitor.app"
    red "Contents:"; ( cd "$TMPDIR" && find . -maxdepth 3 -type d ) >&2
    exit 1
  fi
fi

green "  • Running installer…"
./scripts/install.sh
