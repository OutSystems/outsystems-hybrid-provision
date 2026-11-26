#!/usr/bin/env bash
#
# Builds the installers for every ring and checks what a customer would get.
#
#   tools/test-rings.sh            # build into a temp dir and test
#   KEEP_BUILD=1 tools/test-rings.sh   # keep the built scripts (path is printed)
#   REQUIRE_POWERSHELL=1 ...       # fail instead of skipping when PowerShell is not available (used in CI)
#
# What is checked, per platform script (linux, macos, windows):
#   - every ring builds, no directive markers are left in the output and the script parses
#   - ea and ga contain none of the internal options, variables or registry aliases
#   - dev, test and stage still contain them (so a broken strip cannot pass as a clean ea/ga build)
#   - --help: dev/test/stage list the four internal options, ea/ga list none, and the rest of the help is identical
#   - an internal flag is rejected as an unknown option in ea/ga and accepted in dev/test/stage
#   - the configuration summary shows the internal lines only in dev/test/stage
#   - the helm upgrade arguments: internal --set flags only in dev/test/stage, the common flags in every ring

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
[[ "${KEEP_BUILD:-0}" == "1" ]] || trap 'rm -rf "$BUILD"' EXIT

NEGATIVE_RINGS=(dev test stage)
POSITIVE_RINGS=(ea ga)
ALL_RINGS=("${NEGATIVE_RINGS[@]}" "${POSITIVE_RINGS[@]}")

# Names that must never appear in an ea/ga script (case-insensitive), and the markers that must never appear anywhere.
FORBIDDEN='use[-_]acr|useacr|pegasus|kevents|sh[-_]monitoring|shmonitoring|SP_ID|SP_SECRET|SH_REGISTRY|u4p0z5h7|u5a4o8b8|w0o4m8y0|ECR_ALIAS_(TEST|STAGE|DEV)|EcrAlias(Test|Stage|Dev)|\bACR\b'
MARKERS='internal-only:|positive-only:'

failures=0
checks=0
check() { # check <description> <exit-code> [detail]
    checks=$((checks + 1))
    if [[ "$2" -eq 0 ]]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1${3:+  -- $3}"
        failures=$((failures + 1))
    fi
}

echo "Building every ring into $BUILD"
for script in linux-installer.sh macos-installer.sh windows-installer.ps1; do
    for ring in "${ALL_RINGS[@]}"; do
        "$ROOT/tools/build-ring.sh" "$ring" "$ROOT/scripts/$script" "$BUILD/$ring/$script"
        check "build $ring/$script" $?
    done
done

for script in linux-installer.sh macos-installer.sh windows-installer.ps1; do
    for ring in "${ALL_RINGS[@]}"; do
        ! grep -qE "$MARKERS" "$BUILD/$ring/$script"
        check "no directive markers left in $ring/$script" $?
    done
    for ring in "${POSITIVE_RINGS[@]}"; do
        hits="$(grep -niE "$FORBIDDEN" "$BUILD/$ring/$script" | head -3)"
        [[ -z "$hits" ]]
        check "$ring/$script has no internal option, variable or alias" $? "$hits"
    done
    for ring in "${NEGATIVE_RINGS[@]}"; do
        # Guards against a strip that silently removes too much: the internal ring must still have everything.
        n="$(grep -ciE 'pegasus|kevents|sh[-_]monitoring' "$BUILD/$ring/$script")"
        [[ "$n" -gt 0 ]]
        check "$ring/$script still has the internal options" $? "found $n matching lines"
    done
done

# ---- bash scripts -------------------------------------------------------------------------------------------------

INTERNAL_HELP='--use-acr|--pegasus-enabled|--kevents-replicas|--sh-monitoring'

# Prints the --help of a built script with the internal option block removed (what ea/ga should print).
help_without_internal_block() {
    bash "$1" --help 2>&1 | awk '/^    --use-acr=/ {skip=1} skip && /Currently enabled only in the test cluster/ {skip=0; next} !skip'
}

