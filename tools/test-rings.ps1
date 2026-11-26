# PowerShell part of tools/test-rings.sh. Run it through that script, or directly:
#   pwsh -NoProfile -File tools/test-rings.ps1 -BuildDir <dir that holds <ring>\windows-installer.ps1>
#
# Checks the built Windows installer for every ring: it parses, -help, the unknown-parameter handling,
# the configuration summary and the helm upgrade arguments, the same things test-rings.sh checks for the bash scripts.
param(
    [Parameter(Mandatory = $true)][string]$BuildDir
)

$ErrorActionPreference = 'Stop'
$negativeRings = @('dev', 'test', 'stage')
$positiveRings = @('ea', 'ga')
$script:failures = 0
$script:checks = 0

# A child shell of the same flavour as this one, to run the built scripts the way a customer would.
$shellPath = (Get-Process -Id $PID).Path

function Test-Check {
    param([string]$Description, [bool]$Ok, [string]$Detail = '')
    $script:checks++
    if ($Ok) {
        Write-Output "PASS: $Description"
    } else {
        Write-Output "FAIL: $Description  -- $Detail"
        $script:failures++
    }
}

function Invoke-Built {
    param([string]$File, [string[]]$Arguments)
    $output = & $shellPath -NoProfile -ExecutionPolicy Bypass -File $File @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

# Runs a built script with its last line (Main) replaced by $Body, so single functions can be called without
# installing anything. Returns what the body wrote.
function Invoke-Harness {
    param([string]$File, [string]$Body)
    $text = Get-Content $File -Raw
    $harness = [regex]::Replace($text, '(?m)^Main\s*$', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $Body })
    $harnessFile = Join-Path (Split-Path $File) ('harness-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -Path $harnessFile -Value $harness
    try {
        return (& $shellPath -NoProfile -ExecutionPolicy Bypass -File $harnessFile 2>&1 | Out-String)
    } finally {
        Remove-Item $harnessFile -ErrorAction SilentlyContinue
    }
}

$summaryBody = @'
Initialize-Environment *> $null
$Script:ShoVersion = '1.2.3'
Show-Configuration
'@

function Get-InstallBody {
    param([string]$ArgsFile, [string]$Before = '')
    $escaped = $ArgsFile.Replace("'", "''")
    return @"
`$env:HELM_ARGS_FILE = '$escaped'
function helm {
    if (`$args[0] -eq 'pull') {
        `$i = [array]::IndexOf(`$args, '-d')
        New-Item -ItemType File -Path (Join-Path `$args[`$i + 1] 'self-hosted-operator-1.2.3.tgz') -Force | Out-Null
        `$global:LASTEXITCODE = 0
    } else {
        # a native helm.exe gets the argument array flattened, a PowerShell function receives it as one argument
        (@(`$args | ForEach-Object { `$_ }) -join "``n") | Set-Content `$env:HELM_ARGS_FILE
        `$global:LASTEXITCODE = 0
        'stub'
    }
}
function kubectl { `$global:LASTEXITCODE = 1 }
function Logout-EcrPublic {}
function Wait-ForPodsReady { `$true }
function Start-PortForwarding {}
$Before
Initialize-Environment *> `$null
`$Script:ShoVersion = '1.2.3'
`$null = Install-Sho
"@
}

function Get-HelmArgs {
    param([string]$File, [string]$Before = '')
    $argsFile = Join-Path ([System.IO.Path]::GetTempPath()) ('helm-args-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        $null = Invoke-Harness -File $File -Body (Get-InstallBody -ArgsFile $argsFile -Before $Before)
        if (Test-Path $argsFile) { return ((Get-Content $argsFile) -join "`n") }
        return ''
    } finally {
        Remove-Item $argsFile -ErrorAction SilentlyContinue
    }
}

$internalHelp = 'use-acr|pegasus_enabled|kevents_replicas|sh_monitoring'

# The -help of the ea/ga script must be the dev -help without the internal option block, so the two script
# folders do not drift apart in what customers read.
function Get-HelpLines {
    param([string]$File, [bool]$DropInternalBlock)
    $lines = @((Invoke-Built -File $File -Arguments @('-help')).Output -split "`r?`n" | ForEach-Object { $_.TrimEnd() })
    if (-not $DropInternalBlock) { return $lines }
    $kept = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    foreach ($line in $lines) {
        if ($line -match '^\s+-use-acr ') { $skipping = $true }
        if (-not $skipping) { $kept.Add($line) }
        if ($skipping -and $line -match 'Currently enabled only in the test cluster') { $skipping = $false }
    }
    return $kept.ToArray()
}
$expectedPositiveHelp = Get-HelpLines -File (Join-Path (Join-Path $BuildDir 'dev') 'windows-installer.ps1') -DropInternalBlock $true

