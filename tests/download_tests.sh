#!/usr/bin/env bash

set -e

if [ ! -f 'tests/download_tests.sh' ]; then
    echo "Script must be run from the project root dir"
    exit 1
fi

TESTS_DIR="tests"

RED="\x1b[31m"
BLUE="\x1b[34m"
RESET="\x1b[0m"

log() {
    if [ "$1" = "info" ]; then
        echo -e "[${BLUE}INFO${RESET}] $2"
    elif [ "$1" = "error" ]; then
        echo -e "[${RED}ERROR${RESET}] $2"
    fi
}

sst() {
    TEMP_DIR="$(mktemp -d)"
    REPO_URL="https://github.com/SingleStepTests/z80.git"
    TARGET_DIR="$TESTS_DIR/sst"

    if [ -d "$TARGET_DIR" ] && [ "$(ls "$TARGET_DIR" 2> /dev/null)" ]; then
        log info "SST tests already exists, Skipping download."
        return
    fi

    log info "Downloading SST Tests into '$TARGET_DIR'"

    mkdir -p "$TARGET_DIR"

    git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
    mv "$TEMP_DIR/v1"/*.json "$TARGET_DIR/" 2> /dev/null || echo "No JSON files found."
    rm -rf "$TEMP_DIR"
}

zex() {
    TEMP_DIR="$(mktemp -d)"
    TARGET_DIR="$TESTS_DIR/roms"
    URL="https://zxe.io/depot/software/POSIX/Yaze%20v1.14%20%282004-04-23%29%28Cringle,%20Frank%20D.%29%28Sources%29%5B%21%5D.tar.gz"

    if [ "$(ls "$TARGET_DIR"/*.com 2> /dev/null | wc -l)" -eq 3 ]; then
        log info "Zex tests already exists, Skipping download."
        return
    fi

    mkdir -p "$TARGET_DIR"

    log info "Downloading ZEX Tests into '$TARGET_DIR'"

    wget -O "$TEMP_DIR/yaze-1.14.tar.gz" "$URL"
    tar -xf "$TEMP_DIR/yaze-1.14.tar.gz" -C "$TEMP_DIR"

    cp "$TEMP_DIR/yaze-1.14/test/prelim.com" "$TARGET_DIR"
    cp "$TEMP_DIR/yaze-1.14/test/zexdoc.com" "$TARGET_DIR"
    cp "$TEMP_DIR/yaze-1.14/test/zexall.com" "$TARGET_DIR"

    rm -rf "$TEMP_DIR"
}

z80test() {
    TEMP_DIR="$(mktemp -d)"
    TARGET_DIR="$TESTS_DIR/roms"
    URL="https://github.com/raxoft/z80test/releases/download/v1.2a/z80test-1.2a.zip"

    if [ "$(ls "$TARGET_DIR"/*.tap 2> /dev/null | wc -l)" -eq 6 ]; then
        log info "Z80test tests already exists, Skipping download."
        return
    fi

    mkdir -p "$TARGET_DIR"

    log info "Downloading z80test Tests into '$TARGET_DIR'"

    wget -P "$TEMP_DIR" "$URL"
    unzip "$TEMP_DIR/z80test-1.2a.zip" -d "$TEMP_DIR"

    cp "$TEMP_DIR"/z80test-1.2a/*.tap "$TARGET_DIR"
    rm "$TARGET_DIR/z80ccfscr.tap"

    rm -rf "$TEMP_DIR"
}

all() {
    sst
    zex
    z80test
}

clean() {
    log info "Removing: '$TESTS_DIR/sst'"
    rm -rf "$TESTS_DIR/sst"
    log info "Removing: '$TESTS_DIR/roms'"
    rm -rf "$TESTS_DIR/roms"
}

for cmd in git wget tar unzip; do
    command -v "$cmd" > /dev/null 2>&1 || {
        log error "'$cmd' is required but not installed."
        exit 1
    }
done

if [ "$#" -ne 1 ]; then
    log error "Expected only one argument"
    echo "Usage: $0 [all|sst|zex|z80test|clean]"
    exit 1
fi

case "$1" in
    all) all ;;
    sst) sst ;;
    zex) zex ;;
    z80test) z80test ;;
    clean) clean ;;
    *)
        log error "Unknown argument '$1'"
        echo "Usage: $0 [all|sst|zex|z80test|clean]"
        exit 1
        ;;
esac