# Sources a built script, stubs everything that touches the outside world and prints the helm upgrade arguments.
helm_upgrade_args() { # helm_upgrade_args <script> [shell assignments to run before the install]
    (
        set +eu
        # shellcheck disable=SC1090
        source "$1"
        args_file="$(mktemp)"
        helm() {
            if [[ "$1" == "pull" ]]; then
                local dir=""
                while [[ $# -gt 0 ]]; do [[ "$1" == "-d" ]] && dir="$2"; shift; done
                touch "$dir/self-hosted-operator-1.2.3.tgz"
            else
                printf '%s\n' "$@" > "$args_file"
                echo "stub"
            fi
            return 0
        }
        kubectl() { return 1; }
        logout_ecr_public() { :; }
        wait_for_pods_ready() { return 0; }
        start_port_forwarding() { :; }
        SHO_VERSION="1.2.3"
        [[ -n "${2:-}" ]] && eval "$2"
        setup_environment > /dev/null 2>&1
        sho_install > /dev/null 2>&1
        trap - EXIT   # sho_install sets an EXIT trap for its temp dir; drop it so it does not fire after the stubbed run
        cat "$args_file"
        rm -f "$args_file"
    )
}

summary_of() { # summary_of <script>
    (
        set +e
        # shellcheck disable=SC1090
        source "$1"
        OPERATION="install"; SHO_VERSION="1.2.3"
        setup_environment > /dev/null 2>&1
        show_configuration
    )
}

for script in linux-installer.sh macos-installer.sh; do
    echo
    echo "== $script"
    for ring in "${ALL_RINGS[@]}"; do
        file="$BUILD/$ring/$script"
        bash -n "$file"
        check "$ring/$script parses" $?
    done

    for ring in "${NEGATIVE_RINGS[@]}"; do
        file="$BUILD/$ring/$script"
        help="$(bash "$file" --help 2>&1)"
        n="$(grep -cE -- "$INTERNAL_HELP" <<< "$help")"
        [[ "$n" -eq 4 ]]
        check "$ring/$script --help lists the 4 internal options" $? "found $n"

        bash "$file" --use-acr=true --help > /dev/null 2>&1
        check "$ring/$script accepts --use-acr" $?

        grep -qE 'Use ACR:' <<< "$(summary_of "$file")"
        check "$ring/$script summary shows the internal lines" $?

        out="$(helm_upgrade_args "$file")"
        grep -q '^pegasusEnabled=false$' <<< "$out" && grep -q '^keventsReplicas=0$' <<< "$out" && grep -q '^shMonitoring=false$' <<< "$out"
        check "$ring/$script helm upgrade passes the internal --set flags" $? "$(tr '\n' ' ' <<< "$out")"

        out="$(helm_upgrade_args "$file" 'USE_ACR=true; SH_REGISTRY=reg; SP_ID=id; SP_SECRET=secret')"
        grep -q '^registry.url=reg$' <<< "$out" && grep -q '^enableECR.enabled=false$' <<< "$out"
        check "$ring/$script helm upgrade with --use-acr passes the registry flags" $? "$(tr '\n' ' ' <<< "$out")"
    done

    expected_help="$(help_without_internal_block "$BUILD/dev/$script")"
    for ring in "${POSITIVE_RINGS[@]}"; do
        file="$BUILD/$ring/$script"
        help="$(bash "$file" --help 2>&1)"
        ! grep -qE -- "$INTERNAL_HELP" <<< "$help"
        check "$ring/$script --help lists none of the internal options" $?

        [[ "$help" == "$expected_help" ]]
        check "$ring/$script --help is the dev help minus the internal options" $?

        for flag in --use-acr=true --pegasus-enabled=true --kevents-replicas=1 --sh-monitoring=true; do
            out="$(bash "$file" "$flag" 2>&1)"; code=$?
            [[ $code -ne 0 ]] && grep -q 'Unknown option' <<< "$out"
            check "$ring/$script rejects $flag as an unknown option" $? "exit $code"
        done

        s="$(summary_of "$file")"
        ! grep -qE 'Use ACR|Kevents|SH Monitoring' <<< "$s" && grep -q "Environment:    $ring" <<< "$s" && grep -q 'Version:        1.2.3' <<< "$s"
        check "$ring/$script summary has the common lines and none of the internal ones" $?

        out="$(helm_upgrade_args "$file")"
        grep -q "^ring=$ring$" <<< "$out" && grep -q '^image.tag=v1.2.3$' <<< "$out" && grep -q '^image.registry=public.ecr.aws/' <<< "$out" \
            && ! grep -qE 'pegasus|kevents|shMonitoring|registry\.(url|username|password)|enableECR' <<< "$out"
        check "$ring/$script helm upgrade has the common flags and none of the internal ones" $? "$(tr '\n' ' ' <<< "$out")"
    done
done

# ---- PowerShell script --------------------------------------------------------------------------------------------

echo
echo "== windows-installer.ps1"
ps_status=0
if command -v pwsh > /dev/null 2>&1; then
    pwsh -NoProfile -File "$ROOT/tools/test-rings.ps1" -BuildDir "$BUILD"
    ps_status=$?
elif command -v powershell.exe > /dev/null 2>&1; then
    # WSL: Windows PowerShell can only run files from a Windows path, so work in the Windows temp folder.
    win_tmp="$(cd /mnt/c && powershell.exe -NoProfile -Command '$env:TEMP' | tr -d '\r')"
    work="$(wslpath "$win_tmp")/ring-tests-$$"
    mkdir -p "$work" && cp -r "$BUILD" "$work/build" && cp "$ROOT/tools/test-rings.ps1" "$work/"
    (cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$work/test-rings.ps1")" -BuildDir "$(wslpath -w "$work/build")" | tr -d '\r')
    ps_status=${PIPESTATUS[0]}
    rm -rf "$work"
elif [[ "${REQUIRE_POWERSHELL:-0}" == "1" ]]; then
    echo "FAIL: PowerShell is required (REQUIRE_POWERSHELL=1) but neither pwsh nor powershell.exe was found"
    ps_status=1
else
    echo "SKIP: no PowerShell found (set REQUIRE_POWERSHELL=1 to make this a failure)"
fi
[[ $ps_status -eq 0 ]]
check "windows-installer.ps1 PowerShell checks" $?

echo
if [[ $failures -eq 0 ]]; then
    echo "All $checks checks passed."
    [[ "${KEEP_BUILD:-0}" == "1" ]] && echo "Built scripts kept in $BUILD"
    exit 0
fi
echo "$failures of $checks checks FAILED."
exit 1
