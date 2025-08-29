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

zex() {
  TEMP_DIR="/tmp/zex"
  TARGET_DIR="$TESTS_DIR/roms"
  URL="https://zxe.io/depot/software/POSIX/Yaze%20v1.14%20%282004-04-23%29%28Cringle,%20Frank%20D.%29%28Sources%29%5B%21%5D.tar.gz"

  rm -rf "$TEMP_DIR"
  mkdir -p "$TARGET_DIR" "$TEMP_DIR"

  echo "[INFO] Downloading ZEX Tests into $TARGET_DIR"

  wget -O "$TEMP_DIR/yaze-1.14.tar.gz" "$URL"
  tar -xf "$TEMP_DIR/yaze-1.14.tar.gz" -C "$TEMP_DIR"

  cp "$TEMP_DIR/yaze-1.14/test/prelim.com" "$TARGET_DIR"
  cp "$TEMP_DIR/yaze-1.14/test/zexdoc.com" "$TARGET_DIR"
  cp "$TEMP_DIR/yaze-1.14/test/zexall.com" "$TARGET_DIR"

  rm -rf "$TEMP_DIR"
}

z80test() {
  TEMP_DIR="/tmp/z80test"
  TARGET_DIR="$TESTS_DIR/roms"
  URL="https://github.com/raxoft/z80test/releases/download/v1.2a/z80test-1.2a.zip"

  rm -rf "$TEMP_DIR"
  mkdir -p "$TARGET_DIR" "$TEMP_DIR"

  echo "[INFO] Downloading z80test Tests into $TARGET_DIR"

  wget -P "$TEMP_DIR" "$URL"
  unzip "$TEMP_DIR/z80test-1.2a.zip" -d "$TEMP_DIR"

  cp "$TEMP_DIR"/z80test-1.2a/*.tap "$TARGET_DIR"

  rm -rf "$TEMP_DIR"
}

all() {
  sst
  zex
  z80test
}

clean() {
  echo "[INFO] Removing: $TESTS_DIR/sst"
  rm -rf "$TESTS_DIR/sst"
  echo "[INFO] Removing: $TESTS_DIR/roms"
  rm -rf "$TESTS_DIR/roms"
}

arg="${1:-all}"

case "$arg" in
  all) all ;;
  sst) sst ;;
  zex) zex ;;
  z80test) z80test ;;
  clean) clean ;;
  *)
    echo "Error: Unknown argument '$arg'"
    echo "Usage: $0 [all|sst|zex|z80test|clean]"
    exit 1
    ;;
esac
