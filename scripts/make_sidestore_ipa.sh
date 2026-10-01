#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Uso: $0 Finance.xcarchive Finance.ipa" >&2
  exit 2
fi

archive="$1"
output="$2"
app="$archive/Products/Applications/Finance.app"
widget="$app/PlugIns/FinanceWidgetExtension.appex"

if [[ ! -d "$app" || ! -d "$widget" ]]; then
  echo "El archive debe contener Finance.app y FinanceWidgetExtension.appex" >&2
  exit 1
fi

mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/Payload"
cp -R "$app" "$tmp/Payload/"
(
  cd "$tmp"
  /usr/bin/zip -qry "$tmp/Finance.ipa" Payload
)
mv -f "$tmp/Finance.ipa" "$output"

echo "$output"
