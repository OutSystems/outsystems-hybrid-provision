#Requires -Version 5.1

param(
    [string]$version = $null,
    [ValidateSet("prod", "non-prod")]
    [string]$env = "prod",
    [ValidateSet("install", "uninstall", "get-console-url")]
    [string]$operation = "install",
    [ValidateSet("true", "false")]
    [string]$use_acr = "false",  # Temporary backward compatibility for Azure ACR
    [Alias("UseAcr")]
    [switch]$UseAcr,
    [Alias("h")]
    [switch]$help
)

# Script Configuration
$Script:ScriptName = if ($MyInvocation.MyCommand.Definition) { 
    Split-Path -Leaf $MyInvocation.MyCommand.Definition 
} else { 
    "windows-installer.ps1" 
}
$Script:ScriptVersion = "1.0.0"

# Default Configuration
$Script:Namespace = "self-hosted-operator"
$Script:ChartName = "self-hosted-operator"
$Script:ImageName = "self-hosted-operator"

# Environment-specific settings
$Script:EcrAliasProd = "j0s5s8b0"    # GA ECR alias
$Script:EcrAliasNonProd = "g4u4y4x2" # Lab ECR alias
$Script:PubRegistry = "public.ecr.aws"

# Global variables
$Script:ShoVersion = $version
$Script:Env = $env
$Script:Op = $operation
$Script:UseAcr = if ($UseAcr) { "true" } elseif ($use_acr -eq "true") { "true" } else { "false" }

# Derived configuration
$Script:EcrAlias = ""
$Script:ChartRepository = ""
$Script:ImageRegistry = ""
$Script:ImageRepository = ""

# Console colors
$Script:Colors = @{
    Red    = [ConsoleColor]::Red
    Green  = [ConsoleColor]::Green
    Yellow = [ConsoleColor]::Yellow
    Blue   = [ConsoleColor]::Blue
    White  = [ConsoleColor]::White
}

# Logging functions
function Write-LogInfo {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Script:Colors.Blue
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Script:Colors.Green
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Script:Colors.Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor $Script:Colors.Red
}

function Write-LogStep {
    param([string]$Message)
    Write-Host "🔍 $Message" -ForegroundColor $Script:Colors.Blue
}

# Function to show usage
function Show-Usage {
    @"
$Script:ScriptName v$Script:ScriptVersion - OutSystems Self-Hosted Operator for Windows

USAGE:
    .\$Script:ScriptName [OPTIONS]

OPTIONS:
    --version=VERSION        SHO version to install/manage (default: latest)
    --env=ENVIRONMENT       Environment: prod, non-prod (default: prod)
    --operation=OPERATION   Operation: install, uninstall, get-console-url (default: install)
    --use-acr=BOOLEAN       Use ACR registry: true, false (default: false)
                           [TEMPORARY: Backward compatibility for Azure ACR]
    --help, -h              Show this help message

OPERATIONS:
    install                     Install OutSystems Self-Hosted Operator
    uninstall                  Uninstall OutSystems Self-Hosted Operator
    get-console-url            Get console URL for installed SHO

EXAMPLES:
    # Install latest version in prod environment
    .\$Script:ScriptName

    # Install specific version in non-prod environment
    .\$Script:ScriptName --operation=install --version=0.2.3 --env=non-prod
    
    # Alternative PowerShell syntax (also supported)
    .\$Script:ScriptName -operation install -version 0.2.3 -env non-prod

    # Get console URL for prod environment
    .\$Script:ScriptName --operation=get-console-url --env=prod

    # Uninstall from non-prod environment
    .\$Script:ScriptName --operation=uninstall --env=non-prod

"@
}

