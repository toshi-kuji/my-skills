#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CACHE_DIR="/private/tmp/codex-ocr-clang-module-cache"
BINARY="/private/tmp/codex-ocr"
SOURCE="$SCRIPT_DIR/main.swift"

mkdir -p "$CACHE_DIR"

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFT_MODULE_CACHE_PATH="$CACHE_DIR"

if [[ ! -x "$BINARY" || "$SOURCE" -nt "$BINARY" ]]; then
  swiftc \
    -module-cache-path "$CACHE_DIR" \
    "$SOURCE" \
    -o "$BINARY" \
    -framework AppKit \
    -framework PDFKit \
    -framework Vision \
    -framework ImageIO
fi

if [[ $# -eq 0 ]]; then
  "$BINARY" "$PWD/tmp"
else
  "$BINARY" "$@"
fi
