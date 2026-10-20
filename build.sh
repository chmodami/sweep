#!/bin/bash
# Compila o Faxina e monta o Faxina.app em build/.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Faxina.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Faxina "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Pronto: $PWD/$APP"