# Function to validate arguments
function Test-Arguments {
    Write-LogStep "Validating arguments..."
    
    # Validate version format if provided
    if ($Script:ShoVersion -and $Script:ShoVersion -ne "latest") {
        if ($Script:ShoVersion -notmatch '^\d+\.\d+\.\d+$') {
            Write-LogError "Invalid version format: '$Script:ShoVersion'. Expected format: x.y.z (e.g., 0.2.3)"
            return $false
        }
        Write-LogSuccess "Version '$Script:ShoVersion' format is valid"
    }
    
    # Validate ACR configuration if enabled
    if ($Script:UseAcr -eq "true") {
        if ($Script:Op -ne "install") {
            Write-LogError "-UseAcr flag is only applicable for install operation"
            return $false
        }
        
        Write-LogStep "Validating ACR configuration..."
        $missingVars = @()
        
        if (-not $env:SP_ID) {
            $missingVars += "SP_ID"
        }
        
        if (-not $env:SP_SECRET) {
            $missingVars += "SP_SECRET"
        }
        
        if (-not $env:SH_REGISTRY) {
            $missingVars += "SH_REGISTRY"
        }
        
        if ($missingVars.Count -gt 0) {
            Write-LogError "Missing required environment variables for ACR: $($missingVars -join ', ')"
            Write-LogInfo "Please set the following environment variables:"
            foreach ($var in $missingVars) {
                Write-LogInfo "  `$env:$var = '<value>'"
            }
            return $false
        }
        
        Write-LogSuccess "ACR configuration is valid"
    }
    
    Write-LogSuccess "Environment '$Script:Env' is valid"
    Write-LogSuccess "Operation '$Script:Op' is valid"
    
    return $true
}

# Function to setup environment-specific configuration
function Initialize-Environment {
    Write-LogStep "Setting up environment configuration for: $Script:Env"
    
    if ($Script:Env -eq "non-prod") {
        $Script:EcrAlias = $Script:EcrAliasNonProd
        Write-LogInfo "Using non-production ECR alias: $Script:EcrAlias"
    } else {
        $Script:EcrAlias = $Script:EcrAliasProd
        Write-LogInfo "Using production ECR alias: $Script:EcrAlias"
    }
    
    # Set repository URLs
    $Script:ChartRepository = "$Script:EcrAlias/lab/helm/self-hosted-operator"
    $Script:ImageRegistry = "$Script:EcrAlias/lab"
    $Script:ImageRepository = "$Script:EcrAlias/lab/$Script:ImageName"
    Write-LogInfo "Using ECR repository: $Script:PubRegistry/$Script:ChartRepository"
    
    Write-LogSuccess "Environment setup completed"
}

# Function to check if command exists
function Test-Command {
    param([string]$CommandName)
    return (Get-Command $CommandName -ErrorAction SilentlyContinue) -ne $null
}

# Function to install Chocolatey
function Install-Chocolatey {
    Write-LogStep "Installing Chocolatey package manager..."
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Test-Command "choco") {
            Write-LogSuccess "Chocolatey installed successfully"
            return $true
        } else {
            Write-LogError "Chocolatey installation verification failed"
            return $false
        }
    } catch {
        Write-LogError "Failed to install Chocolatey: $($_.Exception.Message)"
        return $false
    }
}

# Function to install package using Chocolatey
function Install-Package {
    param([string]$PackageName)
    
    Write-LogStep "Installing $PackageName..."
    
    if (-not (Test-Command "choco")) {
        Write-LogWarning "Chocolatey not found. Installing..."
        if (-not (Install-Chocolatey)) {
            return $false
        }
    }
    
    try {
        choco install $PackageName -y --no-progress
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "$PackageName installed successfully"
            return $true
        } else {
            Write-LogError "Failed to install $PackageName"
            return $false
        }
    } catch {
        Write-LogError "Failed to install $PackageName`: $($_.Exception.Message)"
        return $false
    }
}

# Function to install kubectl
function Install-Kubectl {
    Write-LogStep "Installing kubectl..."
    
    if (Test-Command "choco") {
        # Install via Chocolatey
        return Install-Package "kubernetes-cli"
    } else {
        # Manual installation
        Write-LogInfo "Installing kubectl via direct download..."
        
        try {
            # Get latest version
            $latestVersion = (Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt").Trim()
            $downloadUrl = "https://dl.k8s.io/release/$latestVersion/bin/windows/amd64/kubectl.exe"
            
            # Create directory if it doesn't exist
            $kubectlPath = "$env:ProgramFiles\kubectl"
            if (-not (Test-Path $kubectlPath)) {
                New-Item -ItemType Directory -Path $kubectlPath -Force | Out-Null
            }
            
            # Download kubectl
            $kubectlExe = "$kubectlPath\kubectl.exe"
            Write-LogInfo "Downloading kubectl $latestVersion..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $kubectlExe
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$kubectlPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$kubectlPath", "Machine")
                $env:PATH += ";$kubectlPath"
            }
            
            if (Test-Command "kubectl") {
                Write-LogSuccess "kubectl installed successfully"
                return $true
            } else {
                Write-LogError "kubectl installation verification failed"
                return $false
            }
        } catch {
            Write-LogError "Failed to install kubectl: $($_.Exception.Message)"
            return $false
        }
    }
}

