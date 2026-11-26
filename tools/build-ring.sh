#!/usr/bin/env bash
#
# Builds the installer that is published for one ring.
#
# Usage: tools/build-ring.sh <ring> <script-name> <output-script>
#   ring:        dev | test | stage | ea | ga
#   script-name: linux-installer.sh | macos-installer.sh | windows-installer.ps1
#
# The installers live in two folders:
#   scripts/negative/  dev, test, stage  the internal rings, with the internal options (--use-acr, --pegasus-enabled, ...)
#   scripts/positive/  ea, ga            what customers get, without any of the internal options
#
# The only thing done to the script is setting the default ring (DEFAULT_ENV, or $Script:DefaultEnv in the .ps1).

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <ring> <script-name> <output-script>" >&2
    exit 2
fi

ring="$1"
script_name="$2"
output_file="$3"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$ring" in
    dev|test|stage) folder="negative" ;;
    ea|ga)          folder="positive" ;;
    *) echo "build-ring: unknown ring '$ring' (expected dev, test, stage, ea or ga)" >&2; exit 2 ;;
esac

source_file="$root/scripts/$folder/$script_name"
[[ -f "$source_file" ]] || { echo "build-ring: '$source_file' not found" >&2; exit 2; }

mkdir -p "$(dirname "$output_file")"
case "$script_name" in
    *.ps1) sed "s/^\\\$Script:DefaultEnv = \"[^\"]*\"/\$Script:DefaultEnv = \"$ring\"/" "$source_file" > "$output_file" ;;
    *)     sed "s/^DEFAULT_ENV=\"[^\"]*\"/DEFAULT_ENV=\"$ring\"/" "$source_file" > "$output_file" ;;
esac
