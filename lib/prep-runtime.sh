#!/usr/bin/env bash
# Prepare a Node runtime dir with puppeteer-core installed.
# Cached under ~/.cache/web-screenshot/runtime — first run takes ~10-20s
# (npm install over network), subsequent runs return instantly.
#
# Prints the absolute path of the runtime dir on stdout.

set -euo pipefail

RUNTIME_DIR="$HOME/.cache/web-screenshot/runtime"
MIN_NODE_MAJOR=18

# ---------- Check Node ----------
if ! command -v node >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: Node.js is not installed.

Install Node.js ${MIN_NODE_MAJOR}+ with one of:
  brew install node                        (macOS, Homebrew)
  curl -fsSL https://fnm.vercel.app/install | bash && fnm install 22
  https://nodejs.org/                      (download installer)
EOF
  exit 1
fi

node_major=$(node -p 'process.versions.node.split(".")[0]')
if [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
  echo "ERROR: Node.js ${MIN_NODE_MAJOR}+ required (you have $(node --version))" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: npm not found (should ship with Node)" >&2
  exit 1
fi

# ---------- Setup runtime ----------
if [ ! -d "$RUNTIME_DIR/node_modules/puppeteer-core" ]; then
  echo "Setting up web-screenshot runtime (one-time, ~10-20s for npm install)..." >&2
  mkdir -p "$RUNTIME_DIR"
  cd "$RUNTIME_DIR"

  # Minimal package.json so npm doesn't whine
  if [ ! -f package.json ]; then
    cat > package.json <<'JSON'
{
  "name": "web-screenshot-runtime",
  "version": "1.0.0",
  "private": true,
  "type": "module"
}
JSON
  fi

  npm install --silent --no-audit --no-fund puppeteer-core >&2
  echo "Runtime ready." >&2
fi

echo "$RUNTIME_DIR"
