#!/bin/bash
# 文字数カウンター をビルドして .app を作る
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/文字数カウンター.app"

mkdir -p "$APP/Contents/MacOS"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
clang -fobjc-arc -O2 "$DIR/main.m" -o "$APP/Contents/MacOS/SelectCount" \
    -framework Cocoa -framework ApplicationServices -framework QuartzCore
codesign --force -s - "$APP"
echo "ビルド完了: $APP"
