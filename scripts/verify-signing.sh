#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/dist/Clipp.app"
certificate="$root/Resources/Signing/ClippLocal.cer"
signing_identity="${CLIPP_SIGNING_IDENTITY:-$(shasum -a 1 "$certificate" | awk '{print toupper($1)}')}"
codesign --verify --strict "$app"
requirement="$(codesign -d -r- "$app" 2>&1 | sed -n 's/^#* *designated => //p')"
if [[ -z "$requirement" || "$requirement" == *cdhash* || "$requirement" != *identifier* ]] ||
   [[ "$requirement" != *anchor* && "$requirement" != *certificate* ]]; then
    printf 'A assinatura não está vinculada a um certificado estável.\n' >&2
    exit 1
fi

test_dir="$(mktemp -d "$root/.build/signing-check.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
probe="$test_dir/Clipp.app"
ditto "$app" "$probe"
printf 'int main(void) { return 7; }\n' | /usr/bin/clang -x c -o "$probe/Contents/MacOS/Clipp" -
codesign --force --sign "$signing_identity" --identifier br.com.clipp.app "$probe"
if cmp -s "$app/Contents/MacOS/Clipp" "$probe/Contents/MacOS/Clipp"; then
    printf 'O teste precisa de executáveis diferentes.\n' >&2
    exit 1
fi
codesign --verify --strict -R="$requirement" "$app"
codesign --verify --strict -R="$requirement" "$probe"
codesign --force --sign - --identifier br.com.clipp.app "$probe"
if codesign --verify --strict -R="$requirement" "$probe" >/dev/null 2>&1; then
    printf 'Uma assinatura sem o certificado foi aceita indevidamente.\n' >&2
    exit 1
fi
printf 'Assinatura estável verificada: dois executáveis diferentes aceitos e assinatura ad-hoc rejeitada pelo mesmo requisito.\n%s\n' "$requirement"