# Function to install Helm
function Install-Helm {
    Write-LogStep "Installing Helm..."
    
    if (Test-Command "choco") {
        # Install via Chocolatey
        return Install-Package "kubernetes-helm"
    } else {
        # Manual installation
        Write-LogInfo "Installing Helm via direct download..."
        
        try {
            # Get latest Helm release
            $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/helm/helm/releases/latest"
            $version = $releaseInfo.tag_name
            $downloadUrl = "https://get.helm.sh/helm-$version-windows-amd64.zip"
            
            # Create directory if it doesn't exist
            $helmPath = "$env:ProgramFiles\helm"
            if (-not (Test-Path $helmPath)) {
                New-Item -ItemType Directory -Path $helmPath -Force | Out-Null
            }
            
            # Download and extract Helm
            $zipPath = "$env:TEMP\helm.zip"
            Write-LogInfo "Downloading Helm $version..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath
            
            Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\helm-extract" -Force
            Copy-Item "$env:TEMP\helm-extract\windows-amd64\helm.exe" -Destination "$helmPath\helm.exe" -Force
            
            # Cleanup
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\helm-extract" -Recurse -Force -ErrorAction SilentlyContinue
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$helmPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$helmPath", "Machine")
                $env:PATH += ";$helmPath"
            }
            
            if (Test-Command "helm") {
                Write-LogSuccess "Helm installed successfully"
                helm version --short
                return $true
            } else {
                Write-LogError "Helm installation verification failed"
                return $false
            }
        } catch {
            Write-LogError "Failed to install Helm: $($_.Exception.Message)"
            return $false
        }
    }
}

# Function to check dependencies
function Test-Dependencies {
    Write-LogStep "Checking dependencies for Windows..."
    $allDepsOk = $true
    
    # Check if running as Administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-LogWarning "Not running as Administrator. Some installations may require elevated privileges."
        Write-LogInfo "For best experience, run PowerShell as Administrator"
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-LogError "PowerShell 5.0 or higher is required. Current version: $($PSVersionTable.PSVersion)"
        $allDepsOk = $false
    } else {
        Write-LogSuccess "PowerShell version is sufficient: $($PSVersionTable.PSVersion)"
    }
    
    # Check kubectl
    if (-not (Test-Command "kubectl")) {
        Write-LogWarning "kubectl not found. Installing..."
        if (-not (Install-Kubectl)) {
            $allDepsOk = $false
        }
    } else {
        Write-LogSuccess "kubectl is installed"
    }
    
    # Check Helm
    if (-not (Test-Command "helm")) {
        Write-LogWarning "Helm not found. Installing..."
        if (-not (Install-Helm)) {
            $allDepsOk = $false
        }
    } else {
        Write-LogSuccess "Helm is installed"
        helm version --short
    }
    
    # Check Kubernetes connectivity
    Write-LogStep "Checking Kubernetes cluster connectivity..."
    try {
        $null = helm list --all-namespaces 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Connected to Kubernetes cluster"
        } else {
            Write-LogError "Cannot connect to Kubernetes cluster"
            Write-LogInfo "Make sure you have a valid kubeconfig and cluster access"
            $allDepsOk = $false
        }
    } catch {
        Write-LogError "Cannot connect to Kubernetes cluster"
        Write-LogInfo "Make sure you have a valid kubeconfig and cluster access"
        $allDepsOk = $false
    }
    
    if ($allDepsOk) {
        Write-LogSuccess "All dependencies are satisfied"
        return $true
    } else {
        Write-LogError "Some dependencies are missing or failed to install"
        return $false
    }
}

