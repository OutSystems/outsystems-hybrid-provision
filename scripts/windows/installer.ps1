#!/usr/bin/env powershell

param(
    [string]$Version,
    [string]$Repository,
    [string]$Env,
    [switch]$Uninstall,
    [switch]$GetConsoleUrl,
    [switch]$Help
)

# Exit on errors
$ErrorActionPreference = "Stop"

# Configuration
$NAMESPACE = "self-hosted-operator"
$NAMESPACE_CRED_JOB = "self-hosted-registry-credentials-job"

$CHART_NAME = "self-hosted-operator"
# TODO: Update with ga ecr repo when available
$HELM_REPO_URL = if ($env:HELM_REPO_URL) { $env:HELM_REPO_URL } else { "oci://public.ecr.aws/g4u4y4x2/lab/helm" }
$CHART_REPO = "$HELM_REPO_URL/$CHART_NAME"
$IMAGE_REGISTRY = if ($env:IMAGE_REGISTRY) { $env:IMAGE_REGISTRY } else { "public.ecr.aws/g4u4y4x2" }
$IMAGE_REPOSITORY = "self-hosted-operator"
$REPO = "g4u4y4x2/lab/helm/self-hosted-operator"

$SH_REGISTRY = if ($env:SH_REGISTRY) { $env:SH_REGISTRY } else { "" }

# Setup environment configs
if ($Env -eq "non-prod") {
    Write-Host "🔧 Setting environment to non production" -ForegroundColor Yellow
    # TODO: Update with ga ecr repo when available
    $HELM_REPO_URL = if ($env:HELM_REPO_URL) { $env:HELM_REPO_URL } else { "oci://public.ecr.aws/g4u4y4x2/lab/helm" }
    $CHART_REPO = "$HELM_REPO_URL/$CHART_NAME"
    $IMAGE_REGISTRY = if ($env:IMAGE_REGISTRY) { $env:IMAGE_REGISTRY } else { "public.ecr.aws/g4u4y4x2" }
}

# Function to check if Helm is installed
function Test-HelmInstalled {
    try {
        $version = helm version --short 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Helm is already installed" -ForegroundColor Green
            Write-Host $version
            return $true
        }
    }
    catch {
        Write-Host "❌ Helm is not installed" -ForegroundColor Red
        return $false
    }
    return $false
}

