# PowerShell script for installing OutSystems Self-Hosted Operator on Windows
# Requires PowerShell 5.1 or later

param(
    [string]$Version,
    [string]$Repository,
    [string]$Public = "true",
    [switch]$Uninstall,
    [switch]$Help,
    [switch]$LocalInstall
)

# Set error action preference to stop on errors
$ErrorActionPreference = "Stop"

# Check if running as administrator
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to restart as administrator if needed
function Start-AsAdmin {
    if (-not (Test-IsAdmin)) {
        Write-Host "[WARN] This script requires administrator privileges to install tools system-wide." -ForegroundColor Yellow
        Write-Host "[INFO] Attempting to restart as administrator..." -ForegroundColor Cyan
        
        $scriptPath = $MyInvocation.ScriptName
        $arguments = @()
        
        # Build arguments array from bound parameters
        foreach ($param in $MyInvocation.BoundParameters.GetEnumerator()) {
            if ($param.Value -is [switch] -and $param.Value) {
                $arguments += "-$($param.Key)"
            } elseif ($param.Value -isnot [switch]) {
                $arguments += "-$($param.Key)"
                $arguments += "`"$($param.Value)`""
            }
        }
        
        $argumentString = $arguments -join " "
        
        # Create command that keeps window open
        $command = "& `"$scriptPath`" $argumentString; Write-Host ''; Write-Host '[INFO] Script execution completed. Press any key to close this window...' -ForegroundColor Green; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')"
        
        try {
            Start-Process powershell -Verb RunAs -ArgumentList "-NoExit", "-Command", $command
            exit 0
        } catch {
            Write-Host "[ERROR] Failed to restart as administrator. Please run PowerShell as administrator manually." -ForegroundColor Red
            Write-Host "[INFO] Right-click PowerShell and select 'Run as administrator', then run this script again." -ForegroundColor Yellow
            exit 1
        }
    }
}

# Configuration
$NAMESPACE = "self-hosted-operator"
$NAMESPACE_CRED_JOB = "self-hosted-registry-credentials-job"
$CHART_NAME = "self-hosted-operator"

# Default repository URL
if (-not $Repository) {
    $HELM_REPO_URL = if ($env:HELM_REPO_URL) { $env:HELM_REPO_URL } else { "oci://quay.io/rgi-sergio/helm" }
    $CHART_REPO = "$HELM_REPO_URL/$CHART_NAME"
} else {
    $CHART_REPO = "$Repository/$CHART_NAME"
}

$IMAGE_REGISTRY = if ($env:IMAGE_REGISTRY) { $env:IMAGE_REGISTRY } else { "quay.io/rgi-sergio" }
$IMAGE_REPOSITORY = "self-hosted-operator"
$PUBLIC_REPO = $Public

$SH_REGISTRY = ""

# Set version
$HELM_CHART_VERSION = if ($Version) { $Version } else { "latest" }

# Function to check if a command exists
function Test-CommandExists {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check if Helm is installed
function Test-HelmInstalled {
    Write-Host "[INFO] Checking Helm installation..." -ForegroundColor Cyan
    
    if (Test-CommandExists "helm") {
        Write-Host "[OK] Helm is already installed" -ForegroundColor Green
        try {
            $helmVersion = helm version --short 2>$null
            Write-Host "   Version: $helmVersion" -ForegroundColor Gray
            return $true
        } catch {
            Write-Host "   Helm command available" -ForegroundColor Gray
            return $true
        }
    } else {
        Write-Host "[ERROR] Helm is not installed" -ForegroundColor Red
        return $false
    }
}

# Function to install Helm on Windows
function Install-Helm {
    Write-Host "[INFO] Installing Helm..." -ForegroundColor Cyan
    
    # Check if LocalInstall is specified or if we don't have admin privileges
    if ($LocalInstall -or -not (Test-IsAdmin)) {
        Write-Host "[INFO] Installing Helm locally..." -ForegroundColor Yellow
        return Install-HelmLocal
    }
    
    # Check if Chocolatey is available
    if (Test-CommandExists "choco") {
        Write-Host "[INFO] Installing Helm via Chocolatey..." -ForegroundColor Yellow
        try {
            choco install kubernetes-helm -y
            Write-Host "[OK] Helm installed successfully via Chocolatey" -ForegroundColor Green
            helm version --short
            return $true
        } catch {
            Write-Host "[ERROR] Failed to install Helm via Chocolatey" -ForegroundColor Red
            Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
            return Install-HelmLocal
        }
    } elseif (Test-CommandExists "winget") {
        Write-Host "[INFO] Installing Helm via winget..." -ForegroundColor Yellow
        try {
            $wingetOutput = winget install Helm.Helm --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Helm installed successfully via winget" -ForegroundColor Green
                # Refresh environment variables
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                # Test if helm is now available
                if (Test-CommandExists "helm") {
                    helm version --short
                    return $true
                } else {
                    Write-Host "[WARN] Helm installed but not found in PATH. Trying local installation..." -ForegroundColor Yellow
                    return Install-HelmLocal
                }
            } else {
                Write-Host "[ERROR] winget install failed with exit code $LASTEXITCODE" -ForegroundColor Red
                Write-Host "Output: $wingetOutput" -ForegroundColor Gray
                Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
                return Install-HelmLocal
            }
        } catch {
            Write-Host "[ERROR] Failed to install Helm via winget: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
            return Install-HelmLocal
        }
    } else {
        Write-Host "[INFO] Package managers not found. Installing Helm locally..." -ForegroundColor Yellow
        return Install-HelmLocal
    }
}

# Function to install Helm locally
function Install-HelmLocal {
    Write-Host "[INFO] Installing Helm locally in current directory..." -ForegroundColor Yellow
    
    try {
        # Create local tools directory
        $toolsDir = Join-Path (Get-Location) "tools"
        $helmDir = Join-Path $toolsDir "helm"
        
        if (-not (Test-Path $toolsDir)) {
            New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
            Write-Host "[INFO] Created tools directory: $toolsDir" -ForegroundColor Gray
        }
        
        if (-not (Test-Path $helmDir)) {
            New-Item -ItemType Directory -Path $helmDir -Force | Out-Null
        }
        
        Write-Host "[INFO] Downloading Helm..." -ForegroundColor Yellow
        
        # Create temp directory
        $tempDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
        
        # Get latest Helm version
        $latestVersion = (Invoke-RestMethod "https://api.github.com/repos/helm/helm/releases/latest").tag_name
        $downloadUrl = "https://get.helm.sh/helm-$latestVersion-windows-amd64.zip"
        
        $zipPath = Join-Path $tempDir "helm.zip"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
        
        # Extract
        Expand-Archive -Path $zipPath -DestinationPath $tempDir
        $helmExe = Get-ChildItem -Path $tempDir -Recurse -Name "helm.exe" | Select-Object -First 1
        $extractedHelmPath = Join-Path $tempDir (Split-Path $helmExe -Parent)
        
        # Copy to local tools directory
        Copy-Item (Join-Path $extractedHelmPath "helm.exe") $helmDir -Force
        
        # Add to PATH for current session
        $env:PATH = "$helmDir;$env:PATH"
        
        # Clean up
        Remove-Item $tempDir -Recurse -Force
        
        Write-Host "[OK] Helm installed locally at: $helmDir" -ForegroundColor Green
        Write-Host "[INFO] Helm version:" -ForegroundColor Gray
        & "$helmDir\helm.exe" version --short
        
        # Create a helper script for future sessions
        $helperScript = @"
# Add Helm to PATH for this session
`$helmPath = Join-Path (Get-Location) "tools\helm"
if (Test-Path `$helmPath) {
    `$env:PATH = "`$helmPath;`$env:PATH"
    Write-Host "[INFO] Added Helm to PATH: `$helmPath" -ForegroundColor Green
}
"@
        $helperPath = Join-Path $toolsDir "setup-path.ps1"
        $helperScript | Out-File -FilePath $helperPath -Encoding UTF8
        
        Write-Host "[INFO] Helper script created: $helperPath" -ForegroundColor Blue
        Write-Host "[INFO] Run '. .\tools\setup-path.ps1' in future sessions to add tools to PATH" -ForegroundColor Blue
        
        return $true
    } catch {
        Write-Host "[ERROR] Failed to install Helm locally: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to ensure Helm is installed
function Ensure-HelmInstalled {
    if (Test-HelmInstalled) {
        return $true
    } else {
        Write-Host "[INFO] Helm not found. Proceeding with installation..." -ForegroundColor Yellow
        return Install-Helm
    }
}

# Function to check if kubectl is installed
function Test-KubectlInstalled {
    Write-Host "[INFO] Checking kubectl installation..." -ForegroundColor Cyan
    
    if (Test-CommandExists "kubectl") {
        Write-Host "[OK] kubectl is already installed" -ForegroundColor Green
        try {
            $kubectlVersion = kubectl version --client --output=yaml 2>$null | Select-String "gitVersion"
            if ($kubectlVersion) {
                Write-Host "   $kubectlVersion" -ForegroundColor Gray
            } else {
                Write-Host "   kubectl client version available" -ForegroundColor Gray
            }
            return $true
        } catch {
            Write-Host "   kubectl client available" -ForegroundColor Gray
            return $true
        }
    } else {
        Write-Host "[ERROR] kubectl is not installed" -ForegroundColor Red
        return $false
    }
}

# Function to install kubectl on Windows
function Install-Kubectl {
    Write-Host "[INFO] Installing kubectl..." -ForegroundColor Cyan
    
    # Check if LocalInstall is specified or if we don't have admin privileges
    if ($LocalInstall -or -not (Test-IsAdmin)) {
        Write-Host "[INFO] Installing kubectl locally..." -ForegroundColor Yellow
        return Install-KubectlLocal
    }
    
    # Check if Chocolatey is available
    if (Test-CommandExists "choco") {
        Write-Host "[INFO] Installing kubectl via Chocolatey..." -ForegroundColor Yellow
        try {
            choco install kubernetes-cli -y
            Write-Host "[OK] kubectl installed successfully via Chocolatey" -ForegroundColor Green
            try {
                kubectl version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
            } catch {
                Write-Host "   kubectl client installed successfully" -ForegroundColor Gray
            }
            return $true
        } catch {
            Write-Host "[ERROR] Failed to install kubectl via Chocolatey" -ForegroundColor Red
            Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
            return Install-KubectlLocal
        }
    } elseif (Test-CommandExists "winget") {
        Write-Host "[INFO] Installing kubectl via winget..." -ForegroundColor Yellow
        try {
            $wingetOutput = winget install Kubernetes.kubectl --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] kubectl installed successfully via winget" -ForegroundColor Green
                # Refresh environment variables
                $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
                # Test if kubectl is now available
                if (Test-CommandExists "kubectl") {
                    try {
                        kubectl version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
                    } catch {
                        Write-Host "   kubectl client installed successfully" -ForegroundColor Gray
                    }
                    return $true
                } else {
                    Write-Host "[WARN] kubectl installed but not found in PATH. Trying local installation..." -ForegroundColor Yellow
                    return Install-KubectlLocal
                }
            } else {
                Write-Host "[ERROR] winget install failed with exit code $LASTEXITCODE" -ForegroundColor Red
                Write-Host "Output: $wingetOutput" -ForegroundColor Gray
                Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
                return Install-KubectlLocal
            }
        } catch {
            Write-Host "[ERROR] Failed to install kubectl via winget: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[INFO] Attempting local installation..." -ForegroundColor Yellow
            return Install-KubectlLocal
        }
    } else {
        Write-Host "[INFO] Package managers not found. Installing kubectl locally..." -ForegroundColor Yellow
        return Install-KubectlLocal
    }
}

# Function to install kubectl locally
function Install-KubectlLocal {
    Write-Host "[INFO] Installing kubectl locally in current directory..." -ForegroundColor Yellow
    
    try {
        # Create local tools directory
        $toolsDir = Join-Path (Get-Location) "tools"
        $kubectlDir = Join-Path $toolsDir "kubectl"
        
        if (-not (Test-Path $toolsDir)) {
            New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
            Write-Host "[INFO] Created tools directory: $toolsDir" -ForegroundColor Gray
        }
        
        if (-not (Test-Path $kubectlDir)) {
            New-Item -ItemType Directory -Path $kubectlDir -Force | Out-Null
        }
        
        Write-Host "[INFO] Downloading kubectl..." -ForegroundColor Yellow
        
        # Get latest stable version
        $latestVersion = (Invoke-WebRequest -Uri "https://dl.k8s.io/release/stable.txt" -UseBasicParsing).Content.Trim()
        $downloadUrl = "https://dl.k8s.io/release/$latestVersion/bin/windows/amd64/kubectl.exe"
        
        $kubectlPath = Join-Path $kubectlDir "kubectl.exe"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $kubectlPath
        
        # Add to PATH for current session
        $env:PATH = "$kubectlDir;$env:PATH"
        
        Write-Host "[OK] kubectl installed locally at: $kubectlDir" -ForegroundColor Green
        Write-Host "[INFO] kubectl version:" -ForegroundColor Gray
        try {
            & "$kubectlPath" version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
        } catch {
            Write-Host "   kubectl client installed successfully" -ForegroundColor Gray
        }
        
        # Update the helper script to include kubectl
        $helperScript = @"
# Add tools to PATH for this session
`$toolsPath = Join-Path (Get-Location) "tools"
`$helmPath = Join-Path `$toolsPath "helm"
`$kubectlPath = Join-Path `$toolsPath "kubectl"

if (Test-Path `$helmPath) {
    `$env:PATH = "`$helmPath;`$env:PATH"
    Write-Host "[INFO] Added Helm to PATH: `$helmPath" -ForegroundColor Green
}

if (Test-Path `$kubectlPath) {
    `$env:PATH = "`$kubectlPath;`$env:PATH"
    Write-Host "[INFO] Added kubectl to PATH: `$kubectlPath" -ForegroundColor Green
}
"@
        $helperPath = Join-Path $toolsDir "setup-path.ps1"
        $helperScript | Out-File -FilePath $helperPath -Encoding UTF8
        
        Write-Host "[INFO] Helper script updated: $helperPath" -ForegroundColor Blue
        
        return $true
    } catch {
        Write-Host "[ERROR] Failed to install kubectl locally: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to ensure kubectl is installed
function Ensure-KubectlInstalled {
    if (Test-KubectlInstalled) {
        return $true
    } else {
        Write-Host "[INFO] kubectl not found. Proceeding with installation..." -ForegroundColor Yellow
        return Install-Kubectl
    }
}

# Function to verify repository access
function Test-RepoAccess {
    Write-Host "[INFO] Verifying repository access" -ForegroundColor Cyan
    
    try {
        # Capture both stdout and stderr
        $helmOutput = helm show chart $CHART_REPO
        
        # Convert output to string for analysis
        $outputString = $helmOutput -join "`n"

        # For OCI registries, success can be indicated by:
        # 1. Exit code 0
        # 2. "Pulled:" message in output (indicates successful chart pull from OCI registry)
        # 3. Presence of chart metadata (apiVersion, name, version, etc.)
        $isOciSuccess = $outputString -match "Pulled:\s+.*$CHART_NAME" -or 
                       $outputString -match "apiVersion:\s*v\d+" -or
                       $outputString -match "name:\s*$CHART_NAME"
        
        if ($LASTEXITCODE -eq 0 -or $isOciSuccess) {
            if ($outputString -match "Pulled:") {
                Write-Host "[OK] Successfully pulled chart from OCI registry" -ForegroundColor Green
            } else {
                Write-Host "[OK] SHO Registry is accessible" -ForegroundColor Green
            }
            return $true
        } else {
            # Check if this might be an authentication issue
            if ($outputString -match "unauthorized|authentication|login" -or 
                $outputString -match "401|403") {
                Write-Host "[ERROR] Authentication required to access repository" -ForegroundColor Red
                Write-Host "[INFO] Try setting REGISTRY_USERNAME and REGISTRY_PASSWORD environment variables" -ForegroundColor Yellow
            } else {
                Write-Host "[ERROR] Cannot access OutSystems repository or no charts found" -ForegroundColor Red
            }
            
            # Only show output if it's not too verbose and might be helpful
            if ($outputString.Length -lt 500 -and $outputString -notmatch "^$") {
                Write-Host "Error details: $outputString" -ForegroundColor Red
            }
            return $false
        }
    } catch {
        Write-Host "[ERROR] Cannot access OutSystems repository or no charts found" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to login to repository
function Invoke-RepoLogin {
    Write-Host "[INFO] Logging in to SHO private repository" -ForegroundColor Cyan
    
    # Handle authentication if credentials are provided
    $registryUsername = $env:REGISTRY_USERNAME
    $registryPassword = $env:REGISTRY_PASSWORD
    
    if ($registryUsername -and $registryPassword) {
        Write-Host "[INFO] Credentials provided, authenticating with SHO registry..." -ForegroundColor Yellow
        try {
            # For OCI registries, we need to login to the registry hostname, not the full chart path
            # Extract registry hostname from CHART_REPO (e.g., "oci://quay.io/rgi-sergio/helm/self-hosted-operator" -> "quay.io")
            $registryHost = ""
            if ($CHART_REPO -match "oci://([^/]+)") {
                $registryHost = $matches[1]
            } else {
                # Fallback: use the full CHART_REPO
                $registryHost = $CHART_REPO
            }
            
            Write-Host "[INFO] Authenticating with registry: $registryHost" -ForegroundColor Gray
            
            # Use --password-stdin for secure password passing
            $loginResult = $registryPassword | helm registry login $registryHost --username $registryUsername --password-stdin 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Successfully authenticated with OCI registry" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[ERROR] Authentication failed" -ForegroundColor Red
                # Only show login error if it's not too verbose
                $errorString = $loginResult -join " "
                if ($errorString.Length -lt 300) {
                    Write-Host "Login error: $errorString" -ForegroundColor Red
                }
                return $false
            }
        } catch {
            Write-Host "[ERROR] Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "[INFO] No credentials provided, set REGISTRY_USERNAME and REGISTRY_PASSWORD environment variables to authenticate or set PUBLIC_REPO to true for public access" -ForegroundColor Blue
    }
    
    return $true
}

# Function to check all dependencies
function Test-Dependencies {
    $allDepsOk = $true
    
    # Check Helm
    Write-Host "[INFO] Checking Helm..." -ForegroundColor Cyan
    if (-not (Ensure-HelmInstalled)) {
        Write-Host "[ERROR] Failed to ensure Helm is available" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    # Check kubectl
    Write-Host "[INFO] Checking kubectl..." -ForegroundColor Cyan
    if (-not (Ensure-KubectlInstalled)) {
        Write-Host "[ERROR] Failed to ensure kubectl is available" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    # Check Kubernetes cluster connectivity using Helm
    Write-Host "[INFO] Checking Kubernetes cluster connectivity via Helm..." -ForegroundColor Cyan
    try {
        helm list --all-namespaces 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Helm can connect to Kubernetes cluster" -ForegroundColor Green
        } else {
            throw "Helm cannot connect to cluster"
        }
    } catch {
        Write-Host "[ERROR] Helm cannot connect to Kubernetes cluster" -ForegroundColor Red
        Write-Host "   Make sure you have:" -ForegroundColor Yellow
        Write-Host "   - A valid kubeconfig file" -ForegroundColor Yellow
        Write-Host "   - Access to a Kubernetes cluster" -ForegroundColor Yellow
        Write-Host "   - Proper cluster permissions" -ForegroundColor Yellow
        $allDepsOk = $false
    }
    
    # Verify OutSystems helm repository
    if (Test-RepoAccess) {
        Write-Host "[OK] OutSystems repository is ready" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] SHO repository verification failed" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    if ($allDepsOk) {
        Write-Host "[SUCCESS] All required dependencies are satisfied!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "[ERROR] Some dependencies are missing or failed to install" -ForegroundColor Red
        return $false
    }
}

# Function to show usage
function Show-Usage {
    Write-Host "Usage: .\install.ps1 [OPTIONS]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Version VERSION         The SHO chart version to install (optional, defaults to latest)" -ForegroundColor Gray
    Write-Host "  -Repository REPO_URL     The SHO registry URL (optional, uses default if not specified)" -ForegroundColor Gray
    Write-Host "  -Public true/false       Whether to use public repository access (optional, defaults to true)" -ForegroundColor Gray
    Write-Host "  -LocalInstall            Install tools locally in current directory (no admin privileges required)" -ForegroundColor Gray
    Write-Host "  -Uninstall               Uninstall OutSystems Self-Hosted Operator" -ForegroundColor Gray
    Write-Host "  -Help                    Show this help message" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\install.ps1" -ForegroundColor Gray
    Write-Host "  .\install.ps1 -LocalInstall" -ForegroundColor Gray
    Write-Host "  .\install.ps1 -Version 1.2.3" -ForegroundColor Gray
    Write-Host "  .\install.ps1 -Repository private-registry.example.com -Public false -LocalInstall" -ForegroundColor Gray
    Write-Host "  .\install.ps1 -Version 1.2.3 -Repository private-registry.example.com -Public false" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Installation Modes:" -ForegroundColor Yellow
    Write-Host "  Default:      Tries system-wide installation (requires admin privileges)" -ForegroundColor Gray
    Write-Host "  -LocalInstall: Installs tools in ./tools/ directory (no admin privileges required)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Environment Variables (optional for private repositories):" -ForegroundColor Yellow
    Write-Host "  REGISTRY_USERNAME  Username for SHO registry authentication" -ForegroundColor Gray
    Write-Host "  REGISTRY_PASSWORD  Password for SHO registry authentication" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Authentication Examples:" -ForegroundColor Yellow
    Write-Host "  # Public repository (default)" -ForegroundColor Gray
    Write-Host "  .\install.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  # Private repository with authentication (local install)" -ForegroundColor Gray
    Write-Host "  `$env:REGISTRY_USERNAME='myuser'" -ForegroundColor Gray
    Write-Host "  `$env:REGISTRY_PASSWORD='mypassword'" -ForegroundColor Gray
    Write-Host "  .\install.ps1 -Repository private-registry.example.com -Public false -LocalInstall" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Local Installation Notes:" -ForegroundColor Blue
    Write-Host "  - Tools are installed in ./tools/ directory" -ForegroundColor Gray
    Write-Host "  - Run '. .\tools\setup-path.ps1' to add tools to PATH in new sessions" -ForegroundColor Gray
    Write-Host "  - No administrator privileges required" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Note: When -Public false, you must provide REGISTRY_USERNAME and REGISTRY_PASSWORD environment variables." -ForegroundColor Blue
}

# Function to check SHO pods status
function Test-ShoPodsStatus {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    $maxWaitTime = 300  # 5 minutes
    $checkInterval = 10  # 10 seconds
    $elapsedTime = 0
    
    Write-Host "[INFO] Checking OutSystems Self-Hosted Operator pod status..." -ForegroundColor Cyan
    Write-Host "   Namespace: $Namespace" -ForegroundColor Gray
    Write-Host "   Release: $ReleaseName" -ForegroundColor Gray
    Write-Host ""
    
    while ($elapsedTime -lt $maxWaitTime) {
        # Get pod status
        try {
            $podInfo = kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" --no-headers 2>$null
            
            if (-not $podInfo) {
                Write-Host "[INFO] No pods found yet... (${elapsedTime}s elapsed)" -ForegroundColor Yellow
            } else {
                Write-Host "[INFO] Current pod status:" -ForegroundColor Cyan
                Write-Host $podInfo -ForegroundColor Gray
                Write-Host ""
                
                # Check if any pod is running and ready
                $runningPods = ($podInfo | Select-String "Running.*true").Count
                $totalPods = ($podInfo -split "`n").Count
                
                if ($runningPods -gt 0 -and $runningPods -eq $totalPods) {
                    Write-Host "[OK] All SHO pods are running and ready!" -ForegroundColor Green
                    return $true
                } elseif ($podInfo -match "Error|CrashLoopBackOff|ImagePullBackOff") {
                    Write-Host "[ERROR] Pod(s) in error state detected!" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "[INFO] Detailed pod status:" -ForegroundColor Cyan
                    kubectl describe pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName"
                    Write-Host ""
                    Write-Host "[INFO] Pod events:" -ForegroundColor Cyan
                    kubectl get events -n $Namespace --field-selector involvedObject.kind=Pod --sort-by=.metadata.creationTimestamp
                    return $false
                } else {
                    Write-Host "[INFO] Pods still starting... ($runningPods/$totalPods ready) - waiting ${checkInterval}s..." -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "[INFO] Checking pod status... (${elapsedTime}s elapsed)" -ForegroundColor Yellow
        }
        
        Start-Sleep $checkInterval
        $elapsedTime += $checkInterval
        Write-Host "   Elapsed time: ${elapsedTime}s / ${maxWaitTime}s" -ForegroundColor Gray
        Write-Host ""
    }
    
    Write-Host "[WARN] Timeout reached while waiting for pods to be ready" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Final pod status:" -ForegroundColor Cyan
    try {
        kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName" -o wide 2>$null
    } catch {
        Write-Host "No pods found" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "[INFO] Recent events:" -ForegroundColor Cyan
    try {
        kubectl get events -n $Namespace --sort-by=.metadata.creationTimestamp --tail=10 2>$null
    } catch {
        Write-Host "No events available" -ForegroundColor Gray
    }
    
    return $false
}

# Function to show troubleshooting commands
function Show-TroubleshootingCommands {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    Write-Host "[INFO] Troubleshooting Commands:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Check pod status:" -ForegroundColor Cyan
    Write-Host "   kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Describe pods:" -ForegroundColor Cyan
    Write-Host "   kubectl describe pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] View pod logs:" -ForegroundColor Cyan
    Write-Host "   kubectl logs -n $Namespace -l app.kubernetes.io/instance=$ReleaseName --tail=50" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Check events:" -ForegroundColor Cyan
    Write-Host "   kubectl get events -n $Namespace --sort-by=.metadata.creationTimestamp" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Check helm status:" -ForegroundColor Cyan
    Write-Host "   helm status $ReleaseName -n $Namespace" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[INFO] Restart deployment:" -ForegroundColor Cyan
    Write-Host "   kubectl rollout restart deployment -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Gray
}

# Function to install SHO
function Install-Sho {
    Write-Host "[INFO] Installing OutSystems Self-Hosted Operator..." -ForegroundColor Cyan
    
    # Prepare the chart URL
    $localChartRepo = $CHART_REPO
    
    if ($HELM_CHART_VERSION -ne "latest") {
        $localChartRepo = "${CHART_REPO}:$HELM_CHART_VERSION"
        $imageVersion = "v$HELM_CHART_VERSION"
    }
    
    Write-Host "[INFO] Installing SHO chart from: $localChartRepo" -ForegroundColor Yellow
    
    $releaseName = "self-hosted-operator"
    
    # Create namespaces
    try {
        kubectl create namespace $NAMESPACE 2>$null
    } catch {
        Write-Host "Namespace $NAMESPACE already exists, skipping creation" -ForegroundColor Gray
    }
    
    try {
        kubectl create namespace $NAMESPACE_CRED_JOB 2>$null
    } catch {
        Write-Host "Namespace $NAMESPACE_CRED_JOB already exists, skipping creation" -ForegroundColor Gray
    }
    
    Write-Host "[INFO] Running Helm install command..." -ForegroundColor Yellow
    
    # Initialize variables to capture output
    $installOutput = ""
    $installExitCode = 0
    
    # Temporarily set error action to continue to prevent exceptions from helm output
    $originalErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
        
        # Execute helm command and capture both stdout and stderr
        $installOutput = helm upgrade --install $releaseName $localChartRepo `
            --namespace $NAMESPACE `
            --create-namespace `
            --set "image.registry=$IMAGE_REGISTRY" `
            --set "image.repository=$IMAGE_REPOSITORY" `
            --set "image.tag=$imageVersion" `
            --set "registry.url=$SH_REGISTRY" `
            --set-string "podAnnotations.timestamp=$timestamp" 2>&1
        
        # Capture the exit code immediately
        $installExitCode = $LASTEXITCODE
        
        # Convert output to string for analysis
        $outputString = if ($installOutput -is [array]) { $installOutput -join "`n" } else { $installOutput }
        
        # Check for success indicators
        $isSuccess = ($installExitCode -eq 0) -or 
                     ($outputString -match "STATUS: deployed") -or
                     ($outputString -match "Pulled:.*$CHART_NAME") -or
                     ($outputString -match "Release.*has been.*upgraded")
        
        if ($isSuccess) {
            Write-Host "[OK] OutSystems Self-Hosted Operator installed successfully!" -ForegroundColor Green
            Write-Host "[INFO] Release name: $releaseName" -ForegroundColor Gray
            Write-Host ""
            
            # Show relevant output (filter out verbose OCI messages if needed)
            if ($outputString -and $outputString.Length -lt 1000) {
                Write-Host "[INFO] Installation details:" -ForegroundColor Cyan
                Write-Host $outputString -ForegroundColor Gray
            } elseif ($outputString -match "STATUS: deployed") {
                $relevantLines = $outputString -split "`n" | Where-Object { $_ -match "STATUS:|REVISION:|NAMESPACE:|NOTES:" }
                if ($relevantLines) {
                    Write-Host "[INFO] Installation summary:" -ForegroundColor Cyan
                    Write-Host ($relevantLines -join "`n") -ForegroundColor Gray
                }
            }
            Write-Host ""
            
            # Check if pods are running
            Write-Host "[INFO] Waiting for pods to be ready..." -ForegroundColor Yellow
            if (Test-ShoPodsStatus $releaseName $NAMESPACE) {
                Write-Host "[SUCCESS] OutSystems Self-Hosted Operator is running successfully!" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Installation completed but pods are not ready yet" -ForegroundColor Yellow
                Write-Host ""
                Show-TroubleshootingCommands $releaseName $NAMESPACE
            }
            Write-Host ""
            return $true
        } else {
            Write-Host "[ERROR] Failed to install OutSystems Self-Hosted Operator" -ForegroundColor Red
            Write-Host "[INFO] Exit code: $installExitCode" -ForegroundColor Cyan
            if ($outputString) {
                Write-Host "[INFO] Error details:" -ForegroundColor Cyan
                Write-Host $outputString -ForegroundColor Red
            }
            
            # Parse specific error types
            if ($outputString -match "401.*Unauthorized|unauthorized|authentication") {
                Write-Host ""
                Write-Host "[INFO] Authentication issue. Check your credentials." -ForegroundColor Blue
            } elseif ($outputString -match "already exists") {
                Write-Host ""
                Write-Host "[INFO] Release already exists. Use a different name or uninstall the existing release." -ForegroundColor Blue
            } elseif ($outputString -match "no such host|connection refused") {
                Write-Host ""
                Write-Host "[INFO] Network connectivity issue. Check registry URL and internet connection." -ForegroundColor Blue
            } elseif ($outputString -match "not found|404") {
                Write-Host ""
                Write-Host "[INFO] Chart not found. Check the repository URL and chart name." -ForegroundColor Blue
            }
            
            return $false
        }
    } catch {
        Write-Host "[ERROR] Exception occurred during installation" -ForegroundColor Red
        Write-Host "[INFO] Exception details:" -ForegroundColor Cyan
        Write-Host $_.Exception.Message -ForegroundColor Red
        if ($installOutput) {
            Write-Host "[INFO] Command output:" -ForegroundColor Cyan
            Write-Host $installOutput -ForegroundColor Red
        }
        return $false
    } finally {
        # Restore original error action preference
        $ErrorActionPreference = $originalErrorAction
    }
}

# Function to test if URL is accessible
function Test-UrlAccessible {
    param([string]$Url)
    
    try {
        Write-Host "[INFO] Testing URL accessibility: $Url" -ForegroundColor Cyan
        
        # Try using Invoke-WebRequest with HEAD request
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK] URL is accessible (HTTP $($response.StatusCode))" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[WARN] URL returned HTTP $($response.StatusCode)" -ForegroundColor Yellow
                return $false
            }
        } catch {
            # If HEAD request fails, try a simple GET request
            Write-Host "[INFO] HEAD request failed, trying GET request..." -ForegroundColor Gray
            try {
                $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
                if ($response.StatusCode -eq 200) {
                    Write-Host "[OK] URL is accessible (HTTP $($response.StatusCode))" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "[WARN] URL returned HTTP $($response.StatusCode)" -ForegroundColor Yellow
                    return $false
                }
            } catch {
                Write-Host "[WARN] HTTP request failed: $($_.Exception.Message)" -ForegroundColor Yellow
                
                # Final fallback: try a simple TCP connection test
                Write-Host "[INFO] Testing TCP connection..." -ForegroundColor Gray
                
                # Extract hostname and port from URL
                if ($Url -match "https?://([^:/]+)(:(\d+))?") {
                    $hostname = $matches[1]
                    $port = if ($matches[3]) { $matches[3] } else { if ($Url.StartsWith("https")) { 443 } else { 80 } }
                    
                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $connect = $tcpClient.BeginConnect($hostname, $port, $null, $null)
                        $wait = $connect.AsyncWaitHandle.WaitOne(10000, $false) # 10 second timeout
                        
                        if ($wait -and $tcpClient.Connected) {
                            $tcpClient.EndConnect($connect)
                            $tcpClient.Close()
                            Write-Host "[OK] TCP connection successful" -ForegroundColor Green
                            return $true
                        } else {
                            if ($tcpClient.Connected) {
                                $tcpClient.Close()
                            }
                            Write-Host "[WARN] TCP connection timeout or failed" -ForegroundColor Yellow
                            return $false
                        }
                    } catch {
                        Write-Host "[WARN] TCP connection failed: $($_.Exception.Message)" -ForegroundColor Yellow
                        return $false
                    } finally {
                        if ($tcpClient -and $tcpClient.Connected) {
                            $tcpClient.Close()
                        }
                    }
                } else {
                    Write-Host "[WARN] Could not parse URL for TCP test" -ForegroundColor Yellow
                    return $false
                }
            }
        }
    } catch {
        Write-Host "[WARN] Failed to test URL accessibility: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Function to expose SHO service
function Expose-ShoService {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    $serviceName = $ReleaseName
    $routeName = "${ReleaseName}-public"
    $port = 5050
    $maxAttempts = 30
    
    Write-Host "[INFO] Creating LoadBalancer for service $serviceName..." -ForegroundColor Cyan
    
    # Check if the source service exists
    try {
        kubectl get svc $serviceName -n $Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Service $serviceName does not exist in namespace $Namespace" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "[ERROR] Service $serviceName does not exist in namespace $Namespace" -ForegroundColor Red
        return $false
    }
    
    # Check if the LoadBalancer service already exists
    try {
        kubectl get svc $routeName -n $Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[INFO] LoadBalancer does not exist, creating it..." -ForegroundColor Yellow
            kubectl expose svc $serviceName --name=$routeName --type=LoadBalancer --port=$port --target-port=$port -n $Namespace
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[ERROR] Failed to create LoadBalancer service" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "[INFO] LoadBalancer service already exists" -ForegroundColor Blue
        }
    } catch {
        Write-Host "[INFO] LoadBalancer does not exist, creating it..." -ForegroundColor Yellow
        kubectl expose svc $serviceName --name=$routeName --type=LoadBalancer --port=$port --target-port=$port -n $Namespace
    }
    
    Write-Host "[INFO] Waiting for the LoadBalancer to become ready..." -ForegroundColor Yellow
    $attempts = 0
    
    while ($attempts -lt $maxAttempts) {
        try {
            # Try to get hostname first, then IP if hostname is not available
            $routeUrl = kubectl get svc $routeName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
            
            if (-not $routeUrl) {
                $routeUrl = kubectl get svc $routeName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
            
            if ($routeUrl) {
                $fullUrl = "http://${routeUrl}:$port"
                Write-Host "[OK] LoadBalancer is ready!" -ForegroundColor Green
                Write-Host "[INFO] The external URL for SHO is: $fullUrl" -ForegroundColor Green
                Write-Host ""
                Write-Host "[INFO] To access SHO later:" -ForegroundColor Cyan
                Write-Host "   $fullUrl" -ForegroundColor Gray
                Write-Host ""
                Write-Host "[INFO] To check status:" -ForegroundColor Cyan
                Write-Host "   kubectl get svc $routeName -n $Namespace" -ForegroundColor Gray
                Write-Host ""
                Write-Host "[INFO] To remove this LoadBalancer:" -ForegroundColor Cyan
                Write-Host "   kubectl delete svc $routeName -n $Namespace" -ForegroundColor Gray
                
                # Test URL accessibility before opening browser
                Write-Host ""
                Write-Host "[INFO] Checking if SHO console is responding..." -ForegroundColor Yellow
                
                # Wait a moment for the service to start responding
                Start-Sleep 20
                
                if (Test-UrlAccessible $fullUrl) {
                    Write-Host "[INFO] SHO console is responding! Opening browser..." -ForegroundColor Green
                    try {
                        Start-Process $fullUrl
                        Write-Host "[OK] Browser opened successfully" -ForegroundColor Green
                    } catch {
                        Write-Host "[WARN] Could not open browser automatically: $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "[INFO] Please open this URL manually:" -ForegroundColor Blue
                        Write-Host "   $fullUrl" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "[WARN] SHO console is not yet responding" -ForegroundColor Yellow
                    Write-Host "[INFO] The LoadBalancer is ready, but the application might still be starting up" -ForegroundColor Blue
                    Write-Host "[INFO] Please wait a few minutes and try accessing:" -ForegroundColor Blue
                    Write-Host "   $fullUrl" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "[INFO] You can check the pod status with:" -ForegroundColor Cyan
                    Write-Host "   kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Gray
                    Write-Host "   kubectl logs -n $Namespace -l app.kubernetes.io/instance=$ReleaseName --tail=20" -ForegroundColor Gray
                }
                
                return $true
            }
        } catch {
            # Continue waiting
        }
        
        Write-Host "   LoadBalancer not ready yet. Attempt $($attempts + 1)/$maxAttempts - waiting 10 seconds..." -ForegroundColor Yellow
        Start-Sleep 10
        $attempts++
    }
    
    Write-Host "[ERROR] LoadBalancer creation timed out after $($maxAttempts * 10) seconds" -ForegroundColor Red
    Write-Host "   This might be due to:" -ForegroundColor Yellow
    Write-Host "   - Your cloud provider is still provisioning the LoadBalancer" -ForegroundColor Yellow
    Write-Host "   - Quota limitations in your cloud account" -ForegroundColor Yellow
    Write-Host "   - Network policies blocking external access" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[INFO] Check status with:" -ForegroundColor Cyan
    Write-Host "   kubectl get svc $routeName -n $Namespace" -ForegroundColor Gray
    Write-Host "   kubectl describe svc $routeName -n $Namespace" -ForegroundColor Gray
    
    return $false
}

# Function to uninstall SHO
function Uninstall-Sho {
    param([string]$ReleaseName = "self-hosted-operator")
    
    $routeName = "${ReleaseName}-public"
    
    Write-Host "[WARN] WARNING: You are about to uninstall OutSystems Self-Hosted Operator" -ForegroundColor Red
    Write-Host "    This will remove the Helm release, LoadBalancer service, and the namespace" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Release: $ReleaseName" -ForegroundColor Gray
    Write-Host "    Namespace: $NAMESPACE" -ForegroundColor Gray
    Write-Host ""
    $confirm = Read-Host "[CONFIRM] Are you sure you want to proceed with uninstallation? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Host "[INFO] Uninstallation cancelled" -ForegroundColor Yellow
        return $true
    }
    
    Write-Host ""
    Write-Host "[INFO] Uninstalling OutSystems Self-Hosted Operator..." -ForegroundColor Yellow
    
    # Check if the release exists
    try {
        helm status $ReleaseName -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Release $ReleaseName not found in namespace $NAMESPACE" -ForegroundColor Red
            Write-Host "   To see installed releases, run: helm list --all-namespaces" -ForegroundColor Gray
            return $false
        }
    } catch {
        Write-Host "[ERROR] Release $ReleaseName not found in namespace $NAMESPACE" -ForegroundColor Red
        Write-Host "   To see installed releases, run: helm list --all-namespaces" -ForegroundColor Gray
        return $false
    }
    
    # Check for LoadBalancer service and remove it
    Write-Host "[INFO] Checking for LoadBalancer service..." -ForegroundColor Cyan
    try {
        kubectl get svc $routeName -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[INFO] Removing LoadBalancer service $routeName..." -ForegroundColor Yellow
            kubectl delete svc $routeName -n $NAMESPACE
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] LoadBalancer service successfully removed" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Failed to remove LoadBalancer service" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[INFO] No LoadBalancer service found" -ForegroundColor Blue
        }
    } catch {
        Write-Host "[INFO] No LoadBalancer service found" -ForegroundColor Blue
    }
    
    # Uninstall the Helm release
    Write-Host ""
    Write-Host "[INFO] Uninstalling SHO Helm release..." -ForegroundColor Yellow
    try {
        $uninstallOutput = helm uninstall $ReleaseName -n $NAMESPACE 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] SHO release $ReleaseName successfully uninstalled" -ForegroundColor Green

            $patchJson = '{"metadata":{"finalizers":null}}'
            $patchFile = "$env:TEMP\patch.json"
            Set-Content -Path $patchFile -Value $patchJson -Encoding UTF8

            try {
                $selfHostedRuntimes = kubectl get selfhostedruntimes -o name 2>$null
                if ($selfHostedRuntimes) {
                    foreach ($runtime in $selfHostedRuntimes) {
                        kubectl patch $runtime --type merge --patch-file "$patchFile" 2>$null
                    }
                }
            } catch {
                Write-Host "[WARN] Failed to patch selfhostedruntimes" -ForegroundColor Yellow
            }

            try {
                $selfHostedVaultOperators = kubectl get selfhostedvaultoperators -o name 2>$null
                if ($selfHostedVaultOperators) {
                    foreach ($operator in $selfHostedVaultOperators) {
                        kubectl patch $operator --type merge --patch-file "$patchFile" 2>$null
                    }
                }
            } catch {
                Write-Host "[WARN] Failed to patch selfhostedvaultoperators" -ForegroundColor Yellow
            }

            try {
                kubectl delete selfhostedruntime self-hosted-runtime --ignore-not-found=true 2>$null
            } catch {
                Write-Host "[WARN] Failed to delete selfhostedruntime" -ForegroundColor Yellow
            }
    
            
            # Patch and delete namespaces
            Write-Host "[INFO] Waiting for resources to cleanup..." -ForegroundColor Yellow
            Start-Sleep 30

            Write-Host "[INFO] Patching vault roles..." -ForegroundColor Yellow
            try {
                $vaultRoles = kubectl get vaultroles.self-hosted-vault-operator.outsystemscloud.com -o name 2>$null
                if ($vaultRoles) {
                    foreach ($role in $vaultRoles) {
                        kubectl patch $role --type merge --patch-file "$patchFile" 2>$null
                    }
                }
            } catch {
                Write-Host "[WARN] Failed to patch vault roles: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            Write-Host "[INFO] Patching finalizers in namespaces..." -ForegroundColor Yellow
            $namespacesToPatch = @(
                "flux-sdlc", "sh-registry", "vault", "istio-system", "outsystems-gloo-system", 
                "nats-auth", "flux-system", "outsystems-prometheus", "outsystems-rbac-manager", 
                "outsystems-stakater", "vault-operator", "seaweedfs"
            )
            
            foreach ($ns in $namespacesToPatch) {
                Write-Host "   Patching namespace: $ns" -ForegroundColor Gray
                try {
                    $resources = kubectl get helmcharts,helmreleases,kustomizations,helmrepositories -n $ns -o name 2>$null
                    if ($resources) {
                        foreach ($resource in $resources) {
                            kubectl patch $resource -n $ns --type merge --patch-file "$patchFile" 2>$null
                        }
                    }
                } catch {
                    Write-Host "[WARN] Failed to patch resources in namespace $ns" -ForegroundColor Yellow
                }
            }
            
            Start-Sleep 10
            
            Write-Host "[INFO] Cleaning up pods in specific namespaces..." -ForegroundColor Yellow
            $namespacesToClean = @(
                "flux-sdlc", "nats-auth", "sh-registry", "seaweedfs", "outsystems-otel", 
                "outsystems-fluentbit", "outsystems-prometheus", "nats-leaf", "authorization-services"
            )
            
            foreach ($ns in $namespacesToClean) {
                Write-Host "   Cleaning namespace: $ns" -ForegroundColor Gray
                try {
                    $pods = kubectl get pods -n $ns -o name 2>$null
                    if ($pods) {
                        foreach ($pod in $pods) {
                            kubectl delete $pod -n $ns --force
                        }
                    }
                } catch {
                    Write-Host "[WARN] Failed to clean pods in namespace $ns" -ForegroundColor Yellow
                }
            }

                        # Check for namespaces stuck in Terminating state and fix them
            Write-Host "[INFO] Checking for namespaces stuck in Terminating state..." -ForegroundColor Yellow
            try {
                $terminatingNamespaces = kubectl get namespaces --field-selector=status.phase=Terminating -o name 2>$null
                
                if ($terminatingNamespaces) {
                    Write-Host "[INFO] Found namespaces stuck in Terminating state:" -ForegroundColor Cyan
                    foreach ($ns in $terminatingNamespaces) {
                        $nsName = $ns -replace 'namespace/', ''
                        Write-Host "   - $nsName" -ForegroundColor Gray
                        
                        # Get the namespace details to see what's causing the issue
                        Write-Host "[INFO] Investigating namespace: $nsName" -ForegroundColor Yellow
                        
                        # Check for resources with finalizers in this namespace
                        try {
                            # Get all resources in the namespace that might have finalizers
                            $resourceTypes = @(
                                "pods", "services", "deployments", "replicasets", "configmaps", "secrets",
                                "persistentvolumeclaims", "persistentvolumes", "ingresses", "networkpolicies",
                                "helmreleases", "helmcharts", "kustomizations", "helmrepositories",
                                "serviceroles.auth.nats.outsystemscloud.com",
                                "vaultroles.self-hosted-vault-operator.outsystemscloud.com",
                                "selfhostedruntimes", "selfhostedvaultoperators"
                            )
                            
                            foreach ($resourceType in $resourceTypes) {
                                try {
                                    $resources = kubectl get $resourceType -n $nsName -o name 2>$null
                                    if ($resources) {
                                        Write-Host "   Found $resourceType resources in $nsName, patching finalizers..." -ForegroundColor Gray
                                        foreach ($resource in $resources) {
                                            kubectl patch $resource -n $nsName --type merge  --patch-file "$patchFile" 2>$null
                                        }
                                        
                                        # Force delete the resources
                                        kubectl delete $resourceType --all -n $nsName --force --grace-period=0 2>$null
                                    }
                                } catch {
                                    # Skip if resource type doesn't exist or other errors
                                    continue
                                }
                            }
                            
                            # Try to patch the namespace itself to remove finalizers
                            Write-Host "   Patching namespace finalizers for: $nsName" -ForegroundColor Gray
                            kubectl patch namespace $nsName --type merge  --patch-file "$patchFile" 2>$null
                            
                            # Also try to patch the spec.finalizers
                            kubectl patch namespace $nsName --type merge --patch-file "$patchFile" 2>$null
                            
                        } catch {
                            Write-Host "[WARN] Failed to patch resources in namespace $nsName" -ForegroundColor Yellow
                        }
                    }
                    
                    # Wait a bit and check again
                    Write-Host "[INFO] Waiting for namespace cleanup to complete..." -ForegroundColor Yellow
                    Start-Sleep 10
                    
                    # Check if any namespaces are still terminating
                    $stillTerminating = kubectl get namespaces --field-selector=status.phase=Terminating -o name 2>$null
                    if ($stillTerminating) {
                        Write-Host "[WARN] Some namespaces are still in Terminating state:" -ForegroundColor Yellow
                        foreach ($ns in $stillTerminating) {
                            $nsName = $ns -replace 'namespace/', ''
                            Write-Host "   - $nsName" -ForegroundColor Gray
                            
                            # Final attempt: use kubectl replace with empty finalizers
                            Write-Host "[INFO] Final attempt to force cleanup namespace: $nsName" -ForegroundColor Yellow
                            try {
                                # Get current namespace JSON and remove finalizers
                                $nsJson = kubectl get namespace $nsName -o json 2>$null | ConvertFrom-Json
                                if ($nsJson) {
                                    $nsJson.metadata.finalizers = @()
                                    $nsJson.spec.finalizers = @()
                                    
                                    # Convert back to JSON and apply
                                    $cleanJson = $nsJson | ConvertTo-Json -Depth 10 -Compress
                                    $tempFile = "$env:TEMP\ns-$nsName.json"
                                    $cleanJson | Out-File -FilePath $tempFile -Encoding UTF8
                                    
                                    kubectl replace --raw "/api/v1/namespaces/$nsName/finalize" -f $tempFile 2>$null
                                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                                }
                            } catch {
                                Write-Host "[WARN] Final cleanup attempt failed for namespace $nsName" -ForegroundColor Yellow
                            }
                        }
                    } else {
                        Write-Host "[OK] All previously terminating namespaces have been cleaned up" -ForegroundColor Green
                    }
                } else {
                    Write-Host "[OK] No namespaces stuck in Terminating state" -ForegroundColor Green
                }
            } catch {
                Write-Host "[WARN] Failed to check for terminating namespaces: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            Write-Host "[OK] Cleanup operations completed" -ForegroundColor Green

            Write-Host "[OK] Cleanup operations completed" -ForegroundColor Green
            
            Write-Host "[INFO] Deleting namespaces..." -ForegroundColor Yellow
            try {
                kubectl delete namespace $NAMESPACE --wait=false 2>$null
                kubectl delete namespace $NAMESPACE_CRED_JOB --wait=false 2>$null
                
                Write-Host "[OK] Namespace deletion initiated" -ForegroundColor Green
                Write-Host "   Note: Namespace deletion might take some time to complete" -ForegroundColor Gray
            } catch {
                Write-Host "[ERROR] Failed to delete namespace" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[ERROR] Failed to uninstall SHO release: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main execution
try {
    # Show help if requested
    if ($Help) {
        Show-Usage
        exit 0
    }
    
    # Check if LocalInstall is requested
    if ($LocalInstall) {
        Write-Host "[INFO] Local installation mode enabled - tools will be installed in current directory" -ForegroundColor Blue
    } else {
        # Check for administrator privileges first
        if (-not (Test-IsAdmin)) {
            Write-Host "[INFO] Checking if administrator privileges are needed..." -ForegroundColor Cyan
            # Only require admin if we need to install tools system-wide
            if (-not (Test-CommandExists "helm") -or -not (Test-CommandExists "kubectl")) {
                Write-Host "[INFO] Tools not found and no admin privileges. Using local installation..." -ForegroundColor Yellow
                $LocalInstall = $true
            }
        }
    }
    
    # Validate private repository access
    if ($PUBLIC_REPO -eq "false" -and -not $env:REGISTRY_USERNAME) {
        Write-Host "[ERROR] Private repository access requires REGISTRY_USERNAME and REGISTRY_PASSWORD environment variables" -ForegroundColor Red
        Write-Host ""
        Write-Host "Set credentials before running:" -ForegroundColor Yellow
        Write-Host "  `$env:REGISTRY_USERNAME='your-username'" -ForegroundColor Gray
        Write-Host "  `$env:REGISTRY_PASSWORD='your-password'" -ForegroundColor Gray
        Write-Host ""
        Show-Usage
        exit 1
    }
    
    # Show current configuration
    Write-Host "=== Configuration ===" -ForegroundColor White
    Write-Host "Repository URL: $CHART_REPO" -ForegroundColor Gray
    Write-Host "Version: $HELM_CHART_VERSION" -ForegroundColor Gray
    Write-Host "Public Access: $PUBLIC_REPO" -ForegroundColor Gray
    if ($env:REGISTRY_USERNAME) {
        Write-Host "Authentication: configured" -ForegroundColor Gray
    } else {
        Write-Host "Authentication: not configured" -ForegroundColor Gray
    }
    Write-Host ""
    
    if ($Uninstall) {
        Write-Host "[INFO] Uninstalling OutSystems Self-Hosted Operator..." -ForegroundColor Yellow
        if (-not (Uninstall-Sho $CHART_NAME)) {
            exit 1
        }
    } else {
        Write-Host "=== OutSystems Self-Hosted Operator Installation Dependencies Check ===" -ForegroundColor White
        
        if ($PUBLIC_REPO -ne "true") {
            if (-not (Invoke-RepoLogin)) {
                exit 1
            }
        }
        
        if (-not (Test-Dependencies)) {
            Write-Host ""
            Write-Host "[ERROR] Please resolve dependency issues before proceeding" -ForegroundColor Red
            Write-Host "[INFO] Run '.\install.ps1 -Help' for usage information" -ForegroundColor Blue
            exit 1
        }
        
        Write-Host ""
        Write-Host "[INFO] Ready to install SHO!" -ForegroundColor Green
        
        if (-not (Install-Sho)) {
            exit 1
        }
        
        if (-not (Expose-ShoService $CHART_NAME $NAMESPACE)) {
            Write-Host "[WARN] SHO installed but LoadBalancer setup failed" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "[SUCCESS] OutSystems Self-Hosted Operator was successfully installed!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Your OutSystems Self-Hosted environment is now ready for use." -ForegroundColor Cyan
        Write-Host "[INFO] Management Commands:" -ForegroundColor Yellow
        Write-Host "   helm status $CHART_NAME -n $NAMESPACE" -ForegroundColor Gray
        Write-Host "   kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=self-hosted-operator" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[INFO] To uninstall:" -ForegroundColor Yellow
        Write-Host "   .\install.ps1 -Uninstall" -ForegroundColor Gray
    }
} catch {
    Write-Host "[ERROR] An error occurred: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}