# Function to get latest SHO version
function Get-LatestShoVersion {
    Write-LogStep "Fetching latest SHO version..."
    
    try {
        # Get token from ECR public API
        $tokenUri = "https://$Script:PubRegistry/token?scope=repository:$Script:ImageRepository`:pull"
        $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method Get
        
        if (-not $tokenResponse.token) {
            Write-LogError "Failed to extract token from ECR response"
            return $false
        }
        
        # Get tags using the token
        $tagsUri = "https://$Script:PubRegistry/v2/$Script:ImageRepository/tags/list"
        $headers = @{ Authorization = "Bearer $($tokenResponse.token)" }
        $tagsResponse = Invoke-RestMethod -Uri $tagsUri -Headers $headers -Method Get
        
        if (-not $tagsResponse.tags) {
            Write-LogError "No tags found in ECR repository response"
            return $false
        }
        
        # Find latest version
        $versionTags = $tagsResponse.tags | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }
        if (-not $versionTags) {
            Write-LogError "Failed to find a valid image version from tags"
            Write-LogInfo "Available image version tags: $($tagsResponse.tags -join ', ')"
            return $false
        }
        
        # Sort versions and get the latest
        $latestImageVersion = $versionTags | Sort-Object { [version]($_ -replace '^v', '') } | Select-Object -Last 1
        $Script:ShoVersion = $latestImageVersion -replace '^v', ''
        
        Write-LogSuccess "Latest version found: $Script:ShoVersion"
        return $true
        
    } catch {
        Write-LogError "Failed to fetch latest SHO version: $($_.Exception.Message)"
        return $false
    }
}

