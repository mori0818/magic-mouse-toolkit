#!/bin/bash
# The direct swiftc build flow was informed by MouseToucher.
# Copyright (c) 2025 Roger Hughes, used under the MIT License.
# See ../../THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit changes: GPL-3.0-only.

set -euo pipefail
cd "$(dirname "$0")"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"

BIN="VirtualPadProto"
SIGN_ID="${SIGN_ID:-}"

FLAGS=(-import-objc-header MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework Foundation -framework IOKit -O)

mkdir -p build
swiftc main.swift "${FLAGS[@]}" -target arm64-apple-macos13.0 -o build/$BIN

if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning | grep -Fq -- "$SIGN_ID"; then
  IDENTITY="$SIGN_ID"
else
  if [ -n "$SIGN_ID" ]; then
    echo "警告: 証明書 '$SIGN_ID' が見つからないため ad-hoc 署名を使用します" >&2
  else
    echo "SIGN_ID未指定のためad-hoc署名を使用します"
  fi
  IDENTITY="-"
fi

xattr -cr "build/$BIN"
codesign --force --sign "$IDENTITY" "build/$BIN"
echo "Built: build/$BIN"
