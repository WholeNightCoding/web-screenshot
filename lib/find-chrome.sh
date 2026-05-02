#!/usr/bin/env bash
# Find or install a chrome-headless-shell binary.
# Prints the absolute path on stdout. Exits non-zero with a hint on stderr.
#
# Search order:
#   1. Skill-managed cache:    ~/.cache/web-screenshot/chrome/...
#   2. Existing Playwright:    ~/Library/Caches/ms-playwright/, ~/.cache/ms-playwright/
#   3. Existing Puppeteer:     ~/.cache/puppeteer/
#   4. Auto-install via npx @puppeteer/browsers (~80MB, one-time)
#
# Auto-install is the "fresh machine" fallback. Set WEB_SCREENSHOT_NO_AUTO_INSTALL=1
# to skip step 4 (useful for CI / sandboxed environments where you'd rather fail
# loudly than block on a download).

set -euo pipefail

SKILL_CACHE="$HOME/.cache/web-screenshot/chrome"

# ---------- Helper: search a directory tree for chrome-headless-shell ----------
find_in_dir() {
  local root="$1"
  [ -d "$root" ] || return 1
  # Find newest chrome-headless-shell binary, prefer mac-arm64 / linux / mac-x64
  local found
  found=$(find "$root" -type f -name 'chrome-headless-shell' -perm +111 2>/dev/null | sort -V | tail -1)
  [ -n "$found" ] && [ -x "$found" ] && { echo "$found"; return 0; }
  return 1
}

# ---------- 1. Skill-managed cache (preferred — we know how to update it) ----------
if path=$(find_in_dir "$SKILL_CACHE"); then
  echo "$path"
  exit 0
fi

# ---------- 2. Existing Playwright cache ----------
for dir in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
  if path=$(find_in_dir "$dir"); then
    echo "$path"
    exit 0
  fi
done

# ---------- 3. Existing Puppeteer cache ----------
if path=$(find_in_dir "$HOME/.cache/puppeteer"); then
  echo "$path"
  exit 0
fi

# ---------- 4. Auto-install ----------
if [ "${WEB_SCREENSHOT_NO_AUTO_INSTALL:-0}" = "1" ]; then
  cat >&2 <<EOF
ERROR: chrome-headless-shell not found and WEB_SCREENSHOT_NO_AUTO_INSTALL=1.
Install manually with:
  npx -y @puppeteer/browsers install chrome-headless-shell --path "$SKILL_CACHE"
EOF
  exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: npx not found. Install Node.js 18+ first:
  brew install node                        (macOS via Homebrew)
  curl -fsSL https://nodejs.org/...        (or download from nodejs.org)
EOF
  exit 1
fi

mkdir -p "$SKILL_CACHE"
echo "Installing chrome-headless-shell to $SKILL_CACHE (one-time, ~80MB)..." >&2

# Capture install output. The last line is "<pkg>@<version> <absolute path>".
install_out=$(npx -y @puppeteer/browsers install chrome-headless-shell --path "$SKILL_CACHE" 2>&1)
install_status=$?

if [ $install_status -ne 0 ]; then
  echo "ERROR: chrome-headless-shell install failed:" >&2
  echo "$install_out" >&2
  exit 1
fi

# Parse the last line. Format example:
#   chrome-headless-shell@141.0.7390.54 /Users/.../chrome-headless-shell/mac_arm-141.../chrome-headless-shell-mac-arm64/chrome-headless-shell
final_path=$(echo "$install_out" | tail -1 | awk '{print $NF}')

if [ -x "$final_path" ]; then
  echo "Installed: $final_path" >&2
  echo "$final_path"
  exit 0
fi

# Fallback: search the cache we just populated
if path=$(find_in_dir "$SKILL_CACHE"); then
  echo "$path"
  exit 0
fi

echo "ERROR: install reported success but binary not found in $SKILL_CACHE" >&2
echo "$install_out" >&2
exit 1