# Function to install SHO
function Install-Sho {
    Write-LogStep "Installing OutSystems Self-Hosted Operator..."
    
    # Get version if not specified
    if (-not $Script:ShoVersion -or $Script:ShoVersion -eq "latest") {
        if (-not (Get-LatestShoVersion)) {
            Write-LogError "Failed to fetch latest SHO version"
            return $false
        }
    }
    
    Write-LogInfo "Installing SHO version: $Script:ShoVersion"
    Write-LogInfo "Environment: $Script:Env"
    Write-LogInfo "Namespace: $Script:Namespace"
    
    # Enable OCI mode for Helm
    $env:HELM_EXPERIMENTAL_OCI = "1"
    
    # Pull chart to temp directory
    $chartOci = "oci://$Script:PubRegistry/$Script:ChartRepository"
    $tmpDir = New-TemporaryDirectory
    
    try {
        Write-LogStep "Pulling chart from: $chartOci"
        helm pull $chartOci --version $Script:ShoVersion -d $tmpDir.FullName
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Failed to pull Helm chart"
            return $false
        }
        
        # Find chart file
        $chartFile = Get-ChildItem -Path $tmpDir.FullName -Filter "*.tgz" | Select-Object -First 1
        if (-not $chartFile) {
            Write-LogError "Could not find pulled chart package in $($tmpDir.FullName)"
            return $false
        }
        
        Write-LogSuccess "Chart package ready: $($chartFile.FullName)"
        
        # Install/upgrade chart
        Write-LogStep "Installing/upgrading SHO in namespace $Script:Namespace..."
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        
        $helmArgs = @(
            "upgrade", "--install", $Script:ChartName, $chartFile.FullName,
            "--namespace", $Script:Namespace,
            "--create-namespace",
            "--set", "image.registry=$Script:PubRegistry/$Script:ImageRegistry",
            "--set", "image.repository=$Script:ImageName",
            "--set", "image.tag=v$Script:ShoVersion",
            "--set-string", "podAnnotations.timestamp=$timestamp"
        )
        
        if ($Script:UseAcr -eq "true") {
            Write-LogInfo "Installing with ACR registry configuration"
            $helmArgs += @(
                "--set", "registry.url=$env:SH_REGISTRY",
                "--set", "registry.username=$env:SP_ID",
                "--set", "registry.password=$env:SP_SECRET",
                "--set", "enableECR.enabled=false"
            )
        }
        
        $installOutput = & helm $helmArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "OutSystems Self-Hosted Operator installed successfully!"
            Write-LogInfo "Installation details:"
            Write-Host $installOutput
            
            # Wait for pods to be ready
            if (Wait-ForPodsReady) {
                Write-LogSuccess "SHO is running successfully!"
                New-LoadBalancer
            } else {
                Write-LogWarning "Installation completed but pods are not ready yet"
                Show-TroubleshootingCommands
            }
            
            return $true
        } else {
            Write-LogError "Failed to install SHO"
            Write-LogInfo "Error details:"
            Write-Host $installOutput
            return $false
        }
        
    } finally {
        # Cleanup temp directory
        if (Test-Path $tmpDir.FullName) {
            Remove-Item $tmpDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Function to create temporary directory
function New-TemporaryDirectory {
    $tempPath = [System.IO.Path]::GetTempPath()
    $tempDir = [System.IO.Path]::GetRandomFileName()
    $fullPath = Join-Path $tempPath $tempDir
    New-Item -ItemType Directory -Path $fullPath
    return Get-Item $fullPath
}

# Function to wait for pods to be ready
function Wait-ForPodsReady {
    Write-LogStep "Waiting for SHO pods to be ready..."
    
    $maxWait = 300  # 5 minutes
    $checkInterval = 10
    $elapsed = 0
    
    while ($elapsed -lt $maxWait) {
        try {
            $podInfo = kubectl get pods -n $Script:Namespace -l "app.kubernetes.io/instance=$Script:ChartName" --no-headers -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" 2>$null
            
            if ($podInfo) {
                $runningPods = ($podInfo | Select-String "Running.*true").Count
                $totalPods = ($podInfo -split "`n").Count
                
                if ($runningPods -gt 0 -and $runningPods -eq $totalPods) {
                    Write-LogSuccess "All SHO pods are running and ready!"
                    return $true
                } elseif ($podInfo -match "Error|CrashLoopBackOff|ImagePullBackOff") {
                    Write-LogError "Pod(s) in error state detected!"
                    kubectl describe pods -n $Script:Namespace -l "app.kubernetes.io/instance=$Script:ChartName"
                    return $false
                } else {
                    Write-LogInfo "Pods still starting... ($runningPods/$totalPods ready) - waiting $checkInterval s..."
                }
            } else {
                Write-LogInfo "No pods found yet... ($elapsed s elapsed)"
            }
            
            Start-Sleep $checkInterval
            $elapsed += $checkInterval
        } catch {
            Write-LogInfo "Checking pod status... ($elapsed s elapsed)"
            Start-Sleep $checkInterval
            $elapsed += $checkInterval
        }
    }
    
    Write-LogWarning "Timeout reached while waiting for pods to be ready"
    return $false
}

# Function to create LoadBalancer service
function New-LoadBalancer {
    Write-LogStep "Creating LoadBalancer service..."
    
    $serviceName = $Script:ChartName
    $routeName = "$Script:ChartName-public"
    $port = 5050
    
    try {
        # Check if source service exists
        kubectl get svc $serviceName -n $Script:Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Service $serviceName does not exist in namespace $Script:Namespace"
            return $false
        }
        
        # Check if LoadBalancer service exists
        kubectl get svc $routeName -n $Script:Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-LogInfo "Creating LoadBalancer service..."
            kubectl expose svc $serviceName --name=$routeName --type=LoadBalancer --port=$port --target-port=$port -n $Script:Namespace
        } else {
            Write-LogInfo "LoadBalancer service already exists"
        }
        
        # Wait for LoadBalancer to get external IP
        Write-LogStep "Waiting for LoadBalancer to become ready..."
        $attempts = 0
        $maxAttempts = 30
        
        while ($attempts -lt $maxAttempts) {
            try {
                # Try to get hostname first, then IP
                $routeUrl = kubectl get svc $routeName -n $Script:Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
                
                if (-not $routeUrl) {
                    $routeUrl = kubectl get svc $routeName -n $Script:Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
                }
                
                if ($routeUrl) {
                    $fullUrl = "http://$routeUrl`:$port"
                    Write-LogSuccess "LoadBalancer is ready!"
                    Write-LogSuccess "SHO Console URL: $fullUrl"
                    
                    # Test URL accessibility
                    if (Test-UrlAccessible $fullUrl) {
                        Write-LogSuccess "SHO console is responding!"
                        Start-Process $fullUrl
                        Write-LogSuccess "Browser opened"
                    } else {
                        Write-LogWarning "SHO console is not yet responding"
                        Write-LogInfo "Please wait a few minutes and access: $fullUrl"
                    }
                    
                    return $true
                }
                
                Write-LogInfo "LoadBalancer not ready yet. Attempt $(($attempts + 1))/$maxAttempts - waiting 10s..."
                Start-Sleep 10
                $attempts++
            } catch {
                Write-LogInfo "LoadBalancer not ready yet. Attempt $(($attempts + 1))/$maxAttempts - waiting 10s..."
                Start-Sleep 10
                $attempts++
            }
        }
        
        Write-LogError "LoadBalancer creation timed out"
        return $false
        
    } catch {
        Write-LogError "Failed to create LoadBalancer: $($_.Exception.Message)"
        return $false
    }
}

