#!/bin/bash
# Compila o Sweep e monta o Sweep.app em build/.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Sweep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sweep "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Pronto: $PWD/$APP"
