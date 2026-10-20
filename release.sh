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
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Sweep.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sweep" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-0}" != 1 ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

shasum -a 256 "$DMG"
echo "Pronto: $PWD/$DMG"