# Function to test URL accessibility
function Test-UrlAccessible {
    param([string]$Url)
    
    $maxTries = 5
    $try = 1
    
    while ($try -le $maxTries) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            $try++
            if ($try -le $maxTries) {
                Start-Sleep 5
            }
        }
    }
    return $false
}

# Function to uninstall SHO
function Uninstall-Sho {
    Write-LogStep "Uninstalling OutSystems Self-Hosted Operator..."
    
    $routeName = "$Script:ChartName-public"
    
    Write-Host ""
    Write-LogWarning "WARNING: You are about to uninstall OutSystems Self-Hosted Operator"
    Write-LogInfo "This will remove the Helm release and LoadBalancer service"
    Write-LogInfo "Release: $Script:ChartName"
    Write-LogInfo "Namespace: $Script:Namespace"
    Write-Host ""
    
    $confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-LogInfo "Uninstallation cancelled"
        return $true
    }
    
    # Check if release exists
    helm status $Script:ChartName -n $Script:Namespace 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Release $Script:ChartName not found in namespace $Script:Namespace"
        return $false
    }
    
    # Remove LoadBalancer service
    kubectl get svc $routeName -n $Script:Namespace 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-LogStep "Removing LoadBalancer service..."
        kubectl delete svc $routeName -n $Script:Namespace
    }
    
    # Clean up resources
    Write-LogStep "Cleaning up resources..."
    kubectl get selfhostedruntimes -o name 2>$null | ForEach-Object { kubectl patch $_ --type merge -p '{\"metadata\":{\"finalizers\":null}}' } 2>$null
    kubectl get selfhostedvaultoperators -o name 2>$null | ForEach-Object { kubectl patch $_ --type merge -p '{\"metadata\":{\"finalizers\":null}}' } 2>$null
    kubectl delete selfhostedruntime --ignore-not-found self-hosted-runtime 2>$null
    
    # Uninstall Helm release
    Write-LogStep "Uninstalling Helm release..."
    helm uninstall $Script:ChartName -n $Script:Namespace
    
    if ($LASTEXITCODE -eq 0) {
        Write-LogSuccess "SHO release uninstalled successfully"
        
        # Optional: Delete namespace
        $deleteNs = Read-Host "Do you want to delete the namespace '$Script:Namespace'? (yes/no)"
        if ($deleteNs -eq "yes") {
            kubectl delete namespace $Script:Namespace --wait=false 2>$null
            Write-LogInfo "Namespace deletion initiated"
        }
        
        Write-LogSuccess "OutSystems Self-Hosted Operator uninstalled successfully!"
        return $true
    } else {
        Write-LogError "Failed to uninstall SHO release"
        return $false
    }
}

