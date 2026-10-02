#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

./scripts/build-app.sh --universal
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$root/dist/Clipp.app/Contents/Info.plist")"
stage="$(mktemp -d "$root/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto "$root/dist/Clipp.app" "$stage/Clipp.app"
ln -s /Applications "$stage/Applications"
cp "$root/Resources/LEIA-ME.txt" "$stage/LEIA-ME.txt"

dmg="$root/dist/Clipp-$version-universal.dmg"
hdiutil create -volname Clipp -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
hdiutil verify "$dmg"
shasum -a 256 "$dmg"
printf 'Instalador criado em: %s\n' "$dmg"