foreach ($ring in ($negativeRings + $positiveRings)) {
    $file = Join-Path (Join-Path $BuildDir $ring) 'windows-installer.ps1'

    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$parseErrors)
    Test-Check "$ring/windows-installer.ps1 parses" ($parseErrors.Count -eq 0) (($parseErrors | ForEach-Object { $_.Message }) -join '; ')

    $help = Invoke-Built -File $file -Arguments @('-help')
    $helpLines = @($help.Output -split "`r?`n" | Where-Object { $_ -match $internalHelp }).Count

    if ($negativeRings -contains $ring) {
        Test-Check "$ring/windows-installer.ps1 -help lists the 4 internal options" ($helpLines -eq 4) "found $helpLines"

        $accepted = Invoke-Built -File $file -Arguments @('-use_acr', 'true', '-help')
        Test-Check "$ring/windows-installer.ps1 accepts -use_acr" ($accepted.ExitCode -eq 0) $accepted.Output

        $summary = Invoke-Harness -File $file -Body $summaryBody
        Test-Check "$ring/windows-installer.ps1 summary shows the internal lines" (($summary -match 'Use ACR:') -and ($summary -match 'SH Monitoring:') -and ($summary -match 'Kevents Replicas:'))

        $helmArgs = Get-HelmArgs -File $file
        Test-Check "$ring/windows-installer.ps1 helm upgrade passes the internal --set flags" (($helmArgs -match '(?m)^pegasusEnabled=false$') -and ($helmArgs -match '(?m)^keventsReplicas=0$') -and ($helmArgs -match '(?m)^shMonitoring=false$')) ($helmArgs -replace "`n", ' ')

        $helmAcr = Get-HelmArgs -File $file -Before "`$Script:UseAcr = `$true; `$env:SH_REGISTRY = 'reg'; `$env:SP_ID = 'id'; `$env:SP_SECRET = 'secret'"
        Test-Check "$ring/windows-installer.ps1 helm upgrade with -use_acr passes the registry flags" (($helmAcr -match '(?m)^registry.url=reg$') -and ($helmAcr -match '(?m)^enableECR.enabled=false$')) ($helmAcr -replace "`n", ' ')
    } else {
        Test-Check "$ring/windows-installer.ps1 -help lists none of the internal options" ($helpLines -eq 0) "found $helpLines"

        $actualHelp = Get-HelpLines -File $file -DropInternalBlock $false
        $same = ($actualHelp -join "`n") -ceq ($expectedPositiveHelp -join "`n")
        Test-Check "$ring/windows-installer.ps1 -help is the dev help minus the internal options" $same 'the positive and negative help texts differ'

        foreach ($parameter in @('-use_acr', '-pegasus_enabled', '-kevents_replicas', '-sh_monitoring')) {
            $result = Invoke-Built -File $file -Arguments @($parameter, '1', '-help')
            Test-Check "$ring/windows-installer.ps1 rejects $parameter as an unknown option" (($result.ExitCode -ne 0) -and ($result.Output -match 'Unknown option')) "exit $($result.ExitCode): $($result.Output.Trim())"
        }

        $summary = Invoke-Harness -File $file -Body $summaryBody
        Test-Check "$ring/windows-installer.ps1 summary has the common lines and none of the internal ones" (($summary -notmatch 'Use ACR|Kevents|SH Monitoring') -and ($summary -match "Environment:    $ring") -and ($summary -match 'Version:        1.2.3')) $summary

        $helmArgs = Get-HelmArgs -File $file
        $common = ($helmArgs -match "(?m)^ring=$ring$") -and ($helmArgs -match '(?m)^image.tag=v1.2.3$') -and ($helmArgs -match '(?m)^image.registry=public.ecr.aws/')
        $internal = $helmArgs -match 'pegasus|kevents|shMonitoring|registry\.(url|username|password)|enableECR'
        Test-Check "$ring/windows-installer.ps1 helm upgrade has the common flags and none of the internal ones" ($common -and -not $internal) ($helmArgs -replace "`n", ' ')
    }
}

if ($script:failures -eq 0) {
    Write-Output "PowerShell: all $($script:checks) checks passed."
    exit 0
}
Write-Output "PowerShell: $($script:failures) of $($script:checks) checks FAILED."
exit 1
