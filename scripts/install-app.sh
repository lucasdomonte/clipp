#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$HOME/Applications/Clipp.app}"

if pgrep -x Clipp >/dev/null; then
    printf 'Encerre o Clipp pelo menu antes de instalar a atualização.\n' >&2
    exit 1
fi
if [[ -e "$destination" ]]; then
    identifier="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [[ "$identifier" != 'br.com.clipp.app' ]]; then
        printf 'O destino já contém outro aplicativo; instalação cancelada.\n' >&2
        exit 1
    fi
fi

"$root/scripts/build-app.sh"
mkdir -p "$(dirname "$destination")"
ditto "$root/dist/Clipp.app" "$destination"
codesign --verify --strict "$destination"
open "$destination"
printf 'Clipp instalado em: %s\n' "$destination"
