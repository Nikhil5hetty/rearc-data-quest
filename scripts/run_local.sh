#!/usr/bin/env bash
# run_local.sh — Run Lambda functions locally against local data files.
# No AWS credentials required.
#
# Usage:
#   bash scripts/run_local.sh sync          # Download BLS + population → ./data/
#   bash scripts/run_local.sh sync --dry-run
#   bash scripts/run_local.sh process       # Run analytics on ./data/
#   bash scripts/run_local.sh process --bls-file ./data/bls/pr.data.0.Current
#   bash scripts/run_local.sh all           # sync then process

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$PROJECT_DIR/data"
BLS_DIR="$DATA_DIR/bls"
POPULATION_FILE="$DATA_DIR/population.json"

COMMAND="${1:-help}"
shift || true   # remaining args forwarded to the Python script

mkdir -p "$BLS_DIR"

case "$COMMAND" in
  sync)
    echo "→ Running data-sync locally (output: $DATA_DIR)"
    cd "$PROJECT_DIR/lambdas/data-sync"
    python3 handler.py \
      --local-dir "$BLS_DIR" \
      --population-file "$POPULATION_FILE" \
      "$@"
    ;;
  process)
    echo "→ Running data-process locally (reading from: $DATA_DIR)"
    cd "$PROJECT_DIR/lambdas/data-process"
    python3 handler.py \
      --bls-file "$BLS_DIR/pr.data.0.Current" \
      --population-file "$POPULATION_FILE" \
      "$@"
    ;;
  all)
    echo "=== Step 1: Sync data ==="
    bash "$PROJECT_DIR/scripts/run_local.sh" sync
    echo ""
    echo "=== Step 2: Process analytics ==="
    bash "$PROJECT_DIR/scripts/run_local.sh" process
    ;;
  help|*)
    echo "Usage: bash scripts/run_local.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  sync      Download BLS files and population data to ./data/"
    echo "  process   Run analytics queries against local ./data/ files"
    echo "  all       Run sync then process"
    echo ""
    echo "Options (passed through to Python):"
    echo "  --dry-run                 (sync) simulate without writing"
    echo "  --local-dir PATH          (sync) override BLS output directory"
    echo "  --population-file PATH    (sync/process) override population file path"
    echo "  --bls-file PATH           (process) override BLS data file path"
    echo "  --s3-bucket NAME          use S3 instead of local files"
    ;;
esac
