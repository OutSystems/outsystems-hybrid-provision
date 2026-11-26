#!/usr/bin/env bash
#
# Builds the installer script that is published for one ring.
#
# Usage: tools/build-ring.sh <ring> <source-script> <output-script>
#
#   ring: dev | test | stage | ea | ga
#
# The installers in scripts/ are one source file per platform. They carry options that are only meant for
# the internal rings (dev, test, stage): --use-acr, --pegasus-enabled, --kevents-replicas, --sh-monitoring
# and the dev/test/stage registry aliases. A customer on ea or ga must not find any of that in the script
# they download, so those parts are removed when the ring script is built, not just hidden from --help.
#
# Directives (a comment line on its own line, indentation allowed, in .sh and .ps1 sources):
#
#   # internal-only:begin  ...  # internal-only:end
#       Kept in dev, test and stage. Removed in ea and ga.
#
#   # positive-only:begin  ...  # positive-only:end
#       Written as comments in the source, one "# " in front of each line (a lone "#" is an empty line).
#       Uncommented in ea and ga.
#       Removed in dev, test and stage. Used where ea and ga need a different version of a line.
#
# The directive lines themselves never reach the output. Blocks must not be nested and must be closed.
# After the blocks are processed, DEFAULT_ENV (sh) or $Script:DefaultEnv (ps1) is set to the ring.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <ring> <source-script> <output-script>" >&2
    exit 2
fi

ring="$1"
source_file="$2"
output_file="$3"

case "$ring" in
    dev|test|stage) positive=0 ;;
    ea|ga)          positive=1 ;;
    *) echo "build-ring: unknown ring '$ring' (expected dev, test, stage, ea or ga)" >&2; exit 2 ;;
esac

[[ -f "$source_file" ]] || { echo "build-ring: source '$source_file' not found" >&2; exit 2; }

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

awk -v positive="$positive" -v src="$source_file" '
function fail(msg) { printf "build-ring: %s:%d: %s\n", src, NR, msg > "/dev/stderr"; failed = 1; exit 1 }
{
    line = $0
    sub(/\r$/, "", line)
}
line ~ /^[ \t]*# internal-only:begin[ \t]*$/ {
    if (mode != "") fail("nested block: internal-only:begin inside " mode)
    mode = "internal"; next
}
line ~ /^[ \t]*# internal-only:end[ \t]*$/ {
    if (mode != "internal") fail("internal-only:end without a matching begin")
    mode = ""; next
}
line ~ /^[ \t]*# positive-only:begin[ \t]*$/ {
    if (mode != "") fail("nested block: positive-only:begin inside " mode)
    mode = "positive"; next
}
line ~ /^[ \t]*# positive-only:end[ \t]*$/ {
    if (mode != "positive") fail("positive-only:end without a matching begin")
    mode = ""; next
}
mode == "internal" { if (!positive) print $0; next }
mode == "positive" {
    if (positive) {
        if (line == "#") { print ""; next }
        if (line !~ /^# /) fail("line inside positive-only block must start with \"# \" (or be a lone #)")
        sub(/^# /, "", $0)
        print $0
    }
    next
}
{ print $0 }
END {
    if (!failed && mode != "") { printf "build-ring: %s: unclosed %s-only block\n", src, mode > "/dev/stderr"; exit 1 }
}
' "$source_file" > "$tmp_file"

case "$source_file" in
    *.ps1) sed -i "s/^\\\$Script:DefaultEnv = \"[^\"]*\"/\$Script:DefaultEnv = \"$ring\"/" "$tmp_file" ;;
    *)     sed -i "s/^DEFAULT_ENV=\"[^\"]*\"/DEFAULT_ENV=\"$ring\"/" "$tmp_file" ;;
esac

mkdir -p "$(dirname "$output_file")"
cp "$tmp_file" "$output_file"
