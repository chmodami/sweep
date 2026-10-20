#!/bin/bash
# Gera build/Sweep-<versão>.dmg assinado com Developer ID, notarizado pela Apple e com o ticket grampeado.
#
# Antes da primeira vez, salve as credenciais do notarytool no Keychain:
#   xcrun notarytool store-credentials sweep-notary --apple-id <email> --team-id <TEAM_ID>
#
#   SIGN_IDENTITY=…   identidade de assinatura (padrão: a primeira "Developer ID Application" do Keychain)
#   NOTARY_PROFILE=…  perfil do notarytool (padrão: sweep-notary)
#   SKIP_NOTARIZE=1   só assina, sem notarizar
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
PROFILE="${NOTARY_PROFILE:-sweep-notary}"
VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
[ -n "$IDENTITY" ] || { echo "Nenhuma identidade \"Developer ID Application\" no Keychain." >&2; exit 1; }
echo "Assinando com: $IDENTITY"

SIGN_IDENTITY="$IDENTITY" UNIVERSAL=1 ./build.sh
codesign --verify --strict --deep build/Sweep.app

DMG="build/Sweep-$VERSION.dmg"
STAGE=build/dmg
RW=build/Sweep-rw.dmg
VOLUME="Sweep"
rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE/.background"
cp -R build/Sweep.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Fundo da janela em 1x e 2x, juntos num .tiff que o Finder escolhe conforme a tela.
swift scripts/dmg-background.swift "$STAGE/.background"
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
    -out "$STAGE/.background/background.tiff" 2>/dev/null
rm "$STAGE/.background/"*.png
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# Imagem gravável para o Finder salvar o layout (.DS_Store); depois vira a imagem comprimida final.
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
rm -rf "$STAGE"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
xcrun SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT"

# Layout da janela: 640 × 400 pt, ícones de 128 pt nas posições que o fundo espera.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {200, 120, 840, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Sweep.app" of container window to {170, 190}
        set position of item "Applications" of container window to {470, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-0}" != 1 ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

shasum -a 256 "$DMG"
echo "Pronto: $PWD/$DMG"
