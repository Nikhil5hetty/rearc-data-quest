#!/usr/bin/env bash
# build.sh — Build Lambda deployment packages with all Python dependencies.
# Usage:  bash scripts/build.sh
#
# Output: dist/data-sync.zip and dist/data-process.zip

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
LAMBDAS_DIR="$PROJECT_DIR/lambdas"
REQUIREMENTS="$LAMBDAS_DIR/requirements.txt"

echo "Building Lambda packages..."
echo "Project: $PROJECT_DIR"
mkdir -p "$DIST_DIR"

# ---- data-sync (Part 1 + Part 2) ----
echo ""
echo "→ Building data-sync..."
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

cp "$LAMBDAS_DIR/data-sync/handler.py"    "$BUILD_DIR/"
cp "$LAMBDAS_DIR/data-sync/bls_sync.py"   "$BUILD_DIR/"
cp "$LAMBDAS_DIR/data-sync/datausa_api.py" "$BUILD_DIR/"
python3 -m pip install --target "$BUILD_DIR" -r "$REQUIREMENTS" --quiet

(cd "$BUILD_DIR" && zip -r "$DIST_DIR/data-sync.zip" . -q)
echo "✓ dist/data-sync.zip  $(du -sh "$DIST_DIR/data-sync.zip" | cut -f1)"

trap - EXIT
rm -rf "$BUILD_DIR"

# ---- data-process (Part 3) ----
echo ""
echo "→ Building data-process..."
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

cp "$LAMBDAS_DIR/data-process/handler.py" "$BUILD_DIR/"
python3 -m pip install --target "$BUILD_DIR" -r "$REQUIREMENTS" --quiet

(cd "$BUILD_DIR" && zip -r "$DIST_DIR/data-process.zip" . -q)
echo "✓ dist/data-process.zip  $(du -sh "$DIST_DIR/data-process.zip" | cut -f1)"

trap - EXIT
rm -rf "$BUILD_DIR"

echo ""
echo "Build complete! Packages:"
ls -lh "$DIST_DIR"/*.zip | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "Next: cd terraform && make plan ENV=dev && make apply ENV=dev"
