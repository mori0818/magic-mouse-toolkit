#!/bin/bash
# The direct swiftc/lipo build flow was informed by MouseToucher.
# Copyright (c) 2025 Roger Hughes, used under the MIT License.
# See THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit changes: GPL-3.0-only.

set -euo pipefail
cd "$(dirname "$0")"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"

APP="Magic Mouse Toolkit.app"
BIN="MagicMouseToolkit"
SIGN_ID="${SIGN_ID:-}"

SWIFT_FILES=(Sources/*.swift)
FLAGS=(-import-objc-header Sources/MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -O)

mkdir -p build
# フェーズ2のLiquid Glass(glassEffect)はmacOS 26+のAPIのためターゲットを引き上げ
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target arm64-apple-macos26.0  -o build/$BIN-arm64
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target x86_64-apple-macos26.0 -o build/$BIN-x86_64
lipo -create build/$BIN-arm64 build/$BIN-x86_64 -output build/$BIN

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS" "build/$APP/Contents/Resources"
cp Info.plist "build/$APP/Contents/"
cp build/$BIN "build/$APP/Contents/MacOS/"
cp -R Resources/ja.lproj Resources/en.lproj "build/$APP/Contents/Resources/"

# iCloud Drive 配下では com.apple.FinderInfo / fileprovider 拡張属性が
# 署名の直前に再付与されることがあり codesign が失敗するため、リトライ付きで署名する
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

for attempt in 1 2 3; do
  xattr -cr "build/$APP"
  if codesign --force --sign "$IDENTITY" "build/$APP"; then
    break
  fi
  if [ "$attempt" = 3 ]; then
    echo "エラー: 署名に3回失敗しました" >&2
    exit 1
  fi
  sleep 1
done
echo "Built: build/$APP"