# Function to get console URL
function Get-ConsoleUrl {
    Write-LogStep "Getting console URL for OutSystems Self-Hosted Operator..."
    
    # Check if SHO is installed
    helm status $Script:ChartName -n $Script:Namespace 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "OutSystems Self-Hosted Operator is not installed"
        Write-LogInfo "Please install it first using: .\$Script:ScriptName -Operation install"
        return $false
    }
    
    $routeName = "$Script:ChartName-public"
    $port = 5050
    
    # Check if LoadBalancer service exists
    kubectl get svc $routeName -n $Script:Namespace 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-LogWarning "LoadBalancer service not found. Creating it..."
        return New-LoadBalancer
    }
    
    # Get LoadBalancer URL
    try {
        $routeUrl = kubectl get svc $routeName -n $Script:Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        
        if (-not $routeUrl) {
            $routeUrl = kubectl get svc $routeName -n $Script:Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        }
        
        if ($routeUrl) {
            $fullUrl = "http://$routeUrl`:$port"
            Write-LogSuccess "Console URL: $fullUrl"
            
            if (Test-UrlAccessible $fullUrl) {
                Write-LogSuccess "Console is responding!"
                Start-Process $fullUrl
                Write-LogSuccess "Browser opened"
            } else {
                Write-LogWarning "Console is not yet responding"
                Write-LogInfo "Please wait a few minutes and try again"
            }
            
            return $true
        } else {
            Write-LogError "LoadBalancer URL not found"
            Write-LogInfo "LoadBalancer might still be provisioning. Please wait and try again."
            return $false
        }
    } catch {
        Write-LogError "Failed to get console URL: $($_.Exception.Message)"
        return $false
    }
}

# Function to show troubleshooting commands
function Show-TroubleshootingCommands {
    @"

🛠️  Troubleshooting Commands:

📊 Check pod status:
   kubectl get pods -n $Script:Namespace -l app.kubernetes.io/instance=$Script:ChartName

📋 Describe pods:
   kubectl describe pods -n $Script:Namespace -l app.kubernetes.io/instance=$Script:ChartName

📝 View pod logs:
   kubectl logs -n $Script:Namespace -l app.kubernetes.io/instance=$Script:ChartName --tail=50

📋 Check events:
   kubectl get events -n $Script:Namespace --sort-by=.metadata.creationTimestamp

⚡ Check helm status:
   helm status $Script:ChartName -n $Script:Namespace

🔄 Restart deployment:
   kubectl rollout restart deployment -n $Script:Namespace -l app.kubernetes.io/instance=$Script:ChartName

"@
}

# Function to show configuration summary
function Show-Configuration {
    @"

=== Configuration Summary ===
Script Version: $Script:ScriptVersion
Platform:       Windows
Operation:      $Script:Op
Environment:    $Script:Env
Version:        $(if ($Script:ShoVersion) { $Script:ShoVersion } else { "latest" })
Use ACR:        $Script:UseAcr
Namespace:      $Script:Namespace
Chart Name:     $Script:ChartName
Repository:     $Script:PubRegistry/$Script:ChartRepository
Image Registry: $Script:PubRegistry/$Script:ImageRegistry

"@
}

# Main execution
function Main {
    Write-Host "🪟 OutSystems Self-Hosted Operator Windows Installer v$Script:ScriptVersion" -ForegroundColor $Script:Colors.Blue
    Write-Host ""
    
    # Show help if requested
    if ($help) {
        Show-Usage
        exit 0
    }
    
    # Validate arguments
    if (-not (Test-Arguments)) {
        exit 1
    }
    
    # Setup environment
    Initialize-Environment
    
    # Show configuration
    Show-Configuration
    
    # Check dependencies
    if (-not (Test-Dependencies)) {
        Write-LogError "Dependency check failed. Please resolve issues and try again."
        exit 1
    }
    
    # Execute operation
    $success = $false
    switch ($Script:Op) {
        "install" {
            $success = Install-Sho
        }
        "uninstall" {
            $success = Uninstall-Sho
        }
        "get-console-url" {
            $success = Get-ConsoleUrl
        }
        default {
            Write-LogError "Unknown operation: $Script:Op"
            exit 1
        }
    }
    
    if ($success) {
        Write-LogSuccess "Operation '$Script:Op' completed successfully!"
        exit 0
    } else {
        Write-LogError "Operation '$Script:Op' failed"
        exit 1
    }
}

# Run main function
Main