# Function to install Helm on Windows
function Install-Helm {
    Write-Host "🚀 Installing Helm..." -ForegroundColor Blue
    
    # Check if Chocolatey is available
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing Helm via Chocolatey..." -ForegroundColor Blue
        try {
            choco install kubernetes-helm -y
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Helm installed successfully via Chocolatey" -ForegroundColor Green
                helm version --short
                return $true
            }
            else {
                Write-Host "❌ Failed to install Helm via Chocolatey" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install Helm via Chocolatey" -ForegroundColor Red
            return $false
        }
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing Helm via winget..." -ForegroundColor Blue
        try {
            winget install Helm.Helm
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Helm installed successfully via winget" -ForegroundColor Green
                helm version --short
                return $true
            }
            else {
                Write-Host "❌ Failed to install Helm via winget" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install Helm via winget" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "📦 Package manager not found. Installing Helm via direct download..." -ForegroundColor Blue
        
        try {
            # Get the latest Helm version
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/helm/helm/releases/latest"
            $version = $latestRelease.tag_name
            $downloadUrl = "https://get.helm.sh/helm-$version-windows-amd64.zip"
            
            Write-Host "📥 Downloading Helm $version..." -ForegroundColor Blue
            
            $tempPath = "$env:TEMP\helm.zip"
            $extractPath = "$env:TEMP\helm"
            
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath
            
            # Extract the zip file
            Expand-Archive -Path $tempPath -DestinationPath $extractPath -Force
            
            # Find the helm.exe file
            $helmExe = Get-ChildItem -Path $extractPath -Recurse -Name "helm.exe" | Select-Object -First 1
            $helmExePath = Join-Path $extractPath $helmExe
            
            # Create a directory in Program Files if it doesn't exist
            $installPath = "$env:ProgramFiles\Helm"
            if (!(Test-Path $installPath)) {
                New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            }
            
            # Copy helm.exe to the install directory
            Copy-Item -Path $helmExePath -Destination "$installPath\helm.exe" -Force
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$installPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installPath", "Machine")
                $env:PATH = "$env:PATH;$installPath"
            }
            
            # Clean up
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
            
            # Verify installation
            if (Test-Path "$installPath\helm.exe") {
                Write-Host "✅ Helm installed successfully to $installPath" -ForegroundColor Green
                & "$installPath\helm.exe" version --short
                return $true
            }
            else {
                Write-Host "❌ Helm installation verification failed" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install Helm via direct download: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
}

# Function to ensure Helm is installed
function Confirm-HelmInstalled {
    Write-Host "🔍 Checking Helm installation..." -ForegroundColor Blue
    
    if (Test-HelmInstalled) {
        return $true
    }
    else {
        Write-Host "🔧 Helm not found. Proceeding with installation..." -ForegroundColor Yellow
        return Install-Helm
    }
}

# Function to install AWS CLI on Windows
function Install-AwsCli {
    Write-Host "🚀 Installing AWS CLI..." -ForegroundColor Blue
    
    # Check if Chocolatey is available
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing AWS CLI via Chocolatey..." -ForegroundColor Blue
        try {
            choco install awscli -y
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ AWS CLI installed successfully via Chocolatey" -ForegroundColor Green
                aws --version
                return $true
            }
            else {
                Write-Host "❌ Failed to install AWS CLI via Chocolatey" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install AWS CLI via Chocolatey" -ForegroundColor Red
            return $false
        }
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing AWS CLI via winget..." -ForegroundColor Blue
        try {
            winget install Amazon.AWSCLI
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ AWS CLI installed successfully via winget" -ForegroundColor Green
                aws --version
                return $true
            }
            else {
                Write-Host "❌ Failed to install AWS CLI via winget" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install AWS CLI via winget" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "📦 Package manager not found. Installing AWS CLI via MSI installer..." -ForegroundColor Blue
        
        try {
            $downloadUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
            $tempPath = "$env:TEMP\AWSCLIV2.msi"
            
            Write-Host "📥 Downloading AWS CLI installer..." -ForegroundColor Blue
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath
            
            Write-Host "📦 Installing AWS CLI..." -ForegroundColor Blue
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $tempPath, "/quiet" -Wait
            
            # Clean up
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            
            # Verify installation
            if (Get-Command aws -ErrorAction SilentlyContinue) {
                Write-Host "✅ AWS CLI installed successfully" -ForegroundColor Green
                aws --version
                return $true
            }
            else {
                Write-Host "❌ AWS CLI installation verification failed" -ForegroundColor Red
                Write-Host "💡 You may need to restart your PowerShell session or reboot" -ForegroundColor Yellow
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install AWS CLI via MSI installer: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
}

# Function to ensure AWS CLI is installed
function Confirm-AwsCliInstalled {
    Write-Host "🔍 Checking AWS CLI installation..." -ForegroundColor Blue
    
    if (Get-Command aws -ErrorAction SilentlyContinue) {
        Write-Host "✅ AWS CLI is already installed" -ForegroundColor Green
        aws --version
        return $true
    }
    else {
        Write-Host "🔧 AWS CLI not found. Proceeding with installation..." -ForegroundColor Yellow
        return Install-AwsCli
    }
}

# Function to check all dependencies required for helm chart installation
function Test-Dependencies {
    $allDepsOk = $true
    
    # Check AWS CLI (required for ECR authentication)
    Write-Host "📋 Checking AWS CLI..." -ForegroundColor Blue
    if (!(Confirm-AwsCliInstalled)) {
        Write-Host "❌ Failed to ensure AWS CLI is available" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    # Check jq (PowerShell has built-in JSON support, but we'll check for jq for compatibility)
    Write-Host "📋 Checking JSON parsing capabilities..." -ForegroundColor Blue
    if (!(Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️  jq is not installed, but PowerShell has built-in JSON parsing" -ForegroundColor Yellow
        Write-Host "✅ JSON parsing capabilities available" -ForegroundColor Green
    }
    else {
        Write-Host "✅ jq is already installed" -ForegroundColor Green
    }
    
    # Check Helm
    Write-Host "📋 Checking Helm..." -ForegroundColor Blue
    if (!(Confirm-HelmInstalled)) {
        Write-Host "❌ Failed to ensure Helm is available" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    # Check kubectl
    Write-Host "📋 Checking kubectl..." -ForegroundColor Blue
    if (!(Confirm-KubectlInstalled)) {
        Write-Host "❌ Failed to ensure kubectl is available" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    # Check Kubernetes cluster connectivity using Helm
    Write-Host "📋 Checking Kubernetes cluster connectivity via Helm..." -ForegroundColor Blue
    try {
        helm list --all-namespaces 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Helm can connect to Kubernetes cluster" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Helm cannot connect to Kubernetes cluster" -ForegroundColor Red
            Write-Host "   Make sure you have:" -ForegroundColor Yellow
            Write-Host "   - A valid kubeconfig file" -ForegroundColor Yellow
            Write-Host "   - Access to a Kubernetes cluster" -ForegroundColor Yellow
            Write-Host "   - Proper cluster permissions" -ForegroundColor Yellow
            $allDepsOk = $false
        }
    }
    catch {
        Write-Host "❌ Helm cannot connect to Kubernetes cluster" -ForegroundColor Red
        $allDepsOk = $false
    }
    
    if ($allDepsOk) {
        Write-Host "🎉 All required dependencies are satisfied!" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "💥 Some dependencies are missing or failed to install" -ForegroundColor Red
        return $false
    }
}

# Function to identify Kubernetes cluster type and set appropriate options
function Get-ClusterType {
    Write-Host "🔍 Identifying cluster type..." -ForegroundColor Blue
    
    try {
        # Determine cluster type based on node labels
        $nodeLabels = kubectl get nodes --output=jsonpath='{.items[0].metadata.labels}' 2>$null
        
        if ($nodeLabels -match 'openshift') {
            $script:CLUSTER_TYPE = "ocp"
        }
        elseif ($nodeLabels -match 'azure') {
            $script:CLUSTER_TYPE = "azure"
        }
        elseif ($nodeLabels -match 'eks.amazonaws.com') {
            $script:CLUSTER_TYPE = "aws"
        }
        else {
            $script:CLUSTER_TYPE = "unknown"
        }

        Write-Host "✅ Cluster type identified: $script:CLUSTER_TYPE" -ForegroundColor Green

        # Set Helm flags based on cluster type
        if ($script:CLUSTER_TYPE -eq "openshift") {
            Write-Host "🔧 Setting OpenShift specific options" -ForegroundColor Yellow
            Write-Host "   - Using SCC (Security Context Constraints)" -ForegroundColor Yellow
            $script:SCC_CREATION = "true"
        }
        else {
            $script:SCC_CREATION = "false"
        }
    }
    catch {
        Write-Host "⚠️  Could not identify cluster type: $($_.Exception.Message)" -ForegroundColor Yellow
        $script:CLUSTER_TYPE = "unknown"
        $script:SCC_CREATION = "false"
    }
}

# Get latest self-hosted operator version
function Get-LatestShoVersion {
    Write-Host "🔍 Fetching latest OutSystems Self-Hosted Operator version..." -ForegroundColor Blue
    
    try {
        # Use the same token method as the ECR authentication
        $tokenResponse = Invoke-RestMethod -Uri "https://public.ecr.aws/token?scope=repository:${REPO}:pull" -Method Get
        
        if (!$tokenResponse -or !$tokenResponse.token) {
            Write-Host "❌ Failed to get token from ECR public API" -ForegroundColor Red
            return $false
        }
        
        $token = $tokenResponse.token
        
        # Get tags using the token
        $headers = @{
            "Authorization" = "Bearer $token"
        }
        
        $tagsResponse = Invoke-RestMethod -Uri "https://public.ecr.aws/v2/${REPO}/tags/list" -Headers $headers -Method Get
        
        if (!$tagsResponse -or !$tagsResponse.tags) {
            Write-Host "❌ Failed to fetch tags from ECR repository" -ForegroundColor Red
            return $false
        }
        
        $tags = $tagsResponse.tags
        
        if ($tags.Count -eq 0) {
            Write-Host "❌ No tags found in ECR repository response" -ForegroundColor Red
            return $false
        }
        
        # Filter for semantic version tags and sort
        $versionTags = $tags | Where-Object { $_ -match '^[0-9]+\.[0-9]+\.[0-9]+$' } | Sort-Object { [Version]$_ }
        
        if ($versionTags.Count -eq 0) {
            Write-Host "❌ Failed to find a valid version from tags" -ForegroundColor Red
            Write-Host "Available tags: $($tags -join ', ')" -ForegroundColor Yellow
            return $false
        }
        
        $latestVersion = $versionTags[-1]
        
        Write-Host "✅ Latest version found: $latestVersion" -ForegroundColor Green
        $script:HELM_CHART_VERSION = $latestVersion
        return $true
    }
    catch {
        Write-Host "❌ Failed to fetch latest version: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to authenticate with ECR public registry using AWS CLI
function Connect-EcrHelmLogin {
    Write-Host "🔐 Setting up ECR public registry access for Helm..." -ForegroundColor Blue
    
    # Check if AWS CLI is available
    if (!(Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "❌ AWS CLI is not installed or not available in PATH" -ForegroundColor Red
        Write-Host "💡 Please ensure AWS CLI is installed by running the dependency check" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "🔑 Using AWS CLI for ECR public authentication..." -ForegroundColor Blue
    
    try {
        # Test if AWS CLI can get the login password
        $awsPassword = aws ecr-public get-login-password --region us-east-1 2>$null
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($awsPassword)) {
            Write-Host "❌ AWS CLI failed to get authentication token" -ForegroundColor Red
            Write-Host "💡 This could be due to:" -ForegroundColor Yellow
            Write-Host "   - AWS CLI not configured (run 'aws configure')" -ForegroundColor Yellow
            Write-Host "   - No AWS credentials available" -ForegroundColor Yellow
            Write-Host "   - Network connectivity issues" -ForegroundColor Yellow
            Write-Host "   - Insufficient permissions" -ForegroundColor Yellow
            Write-Host "" 
            Write-Host "🔧 To configure AWS CLI:" -ForegroundColor Blue
            Write-Host "   aws configure" -ForegroundColor Cyan
            Write-Host "   # You can use any valid AWS credentials" -ForegroundColor Gray
            Write-Host "   # Access Key ID: (your access key)" -ForegroundColor Gray
            Write-Host "   # Secret Access Key: (your secret key)" -ForegroundColor Gray
            Write-Host "   # Default region: us-east-1" -ForegroundColor Gray
            Write-Host "   # Default output format: json" -ForegroundColor Gray
            return $false
        }
        
        Write-Host "✅ AWS CLI authentication token obtained" -ForegroundColor Green
        
        # Use the AWS CLI generated password with Helm
        $awsPassword | helm registry login --username AWS --password-stdin public.ecr.aws 2>$null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Helm registry authentication successful" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "❌ Helm registry login failed" -ForegroundColor Red
            Write-Host "💡 This could be due to:" -ForegroundColor Yellow
            Write-Host "   - Network connectivity issues" -ForegroundColor Yellow
            Write-Host "   - Helm version compatibility" -ForegroundColor Yellow
            Write-Host "   - Registry authentication problems" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ ECR authentication failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to install kubectl on Windows
function Install-Kubectl {
    Write-Host "🚀 Installing kubectl..." -ForegroundColor Blue
    
    # Check if Chocolatey is available
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing kubectl via Chocolatey..." -ForegroundColor Blue
        try {
            choco install kubernetes-cli -y
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ kubectl installed successfully via Chocolatey" -ForegroundColor Green
                kubectl version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
                return $true
            }
            else {
                Write-Host "❌ Failed to install kubectl via Chocolatey" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install kubectl via Chocolatey" -ForegroundColor Red
            return $false
        }
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "📦 Installing kubectl via winget..." -ForegroundColor Blue
        try {
            winget install Kubernetes.kubectl
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ kubectl installed successfully via winget" -ForegroundColor Green
                kubectl version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
                return $true
            }
            else {
                Write-Host "❌ Failed to install kubectl via winget" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install kubectl via winget" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "📦 Package manager not found. Installing kubectl via direct download..." -ForegroundColor Blue
        
        try {
            # Get the latest stable version
            $kubectlVersion = Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt"
            
            if ([string]::IsNullOrEmpty($kubectlVersion)) {
                Write-Host "❌ Failed to get kubectl version" -ForegroundColor Red
                return $false
            }
            
            Write-Host "📥 Downloading kubectl $kubectlVersion..." -ForegroundColor Blue
            
            # Download kubectl binary for Windows
            $downloadUrl = "https://dl.k8s.io/release/$kubectlVersion/bin/windows/amd64/kubectl.exe"
            $installPath = "$env:ProgramFiles\kubectl"
            $kubectlExe = "$installPath\kubectl.exe"
            
            # Create directory if it doesn't exist
            if (!(Test-Path $installPath)) {
                New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            }
            
            Invoke-WebRequest -Uri $downloadUrl -OutFile $kubectlExe
            
            Write-Host "✅ kubectl downloaded successfully" -ForegroundColor Green
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$installPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$installPath", "Machine")
                $env:PATH = "$env:PATH;$installPath"
                Write-Host "✅ kubectl installed to $installPath" -ForegroundColor Green
                Write-Host "ℹ️  Added $installPath to PATH" -ForegroundColor Blue
            }
            else {
                Write-Host "✅ kubectl installed to $installPath" -ForegroundColor Green
            }
            
            # Verify installation
            if (Test-Path $kubectlExe) {
                Write-Host "✅ kubectl installed successfully" -ForegroundColor Green
                & $kubectlExe version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
                return $true
            }
            else {
                Write-Host "❌ kubectl installation verification failed" -ForegroundColor Red
                return $false
            }
        }
        catch {
            Write-Host "❌ Failed to install kubectl: $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }
}

# Function to ensure kubectl is installed
function Confirm-KubectlInstalled {
    Write-Host "🔍 Checking kubectl installation..." -ForegroundColor Blue
    
    if (Get-Command kubectl -ErrorAction SilentlyContinue) {
        Write-Host "✅ kubectl is already installed" -ForegroundColor Green
        kubectl version --client --output=yaml 2>$null | Select-String "gitVersion" | Select-Object -First 1
        return $true
    }
    else {
        Write-Host "🔧 kubectl not found. Proceeding with installation..." -ForegroundColor Yellow
        return Install-Kubectl
    }
}

# Function to show usage
function Show-Usage {
    Write-Host "Usage: .\installer.ps1 [OPTIONS]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor White
    Write-Host "  -Version VERSION         The SHO chart version to install (optional, defaults to latest)" -ForegroundColor Cyan
    Write-Host "  -Repository REPO_URL     The SHO registry URL (optional, uses default if not specified)" -ForegroundColor Cyan
    Write-Host "  -Uninstall              Uninstall OutSystems Self-Hosted Operator" -ForegroundColor Cyan
    Write-Host "  -Env ENVIRONMENT        Set the environment (non-prod, prod, etc.)" -ForegroundColor Cyan
    Write-Host "  -GetConsoleUrl          Get the console URL for the installed SHO" -ForegroundColor Cyan
    Write-Host "  -Help                   Show this help message" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\installer.ps1" -ForegroundColor Gray
    Write-Host "  .\installer.ps1 -Version 1.2.3" -ForegroundColor Gray
    Write-Host "  .\installer.ps1 -Repository registry.example.com" -ForegroundColor Gray
    Write-Host "  .\installer.ps1 -Version 1.2.3 -Repository registry.example.com" -ForegroundColor Gray
    Write-Host "  .\installer.ps1 -Env non-prod -GetConsoleUrl" -ForegroundColor Gray
}

# Function to install OutSystems Self-Hosted Operator
function Install-Sho {
    Write-Host "🚀 Installing OutSystems Self-Hosted Operator..." -ForegroundColor Blue
    
    # Authenticate with ECR public registry
    if (!(Connect-EcrHelmLogin)) {
        Write-Host "❌ Failed to authenticate with ECR public registry" -ForegroundColor Red
        return $false
    }
    
    # Prepare the chart URL
    if ($script:HELM_CHART_VERSION -ne "latest") {
        $script:CHART_REPO = "$script:CHART_REPO`:$script:HELM_CHART_VERSION"
        $script:IMAGE_VERSION = "v$script:HELM_CHART_VERSION"
    }

    Write-Host "📦 Installing SHO chart from: $script:CHART_REPO" -ForegroundColor Blue
    
    $releaseName = "self-hosted-operator"
    
    # Create namespaces
    kubectl create namespace $NAMESPACE 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Namespace $NAMESPACE already exists, skipping creation" -ForegroundColor Yellow
    }
    
    kubectl create namespace $NAMESPACE_CRED_JOB 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Namespace $NAMESPACE_CRED_JOB already exists, skipping creation" -ForegroundColor Yellow
    }
    
    Write-Host "🔧 Running Helm install command..." -ForegroundColor Blue
    Write-Host "🚀 Deploying with platform: $script:CLUSTER_TYPE" -ForegroundColor Blue
    
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    
    # Build Helm command arguments
    $helmArgs = @(
        "upgrade", "--install", $releaseName, $script:CHART_REPO,
        "--namespace", $NAMESPACE,
        "--create-namespace",
        "--set", "image.registry=$IMAGE_REGISTRY",
        "--set", "image.repository=$IMAGE_REPOSITORY",
        "--set", "image.tag=$script:IMAGE_VERSION",
        "--set", "registry.url=$SH_REGISTRY",
        "--set", "registry.username=$env:SP_ID",
        "--set", "registry.password=$env:SP_SECRET",
        "--set-string", "podAnnotations.timestamp=$timestamp",
        "--set", "platform=$script:CLUSTER_TYPE",
        "--set", "scc.create=$script:SCC_CREATION"
    )
    
    try {
        $installOutput = & helm $helmArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ OutSystems Self-Hosted Operator installed successfully!" -ForegroundColor Green
            Write-Host "📋 Release name: $releaseName" -ForegroundColor Blue
            Write-Host ""
            Write-Host "🔍 Installation details:" -ForegroundColor Blue
            Write-Host $installOutput
            Write-Host ""
            
            # Check if pods are running
            Write-Host "⏳ Waiting for pods to be ready..." -ForegroundColor Yellow
            if (Test-ShoPodStatus $releaseName $NAMESPACE) {
                Write-Host "🎉 OutSystems Self-Hosted Operator is running successfully!" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️  Installation completed but pods are not ready yet" -ForegroundColor Yellow
                Write-Host ""
                Show-TroubleshootingCommands $releaseName $NAMESPACE
            }
            Write-Host ""
            return $true
        }
        else {
            Write-Host "❌ Failed to install OutSystems Self-Hosted Operator" -ForegroundColor Red
            Write-Host "🔍 Error details:" -ForegroundColor Blue
            Write-Host $installOutput
            
            # Parse specific error types
            if ($installOutput -match "already exists") {
                Write-Host ""
                Write-Host "💡 Release already exists. Use a different name or uninstall the existing release." -ForegroundColor Yellow
            }
            elseif ($installOutput -match "no such host|connection refused") {
                Write-Host ""
                Write-Host "💡 Network connectivity issue. Check registry URL and internet connection." -ForegroundColor Yellow
            }
            
            return $false
        }
    }
    catch {
        Write-Host "❌ Failed to install OutSystems Self-Hosted Operator: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Function to check if SHO pods are running
function Test-ShoPodStatus {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    $maxWaitTime = 300  # 5 minutes
    $checkInterval = 10  # 10 seconds
    $elapsedTime = 0
    
    Write-Host "🔍 Checking OutSystems Self-Hosted Operator pod status..." -ForegroundColor Blue
    Write-Host "   Namespace: $Namespace" -ForegroundColor Gray
    Write-Host "   Release: $ReleaseName" -ForegroundColor Gray
    Write-Host ""
    
    while ($elapsedTime -lt $maxWaitTime) {
        try {
            # Get pod status
            $podInfo = kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" --no-headers 2>$null
            
            if ([string]::IsNullOrEmpty($podInfo)) {
                Write-Host "⏳ No pods found yet... (${elapsedTime}s elapsed)" -ForegroundColor Yellow
            }
            else {
                Write-Host "📋 Current pod status:" -ForegroundColor Blue
                Write-Host $podInfo
                Write-Host ""
                
                # Check if any pod is running and ready
                $podLines = $podInfo -split "`n" | Where-Object { $_.Trim() -ne "" }
                $runningPods = ($podLines | Where-Object { $_ -match "Running.*true" }).Count
                $totalPods = $podLines.Count
                
                if ($runningPods -gt 0 -and $runningPods -eq $totalPods) {
                    Write-Host "✅ All SHO pods are running and ready!" -ForegroundColor Green
                    return $true
                }
                elseif ($podInfo -match "Error|CrashLoopBackOff|ImagePullBackOff") {
                    Write-Host "❌ Pod(s) in error state detected!" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "🔍 Detailed pod status:" -ForegroundColor Blue
                    kubectl describe pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName"
                    Write-Host ""
                    Write-Host "📋 Pod events:" -ForegroundColor Blue
                    kubectl get events -n $Namespace --field-selector involvedObject.kind=Pod --sort-by=.metadata.creationTimestamp
                    return $false
                }
                else {
                    Write-Host "⏳ Pods still starting... ($runningPods/$totalPods ready) - waiting ${checkInterval}s..." -ForegroundColor Yellow
                }
            }
            
            Start-Sleep -Seconds $checkInterval
            $elapsedTime += $checkInterval
            Write-Host "   Elapsed time: ${elapsedTime}s / ${maxWaitTime}s" -ForegroundColor Gray
            Write-Host ""
        }
        catch {
            Write-Host "⚠️  Error checking pod status: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds $checkInterval
            $elapsedTime += $checkInterval
        }
    }
    
    Write-Host "⚠️  Timeout reached while waiting for pods to be ready" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "🔍 Final pod status:" -ForegroundColor Blue
    kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$ReleaseName" -o wide 2>$null
    Write-Host ""
    Write-Host "📋 Recent events:" -ForegroundColor Blue
    kubectl get events -n $Namespace --sort-by=.metadata.creationTimestamp --tail=10 2>$null
    
    return $false
}

# Function to show useful troubleshooting commands
function Show-TroubleshootingCommands {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    Write-Host "🛠️  Troubleshooting Commands:" -ForegroundColor Blue
    Write-Host ""
    Write-Host "📊 Check pod status:" -ForegroundColor White
    Write-Host "   kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📋 Describe pods:" -ForegroundColor White
    Write-Host "   kubectl describe pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📝 View pod logs:" -ForegroundColor White
    Write-Host "   kubectl logs -n $Namespace -l app.kubernetes.io/instance=$ReleaseName --tail=50" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "📋 Check events:" -ForegroundColor White
    Write-Host "   kubectl get events -n $Namespace --sort-by=.metadata.creationTimestamp" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚡ Check helm status:" -ForegroundColor White
    Write-Host "   helm status $ReleaseName -n $Namespace" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🔄 Restart deployment:" -ForegroundColor White
    Write-Host "   kubectl rollout restart deployment -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Cyan
}

# Function to test if URL is accessible
function Test-UrlAccessible {
    param(
        [string]$Url,
        [int]$MaxTries = 10,
        [int]$RetryInterval = 20
    )
    
    Write-Host "🔍 Testing URL accessibility: $Url" -ForegroundColor Blue
    Write-Host "   Will try up to $MaxTries times with ${RetryInterval}s intervals" -ForegroundColor Gray
    
    for ($try = 1; $try -le $MaxTries; $try++) {
        Write-Host "   Attempt $try/$MaxTries..." -ForegroundColor Gray
        
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "✅ URL is accessible after $try attempt(s)" -ForegroundColor Green
                return $true
            }
        }
        catch {
            if ($try -lt $MaxTries) {
                Write-Host "   ⏳ URL not accessible yet, waiting ${RetryInterval}s before next attempt..." -ForegroundColor Yellow
                Start-Sleep -Seconds $RetryInterval
            }
            else {
                Write-Host "⚠️  URL is not accessible after $MaxTries attempts" -ForegroundColor Yellow
            }
        }
    }
    
    return $false
}

# Function to expose SHO service with a LoadBalancer and verify it's online
function Expose-ShoService {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    
    $serviceName = $ReleaseName
    $routeName = "$ReleaseName-public"
    $port = 5050
    $maxAttempts = 30
    
    Write-Host "🌐 Creating LoadBalancer for service $serviceName..." -ForegroundColor Blue
    
    # Check if the source service exists
    try {
        kubectl get svc $serviceName -n $Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: Service $serviceName does not exist in namespace $Namespace" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "❌ Error: Service $serviceName does not exist in namespace $Namespace" -ForegroundColor Red
        return $false
    }
    
    # Check if the LoadBalancer service already exists
    try {
        kubectl get svc $routeName -n $Namespace 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "📦 LoadBalancer does not exist, creating it..." -ForegroundColor Blue
            kubectl expose svc $serviceName --name=$routeName --type=LoadBalancer --port=$port --target-port=$port -n $Namespace
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Failed to create LoadBalancer service" -ForegroundColor Red
                return $false
            }
        }
        else {
            Write-Host "ℹ️ LoadBalancer service already exists" -ForegroundColor Blue
        }
    }
    catch {
        Write-Host "❌ Failed to create LoadBalancer service: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    
    Write-Host "⏳ Waiting for the LoadBalancer to become ready..." -ForegroundColor Yellow
    
    for ($attempts = 0; $attempts -lt $maxAttempts; $attempts++) {
        try {
            # Try to get hostname first, then IP if hostname is not available
            $routeUrl = kubectl get svc $routeName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
            
            if ([string]::IsNullOrEmpty($routeUrl)) {
                $routeUrl = kubectl get svc $routeName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
            
            if (![string]::IsNullOrEmpty($routeUrl)) {
                $fullUrl = "http://${routeUrl}:$port"
                Write-Host "✅ LoadBalancer is ready!" -ForegroundColor Green
                Write-Host "🌐 The external URL for SHO is: $fullUrl" -ForegroundColor Green
                Write-Host ""
                Write-Host "📝 To access SHO later:" -ForegroundColor White
                Write-Host "   $fullUrl" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "📋 To check status:" -ForegroundColor White
                Write-Host "   kubectl get svc $routeName -n $Namespace" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "🗑️ To remove this LoadBalancer:" -ForegroundColor White
                Write-Host "   kubectl delete svc $routeName -n $Namespace" -ForegroundColor Cyan
                
                # Wait for DNS record to propagate and service to start responding
                Write-Host ""
                Write-Host "🔍 Checking if SHO console is responding..." -ForegroundColor Blue
                Write-Host "⏳ Waiting for DNS record to propagate..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
                
                # Test URL accessibility before opening browser
                if (Test-UrlAccessible $fullUrl 10) {
                    Write-Host "🎉 SHO console is responding! Opening browser..." -ForegroundColor Green
                    
                    try {
                        Start-Process $fullUrl
                        Write-Host "✅ Browser opened successfully" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "ℹ️ Could not open browser automatically. Please open this URL manually:" -ForegroundColor Blue
                        Write-Host "   $fullUrl" -ForegroundColor Cyan
                    }
                }
                else {
                    Write-Host "⚠️  SHO console is not yet responding" -ForegroundColor Yellow
                    Write-Host "ℹ️ The LoadBalancer is ready, but the application might still be starting up" -ForegroundColor Blue
                    Write-Host "📝 Please wait a few minutes and try accessing:" -ForegroundColor White
                    Write-Host "   $fullUrl" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "🔍 You can check the pod status with:" -ForegroundColor White
                    Write-Host "   kubectl get pods -n $Namespace -l app.kubernetes.io/instance=$ReleaseName" -ForegroundColor Cyan
                    Write-Host "   kubectl logs -n $Namespace -l app.kubernetes.io/instance=$ReleaseName --tail=20" -ForegroundColor Cyan
                }
                
                return $true
            }
            
            Write-Host "   LoadBalancer not ready yet. Attempt $($attempts + 1)/$maxAttempts - waiting 10 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
        catch {
            Write-Host "   Error checking LoadBalancer status: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 10
        }
    }
    
    Write-Host "❌ Error: LoadBalancer creation timed out after $($maxAttempts * 10) seconds" -ForegroundColor Red
    Write-Host "   This might be due to:" -ForegroundColor Yellow
    Write-Host "   - Your cloud provider is still provisioning the LoadBalancer" -ForegroundColor Yellow
    Write-Host "   - Quota limitations in your cloud account" -ForegroundColor Yellow
    Write-Host "   - Network policies blocking external access" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "📋 Check status with:" -ForegroundColor White
    Write-Host "   kubectl get svc $routeName -n $Namespace" -ForegroundColor Cyan
    Write-Host "   kubectl describe svc $routeName -n $Namespace" -ForegroundColor Cyan
    
    return $false
}

# Function to uninstall OutSystems Self-Hosted Operator
function Uninstall-Sho {
    param(
        [string]$ReleaseName = "self-hosted-operator"
    )
    
    $routeName = "$ReleaseName-public"
    
    Write-Host "⚠️  WARNING: You are about to uninstall OutSystems Self-Hosted Operator" -ForegroundColor Red
    Write-Host "    This will remove the Helm release, LoadBalancer service, and the namespace" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Release: $ReleaseName" -ForegroundColor White
    Write-Host "    Namespace: $NAMESPACE" -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "🚨 Are you sure you want to proceed with uninstallation? (yes/no)"
    
    if ($confirm -ne "yes") {
        Write-Host "🛑 Uninstallation cancelled" -ForegroundColor Yellow
        return $true
    }
    
    Write-Host ""
    Write-Host "🗑️ Uninstalling OutSystems Self-Hosted Operator..." -ForegroundColor Blue
    
    # Check if the release exists
    try {
        helm status $ReleaseName -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: Release $ReleaseName not found in namespace $NAMESPACE" -ForegroundColor Red
            Write-Host "   To see installed releases, run: helm list --all-namespaces" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ Error: Release $ReleaseName not found in namespace $NAMESPACE" -ForegroundColor Red
        return $false
    }
    
    # Check for LoadBalancer service and remove it
    Write-Host "🔍 Checking for LoadBalancer service..." -ForegroundColor Blue
    try {
        kubectl get svc $routeName -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "🗑️ Removing LoadBalancer service $routeName..." -ForegroundColor Blue
            kubectl delete svc $routeName -n $NAMESPACE
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ LoadBalancer service successfully removed" -ForegroundColor Green
            }
            else {
                Write-Host "⚠️ Failed to remove LoadBalancer service" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "ℹ️ No LoadBalancer service found" -ForegroundColor Blue
        }
    }
    catch {
        Write-Host "ℹ️ No LoadBalancer service found" -ForegroundColor Blue
    }
    
    Write-Host "Cleaning up resources..." -ForegroundColor Blue
    
    # Clean up custom resources
    try {
        kubectl get selfhostedruntimes -o name 2>$null | ForEach-Object { kubectl patch $_ --type merge -p '{"metadata":{"finalizers":null}}' 2>$null }
        kubectl get selfhostedvaultoperators -o name 2>$null | ForEach-Object { kubectl patch $_ --type merge -p '{"metadata":{"finalizers":null}}' 2>$null }
        kubectl delete selfhostedruntime --ignore-not-found self-hosted-runtime 2>$null
    }
    catch {
        # Ignore errors in cleanup
    }

    # Uninstall the Helm release
    Write-Host ""
    Write-Host "🗑️ Uninstalling SHO Helm release..." -ForegroundColor Blue
    
    try {
        $uninstallOutput = helm uninstall $ReleaseName -n $NAMESPACE 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ SHO release $ReleaseName successfully uninstalled" -ForegroundColor Green
            Write-Host "Waiting for resources to cleanup..." -ForegroundColor Blue
            Start-Sleep -Seconds 30
            
            # Additional cleanup
            try {
                kubectl get vaultroles.self-hosted-vault-operator.outsystemscloud.com -o name 2>$null | ForEach-Object { kubectl patch $_ --type merge -p '{"metadata":{"finalizers":null}}' 2>$null }
                
                $namespacesToClean = @("flux-sdlc", "sh-registry", "vault", "istio-system", "outsystems-gloo-system", "nats-auth", "outsystems-gloo-system", "flux-system", "outsystems-prometheus", "outsystems-rbac-manager", "outsystems-stakater", "vault-operator", "seaweedfs", "authorization-services")
                
                foreach ($ns in $namespacesToClean) {
                    Write-Host "Patching up namespace: $ns" -ForegroundColor Blue
                    kubectl get helmcharts,helmreleases,kustomizations,helmrepositories -n $ns -o name 2>$null | ForEach-Object { kubectl patch $_ -n $ns --type merge -p '{"metadata":{"finalizers":null}}' 2>$null }
                }
                
                Start-Sleep -Seconds 10
                
                $namespacesToDelete = @("flux-sdlc", "nats-auth", "sh-registry", "seaweedfs", "outsystems-otel", "outsystems-fluentbit", "outsystems-prometheus", "nats-auth", "nats-leaf", "authorization-services")
                
                foreach ($ns in $namespacesToDelete) {
                    Write-Host "Cleaning up namespace: $ns" -ForegroundColor Blue
                    kubectl get pods -n $ns -o name 2>$null | ForEach-Object { kubectl delete $_ -n $ns --force 2>$null }
                }
            }
            catch {
                # Ignore cleanup errors
            }
            
            Write-Host "🗑️ Deleting namespace $NAMESPACE..." -ForegroundColor Blue
            kubectl delete namespace $NAMESPACE --wait=false 2>$null
            kubectl delete namespace $NAMESPACE_CRED_JOB --wait=false 2>$null
                
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Namespace deletion initiated" -ForegroundColor Green
                Write-Host "   Note: Namespace deletion might take some time to complete" -ForegroundColor Yellow
            }
            else {
                Write-Host "❌ Failed to delete namespace" -ForegroundColor Red
            }
        }
        else {
            Write-Host "❌ Failed to uninstall SHO release" -ForegroundColor Red
            Write-Host "🔍 Error details:" -ForegroundColor Blue
            Write-Host $uninstallOutput
            return $false
        }
    }
    catch {
        Write-Host "❌ Failed to uninstall SHO release: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    
    Write-Host ""
    Write-Host "🎉 OutSystems Self-Hosted Operator was successfully uninstalled!" -ForegroundColor Green
    return $true
}

# Main execution
if ($Help) {
    Show-Usage
    exit 0
}

# Handle GetConsoleUrl
if ($GetConsoleUrl) {
    # Check SHO is installed
    try {
        helm status $CHART_NAME -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: OutSystems Self-Hosted Operator is not installed" -ForegroundColor Red
            Write-Host "   Please install it first using: .\installer.ps1" -ForegroundColor Yellow
            exit 1
        }
    }
    catch {
        Write-Host "❌ Error: OutSystems Self-Hosted Operator is not installed" -ForegroundColor Red
        exit 1
    }
    
    # Get the LoadBalancer service URL
    Write-Host "🌐 Retrieving LoadBalancer service URL for $CHART_NAME..." -ForegroundColor Blue
    
    try {
        kubectl get svc "$CHART_NAME-public" -n $NAMESPACE 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $routeUrl = kubectl get svc "$CHART_NAME-public" -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
            if ([string]::IsNullOrEmpty($routeUrl)) {
                $routeUrl = kubectl get svc "$CHART_NAME-public" -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
            
            if (![string]::IsNullOrEmpty($routeUrl)) {
                Write-Host "✅ LoadBalancer URL: http://$routeUrl`:5050" -ForegroundColor Green
                $fullUrl = "http://${routeUrl}:5050"
                
                if (Test-UrlAccessible $fullUrl 10) {
                    Write-Host "🎉 SHO console is responding! Opening browser..." -ForegroundColor Green
                    
                    try {
                        Start-Process $fullUrl
                        Write-Host "✅ Browser opened successfully" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "ℹ️ Could not open browser automatically. Please open this URL manually:" -ForegroundColor Blue
                        Write-Host "   $fullUrl" -ForegroundColor Cyan
                    }
                }
                exit 0
            }
            else {
                Write-Host "❌ Error: LoadBalancer service URL not found. Please contact support!!!" -ForegroundColor Red
                exit 1
            }
        }
        else {
            Write-Host "❌ Error: LoadBalancer service $CHART_NAME-public not found in namespace $NAMESPACE. Creating it now..." -ForegroundColor Red
            Expose-ShoService $CHART_NAME $NAMESPACE
            exit 0
        }
    }
    catch {
        Write-Host "❌ Error retrieving console URL: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($Uninstall) {
    Write-Host "🗑️ Uninstalling OutSystems Self-Hosted Operator..." -ForegroundColor Blue
    Uninstall-Sho $CHART_NAME
    exit 0
}

# Set version from parameter
if ($Version) {
    $script:HELM_CHART_VERSION = $Version
    Write-Host "📝 Using version: $script:HELM_CHART_VERSION" -ForegroundColor Blue
}

# Set repository from parameter
if ($Repository) {
    $script:CHART_REPO = "$Repository/$CHART_NAME"
    Write-Host "📝 Using repository: $Repository" -ForegroundColor Blue
}

# Set default version if not provided
if ([string]::IsNullOrEmpty($script:HELM_CHART_VERSION)) {
    Write-Host "📝 Version not provided, checking latest version available" -ForegroundColor Blue
    if (!(Get-LatestShoVersion)) {
        Write-Host "❌ Failed to get latest version" -ForegroundColor Red
        exit 1
    }
}

# Show current configuration
Write-Host "=== Configuration ===" -ForegroundColor White
Write-Host "Repository URL: $script:CHART_REPO" -ForegroundColor Gray
Write-Host "Version: $script:HELM_CHART_VERSION" -ForegroundColor Gray
Write-Host ""

Write-Host "🔍 Checking all dependencies..." -ForegroundColor Blue
if (!(Test-Dependencies)) {
    Write-Host "💥 Please resolve dependency issues before proceeding" -ForegroundColor Red
    Write-Host "💡 Run '.\installer.ps1 -Help' for usage information" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "🔍 Analyzing Kubernetes cluster..." -ForegroundColor Blue
Get-ClusterType

Write-Host ""
Write-Host "🚀 Ready to install SHO!" -ForegroundColor Green

if (Install-Sho) {
    Expose-ShoService $CHART_NAME $NAMESPACE
    Write-Host ""
    Write-Host "🎉 OutSystems Self-Hosted Operator was successfully installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your OutSystems Self-Hosted environment is now ready for use." -ForegroundColor White
    Write-Host "📊 Management Commands:" -ForegroundColor White
    Write-Host "   helm status $CHART_NAME -n $NAMESPACE" -ForegroundColor Cyan
    Write-Host "   kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🗑️  To uninstall:" -ForegroundColor White
    Write-Host "   .\installer.ps1 -Uninstall" -ForegroundColor Cyan
}
else {
    Write-Host ""
    Write-Host "💥 Installation failed. Please check the error messages above." -ForegroundColor Red
    Write-Host "💡 Run '.\installer.ps1 -Help' for usage information" -ForegroundColor Yellow
    exit 1
}
