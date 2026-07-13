#!/usr/bin/env bash
# One-time bootstrap of the Homebrew tap repo (ismatBabirli/homebrew-pelmet).
#
# Creates the public tap repo if it doesn't exist and seeds it with the cask
# from packaging/homebrew/pelmet.rb plus a short README. After this, the release
# workflow keeps the cask's version/sha256 in sync on every tagged release.
#
# Requires: gh (authenticated), git.
#   ./scripts/bootstrap-tap.sh
set -euo pipefail

OWNER="ismatBabirli"
TAP="homebrew-pelmet"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK_SRC="$ROOT/packaging/homebrew/pelmet.rb"

[ -f "$CASK_SRC" ] || { echo "Missing $CASK_SRC"; exit 1; }

if ! gh repo view "$OWNER/$TAP" >/dev/null 2>&1; then
  echo "Creating $OWNER/$TAP ..."
  gh repo create "$OWNER/$TAP" --public \
    --description "Homebrew tap for Pelmet — brew install --cask $OWNER/pelmet/pelmet"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git clone "https://github.com/$OWNER/$TAP.git" "$tmp"

mkdir -p "$tmp/Casks"
cp "$CASK_SRC" "$tmp/Casks/pelmet.rb"

cat > "$tmp/README.md" <<EOF
# Homebrew Pelmet

Homebrew tap for [Pelmet](https://github.com/$OWNER/pelmet) — a macOS menu bar
organizer that reclaims the icons a MacBook notch hides.

\`\`\`bash
brew install --cask $OWNER/pelmet/pelmet
\`\`\`
EOF

cd "$tmp"
git add .
if git diff --cached --quiet; then
  echo "Tap already up to date."
else
  git commit -m "Seed pelmet cask"
  git push
fi

echo "Done. Install with: brew install --cask $OWNER/pelmet/pelmet"
