#!/usr/bin/env bash

set -e

TESTS_DIR="./tests"

sst() {
  TEMP_DIR_SST="/tmp/sst_z80"
  REPO_URL="https://github.com/SingleStepTests/z80.git"
  TARGET_DIR="$TESTS_DIR/sst"

  if [ -d "$TARGET_DIR" ] && [ "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
    echo "[INFO] SST tests already exist in $TARGET_DIR. Skipping download."
    return
  fi

  echo "[INFO] Downloading SST Tests into $TARGET_DIR"

  rm -rf "$TEMP_DIR_SST"
  mkdir -p "$TARGET_DIR"

  git clone --depth 1 "$REPO_URL" "$TEMP_DIR_SST"
  mv "$TEMP_DIR_SST/v1"/*.json "$TARGET_DIR/" 2>/dev/null || echo "No JSON files found."
  rm -rf "$TEMP_DIR_SST"
}

all() {
  sst
}

clean() {
  echo "[INFO] Removing: $TESTS_DIR/sst"
  rm -rf "$TESTS_DIR/sst"
}

arg="${1:-all}"

case "$arg" in
  all) all ;;
  sst) sst ;;
  clean) clean ;;
  *)
    echo "Error: Unknown argument '$arg'"
    echo "Usage: $0 [all|sst]"
    exit 1
    ;;
esac
