#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <Stackbar.app> <output.dmg>\n' "$0" >&2
  exit 64
fi

app_path=$1
output_path=$2

if [[ ! -d "$app_path" ]]; then
  printf 'App bundle not found: %s\n' "$app_path" >&2
  exit 66
fi
if [[ -e "$output_path" ]]; then
  printf 'Output already exists: %s\n' "$output_path" >&2
  exit 73
fi

mkdir -p "$(dirname "$output_path")"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/stackbar-dmg.XXXXXX")
trap 'rm -r -- "$staging_dir"' EXIT

ditto "$app_path" "$staging_dir/Stackbar.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -quiet -volname Stackbar -srcfolder "$staging_dir" -format UDZO "$output_path"
