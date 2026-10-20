#!/bin/bash
# Compila o Sweep e monta o Sweep.app em build/.
#   UNIVERSAL=1      binário para Apple Silicon e Intel
#   SIGN_IDENTITY=…  assina com essa identidade e hardened runtime (sem ela, assinatura ad hoc)
set -euo pipefail
cd "$(dirname "$0")"

# String em vez de array: o bash 3.2 do macOS trata array vazio como variável indefinida.
ARCHS=""
[ "${UNIVERSAL:-0}" = 1 ] && ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
# O caminho de saída muda entre versões do SwiftPM; pergunta a ele.
BIN="$(swift build -c release $ARCHS --show-bin-path)/Sweep"

APP=build/Sweep.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Pronto: $PWD/$APP"
