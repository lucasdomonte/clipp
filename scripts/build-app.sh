#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
export CLANG_MODULE_CACHE_PATH="$root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"

certificate="$root/Resources/Signing/ClippLocal.cer"
signing_identity="${CLIPP_SIGNING_IDENTITY:-$(shasum -a 1 "$certificate" | awk '{print toupper($1)}')}"
if [[ "$signing_identity" == '-' ]] || ! security find-identity -p codesigning | grep -F -- "$signing_identity" >/dev/null; then
    printf 'Identidade de assinatura ausente no Chaveiro. Reutilize Clipp Local Code Signing ou defina CLIPP_SIGNING_IDENTITY.\n' >&2
    exit 1
fi

build_options=(-c release --disable-sandbox)
case "${1:-}" in
    --universal) build_options+=(--arch arm64 --arch x86_64) ;;
    '') ;;
    *) printf 'Uso: %s [--universal]\n' "$0" >&2; exit 1 ;;
esac
swift build "${build_options[@]}"
bin_dir="$(swift build "${build_options[@]}" --show-bin-path)"
app="$root/dist/Clipp.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Clipp" "$app/Contents/MacOS/Clipp"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"

icon="$root/Resources/IconConcepts/clipp-paperclip-brain-v3-transparent.png"
iconset="$root/.build/Clipp.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
sips -z 18 18 "$icon" --out "$app/Contents/Resources/MenuBarIconTemplate.png" >/dev/null
sips -z 36 36 "$icon" --out "$app/Contents/Resources/MenuBarIconTemplate@2x.png" >/dev/null
codesign --force --sign "$signing_identity" --identifier br.com.clipp.app "$app"
codesign --verify --strict "$app"
printf 'Aplicativo criado em: %s\n' "$app"
