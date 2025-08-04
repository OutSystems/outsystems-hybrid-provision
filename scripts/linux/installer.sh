#!/bin/bash

set -e

# Configuration
NAMESPACE="self-hosted-operator"
NAMESPACE_CRED_JOB="self-hosted-registry-credentials-job"

CHART_NAME="self-hosted-operator"
# TODO: Update with ga ecr repo when available
HELM_REPO_URL=${HELM_REPO_URL:-"oci://public.ecr.aws/g4u4y4x2/lab/helm"}
CHART_REPO=$HELM_REPO_URL"/$CHART_NAME"
IMAGE_REGISTRY=${IMAGE_REGISTRY:-"public.ecr.aws/g4u4y4x2"}
IMAGE_REPOSITORY="self-hosted-operator"
REPO="g4u4y4x2/lab/helm/self-hosted-operator"

SH_REGISTRY=${SH_REGISTRY:-""}

# Setup environment configs
if [[ $ENV == "non-prod" ]]; then
    echo "🔧 Setting environment to non production"
    # TODO: Update with test ecr repo when available
    HELM_REPO_URL=${HELM_REPO_URL:-"oci://public.ecr.aws/g4u4y4x2/lab/helm"}
    CHART_REPO=$HELM_REPO_URL"/$CHART_NAME"
    IMAGE_REGISTRY=${IMAGE_REGISTRY:-"public.ecr.aws/g4u4y4x2"}

fi

# Function to check if Helm is installed
check_helm_installed() {
    if command -v helm &> /dev/null; then
        echo "✅ Helm is already installed"
        helm version --short
        return 0
    else
        echo "❌ Helm is not installed"
        return 1
    fi
}

# Function to install Helm on macOS
install_helm() {
    echo "🚀 Installing Helm..."
    
    # Detect Linux distribution type
    if command -v apt-get &> /dev/null; then
        echo "📦 Detected Debian-based distribution (apt)"
        
        # First try to install via apt
        echo "📦 Attempting to install Helm via apt..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https gnupg
        
        curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
        echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update
        sudo apt-get install -y helm
        
        if [ $? -eq 0 ]; then
            echo "✅ Helm installed successfully via apt"
            helm version --short
            return 0
        else
            echo "❌ Failed to install Helm via apt"
            echo "📦 Falling back to script installation..."
        fi
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        echo "📦 Detected Red Hat-based distribution (yum/dnf)"
        
        # Determine which package manager to use
        PKG_MANAGER="yum"
        if command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        fi
        
        echo "📦 Attempting to install Helm via $PKG_MANAGER..."
        
        # Add Helm repository
        sudo $PKG_MANAGER install -y epel-release
        
        # Install Helm
        if [ "$PKG_MANAGER" = "dnf" ]; then
            # For Fedora/newer RHEL
            sudo $PKG_MANAGER install -y helm
        else
            # For CentOS/RHEL
            curl -fsSL -o helm-stable-repo.rpm https://github.com/helm/helm/releases/download/v3.12.0/helm-3.12.0-1.el7.x86_64.rpm
            sudo $PKG_MANAGER install -y ./helm-stable-repo.rpm
            rm -f helm-stable-repo.rpm
        fi
        
        if [ $? -eq 0 ]; then
            echo "✅ Helm installed successfully via $PKG_MANAGER"
            helm version --short
            return 0
        else
            echo "❌ Failed to install Helm via $PKG_MANAGER"
            echo "📦 Falling back to script installation..."
        fi
    fi
    
    # Fall back to using the official script for all distributions
    echo "📦 Installing Helm via official script..."
    
    # Download and install Helm using the official script
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    
    # Clean up the script
    rm -f get_helm.sh
    
    if command -v helm &> /dev/null; then
        echo "✅ Helm installed successfully via script"
        helm version --short
        return 0
    else
        echo "❌ Failed to install Helm via script"
        return 1
    fi
}

# Function to ensure Helm is installed (combines check and install)
ensure_helm_installed() {
    echo "🔍 Checking Helm installation..."
    
    if check_helm_installed; then
        return 0
    else
        echo "🔧 Helm not found. Proceeding with installation..."
        install_helm
        return $?
    fi
}

# Function to install AWS CLI on Linux
install_aws_cli() {
    echo "🚀 Installing AWS CLI..."
    
    # Detect Linux distribution type
    if command -v apt-get &> /dev/null; then
        echo "📦 Installing AWS CLI via apt..."
        sudo apt-get update
        sudo apt-get install -y awscli
        
        if [ $? -eq 0 ]; then
            echo "✅ AWS CLI installed successfully via apt"
            aws --version
            return 0
        else
            echo "❌ Failed to install AWS CLI via apt, trying direct download..."
        fi
    elif command -v yum &> /dev/null; then
        echo "📦 Installing AWS CLI via yum..."
        sudo yum install -y awscli
        
        if [ $? -eq 0 ]; then
            echo "✅ AWS CLI installed successfully via yum"
            aws --version
            return 0
        else
            echo "❌ Failed to install AWS CLI via yum, trying direct download..."
        fi
    elif command -v dnf &> /dev/null; then
        echo "📦 Installing AWS CLI via dnf..."
        sudo dnf install -y awscli
        
        if [ $? -eq 0 ]; then
            echo "✅ AWS CLI installed successfully via dnf"
            aws --version
            return 0
        else
            echo "❌ Failed to install AWS CLI via dnf, trying direct download..."
        fi
    fi
    
    # Fallback to direct download installation
    echo "📦 Installing AWS CLI via direct download..."
    
    # Download and install AWS CLI using the official installer
    echo "📥 Downloading AWS CLI installer..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    
    if [ $? -eq 0 ]; then
        echo "📦 Installing AWS CLI..."
        unzip -q awscliv2.zip
        sudo ./aws/install
        
        # Clean up the installer
        rm -rf awscliv2.zip aws/
        
        if command -v aws &> /dev/null; then
            echo "✅ AWS CLI installed successfully"
            aws --version
            return 0
        else
            echo "❌ AWS CLI installation verification failed"
            return 1
        fi
    else
        echo "❌ Failed to download AWS CLI installer"
        return 1
    fi
}

# Function to ensure AWS CLI is installed
ensure_aws_cli_installed() {
    echo "🔍 Checking AWS CLI installation..."
    
    if command -v aws &> /dev/null; then
        echo "✅ AWS CLI is already installed"
        aws --version
        return 0
    else
        echo "🔧 AWS CLI not found. Proceeding with installation..."
        install_aws_cli
        return $?
    fi
}

# Function to check all dependencies required for helm chart installation
check_dependencies() {
    local all_deps_ok=true
    
    # Check AWS CLI (required for ECR authentication)
    echo "📋 Checking AWS CLI..."
    if ! ensure_aws_cli_installed; then
        echo "❌ Failed to ensure AWS CLI is available"
        all_deps_ok=false
    fi
    
    # Check jq (required for JSON parsing)
    echo "📋 Checking jq..."
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Installing jq..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y jq
            if [ $? -eq 0 ]; then
                echo "✅ jq installed successfully via apt"
            else
                echo "❌ Failed to install jq via apt"
                all_deps_ok=false
            fi
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
            if [ $? -eq 0 ]; then
                echo "✅ jq installed successfully via yum"
            else
                echo "❌ Failed to install jq via yum"
                all_deps_ok=false
            fi
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y jq
            if [ $? -eq 0 ]; then
                echo "✅ jq installed successfully via dnf"
            else
                echo "❌ Failed to install jq via dnf"
                all_deps_ok=false
            fi
        else
            echo "❌ Package manager not found. Please install jq manually"
            all_deps_ok=false
        fi
    else
        echo "✅ jq is already installed"
    fi
    
    # Check Helm
    echo "📋 Checking Helm..."
    if ! ensure_helm_installed; then
        echo "❌ Failed to ensure Helm is available"
        all_deps_ok=false
    fi
    
    # Check kubectl
    echo "📋 Checking kubectl..."
    if ! ensure_kubectl_installed; then
        echo "❌ Failed to ensure kubectl is available"
        all_deps_ok=false
    fi
    
    # Check Kubernetes cluster connectivity using Helm
    echo "📋 Checking Kubernetes cluster connectivity via Helm..."
    if helm list --all-namespaces &> /dev/null; then
        echo "✅ Helm can connect to Kubernetes cluster"
    else
        echo "❌ Helm cannot connect to Kubernetes cluster"
        echo "   Make sure you have:"
        echo "   - A valid kubeconfig file"
        echo "   - Access to a Kubernetes cluster"
        echo "   - Proper cluster permissions"
        all_deps_ok=false
    fi
    
    if [ "$all_deps_ok" = true ]; then
        echo "🎉 All required dependencies are satisfied!"
        return 0
    else
        echo "💥 Some dependencies are missing or failed to install"
        return 1
    fi
}

# Function to verify repository access and list available charts
verify_repo_access() {    
    echo "🔍 Verifying repository access"

    helm_output=$(helm show chart $CHART_REPO 2>&1)
    helm_exit_code=$?
    if [ $helm_exit_code -eq 0 ] ; then
        echo "✅ SHO Registry is accessible"
        return 0
    else
        echo "❌ Cannot access OutSystems repository or no charts found"
        echo "Error: $helm_output"
        return 1
    fi
}

# Function to identify Kubernetes cluster type and set appropriate options
identify_cluster() {
    echo "🔍 Identifying cluster type..."
    
    # Determine cluster type based on node labels
    if kubectl get nodes --output=jsonpath='{.items[0].metadata.labels}' | grep -q 'openshift'; then
        CLUSTER_TYPE="ocp"
    elif kubectl get nodes --output=jsonpath='{.items[0].metadata.labels}' | grep -q 'azure'; then
        CLUSTER_TYPE="azure"
    elif kubectl get nodes --output=jsonpath='{.items[0].metadata.labels}' | grep -q 'eks.amazonaws.com'; then
        CLUSTER_TYPE="aws"
    else
        CLUSTER_TYPE="unknown"
    fi

    echo "✅ Cluster type identified: $CLUSTER_TYPE"

    # Set Helm flags based on cluster type
    if [ "$CLUSTER_TYPE" = "openshift" ]; then
        echo "🔧 Setting OpenShift specific options"
        echo "   - Using SCC (Security Context Constraints)"
        SCC_CREATION="true"
    else
        SCC_CREATION="false"
    fi
}

# Get latest self-hosted operator version
get_latest_sho_version() {
    echo "🔍 Fetching latest OutSystems Self-Hosted Operator version..."
    
    # Use the same token method as the ECR authentication
    local token_response
    token_response=$(curl -sL "https://public.ecr.aws/token?scope=repository:${REPO}:pull" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$token_response" ]; then
        echo "❌ Failed to get token from ECR public API"
        return 1
    fi
    
    local token
    token=$(echo "$token_response" | jq -r '.token' 2>/dev/null)
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "❌ Failed to extract token from ECR response"
        return 1
    fi
    
    # Get tags using the token
    local tags_response
    tags_response=$(curl -s -H "Authorization: Bearer $token" \
        "https://public.ecr.aws/v2/${REPO}/tags/list" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$tags_response" ]; then
        echo "❌ Failed to fetch tags from ECR repository"
        return 1
    fi
    
    local tags
    tags=$(echo "$tags_response" | jq -r '.tags[]' 2>/dev/null)
    
    if [ -z "$tags" ]; then
        echo "❌ No tags found in ECR repository response"
        return 1
    fi
    
    local latest_version
    latest_version=$(echo "$tags" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
    
    if [ -z "$latest_version" ]; then
        echo "❌ Failed to find a valid version from tags"
        echo "Available tags: $tags"
        return 1
    fi
    
    echo "✅ Latest version found: $latest_version"
    export HELM_CHART_VERSION="$latest_version"
    return 0
}

# Function to authenticate with ECR public registry using AWS CLI
ecr_helm_login() {
    echo "🔐 Setting up ECR public registry access for Helm..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed or not available in PATH"
        echo "💡 Please ensure AWS CLI is installed by running the dependency check"
        return 1
    fi
    
    echo "🔑 Using AWS CLI for ECR public authentication..."
    
    # Login using AWS CLI and Helm
    aws ecr-public get-login-password --region us-east-1 2>/dev/null | helm registry login --username AWS --password-stdin public.ecr.aws 2>&1
    if [[ $? -ne 0 ]]; then
        echo "❌ Failed to authenticate with ECR public registry"
        echo "💡 Possible reasons:"
        echo "   - No AWS credentials available"
        echo "   - Network connectivity issues"
        echo "   - Insufficient permissions"
        echo ""
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version=VERSION        The SHO chart version to install (optional, defaults to latest)"
    echo "  --repository=REPO_URL    The SHO registry URL (optional, uses default if not specified)"
    echo "  --uninstall              Uninstall OutSystems Self-Hosted Operator"
    echo "  --env                    Set the environment (non-prod, prod, etc.)"
    echo "  --get-console-url        Get the console URL for the installed SHO"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --version=1.2.3"
    echo "  $0 --repository=registry.example.com"
    echo "  $0 --version=1.2.3 --repository=registry.example.com"
    echo "  $0 --env=non-prod --get-console-url"
}

# Function to install OutSystems Self-Hosted Operator
sho_install() {
    echo "🚀 Installing OutSystems Self-Hosted Operator..."
    
    # Authenticate with ECR public registry
    if ! ecr_helm_login; then
        echo "❌ Failed to authenticate with ECR public registry"
        return 1
    fi
    
    # Prepare the chart URL
    if [ "$HELM_CHART_VERSION" != "latest" ]; then
        CHART_REPO="$CHART_REPO:$HELM_CHART_VERSION"
        IMAGE_VERSION="v$HELM_CHART_VERSION"
    fi

    echo "📦 Installing SHO chart from: $CHART_REPO"
    
    local release_name="self-hosted-operator"
    
    # Install the chart
    local install_output
    local install_exit_code

    kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace $NAMESPACE already exists, skipping creation"
    kubectl create namespace $NAMESPACE_CRED_JOB 2>/dev/null || echo "Namespace $NAMESPACE_CRED_JOB already exists, skipping creation"
    
    echo "🔧 Running Helm install command..."
    echo "Deploying with platform: ${CLUSTER_TYPE}"
    install_output=$(helm upgrade --install "$release_name" "$CHART_REPO" \
        --namespace $NAMESPACE \
        --create-namespace \
        --set image.registry="${IMAGE_REGISTRY}" \
        --set image.repository="${IMAGE_REPOSITORY}" \
        --set image.tag="${IMAGE_VERSION}" \
        --set registry.url="$SH_REGISTRY" \
        --set registry.username="${SP_ID}" \
        --set registry.password="${SP_SECRET}" \
        --set-string podAnnotations.timestamp="$TIMESTAMP" \
        --set platform="${CLUSTER_TYPE}" \
        --set scc.create="${SCC_CREATION}")
    install_exit_code=$?
    
    if [ $install_exit_code -eq 0 ]; then
        echo "✅ OutSystems Self-Hosted Operator installed successfully!"
        echo "📋 Release name: $release_name"
        echo ""
        echo "🔍 Installation details:"
        echo "$install_output"
        echo ""
        
        # Check if pods are running
        echo "⏳ Waiting for pods to be ready..."
        if check_sho_pods_status "$release_name" "$NAMESPACE"; then
            echo "🎉 OutSystems Self-Hosted Operator is running successfully!"
        else
            echo "⚠️  Installation completed but pods are not ready yet"
            echo ""
            show_troubleshooting_commands "$release_name" "$NAMESPACE"
        fi
        echo ""    
        return 0
    else
        echo "❌ Failed to install OutSystems Self-Hosted Operator"
        echo "🔍 Error details:"
        echo "$install_output"
        
        # Parse specific error types
        if echo "$install_output" | grep -q "already exists"; then
            echo ""
            echo "💡 Release already exists. Use a different name or uninstall the existing release."
        elif echo "$install_output" | grep -q "no such host\|connection refused"; then
            echo ""
            echo "💡 Network connectivity issue. Check registry URL and internet connection."
        fi
        
        return 1
    fi
}

# Function to install kubectl on Linux
install_kubectl() {
    echo "🚀 Installing kubectl..."
    
    # Detect Linux distribution type
    if command -v apt-get &> /dev/null; then
        echo "📦 Detected Debian-based distribution (apt)"
        
        echo "📦 Updating package lists..."
        sudo apt-get update
        
        echo "📦 Installing kubectl via apt..."
        # Add Kubernetes apt repository and install
        sudo apt-get install -y apt-transport-https ca-certificates curl
        
        # Download the Google Cloud public signing key
        sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg || sudo mkdir -p /etc/apt/keyrings && sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
        
        # Add the Kubernetes apt repository
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
        
        # Update apt package index with the new repository
        sudo apt-get update
        
        # Install kubectl
        sudo apt-get install -y kubectl
        
        if [ $? -eq 0 ]; then
            echo "✅ kubectl installed successfully via apt"
            kubectl version --client --short 2>/dev/null || echo "   kubectl client installed"
            return 0
        else
            echo "❌ Failed to install kubectl via apt"
            echo "📦 Attempting installation via direct download..."
        fi
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        echo "📦 Detected Red Hat-based distribution (yum/dnf)"
        
        # Determine which package manager to use
        PKG_MANAGER="yum"
        if command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        fi
        
        # Add Kubernetes repository
        echo "[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg" | sudo tee /etc/yum.repos.d/kubernetes.repo
        
        # Install kubectl
        sudo $PKG_MANAGER install -y kubectl
        
        if [ $? -eq 0 ]; then
            echo "✅ kubectl installed successfully via $PKG_MANAGER"
            kubectl version --client --short 2>/dev/null || echo "   kubectl client installed"
            return 0
        else
            echo "❌ Failed to install kubectl via $PKG_MANAGER"
            echo "📦 Attempting installation via direct download..."
        fi
    else
        echo "📦 Unable to detect package manager. Using direct download method..."
    fi
    
    # Fall back to direct binary download if repository installation fails
    echo "📦 Installing kubectl via direct download..."
    
    # Get the latest stable version
    local kubectl_version
    kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    if [ -z "$kubectl_version" ]; then
        echo "❌ Failed to get kubectl version"
        return 1
    fi
    
    echo "📥 Downloading kubectl $kubectl_version..."
    
    # Get architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="arm" ;;
        *) echo "❌ Unsupported architecture: $ARCH"; return 1 ;;
    esac
    
    # Download kubectl binary for Linux
    if curl -LO "https://dl.k8s.io/release/$kubectl_version/bin/linux/${ARCH}/kubectl" &> /dev/null; then
        echo "✅ kubectl downloaded successfully"
        
        # Make it executable
        chmod +x kubectl
        
        # Move to a directory in PATH (try /usr/local/bin first, then ~/bin)
        if sudo mv kubectl /usr/local/bin/ 2>/dev/null; then
            echo "✅ kubectl installed to /usr/local/bin/"
        elif mkdir -p ~/bin && mv kubectl ~/bin/ && export PATH="$HOME/bin:$PATH"; then
            echo "✅ kubectl installed to ~/bin/"
            echo "ℹ️  Added ~/bin to PATH for this session"
            echo "   Add 'export PATH=\"\$HOME/bin:\$PATH\"' to your shell profile for permanent access"
        else
            echo "❌ Failed to install kubectl to system PATH"
            echo "   You may need to run with sudo or install manually"
            return 1
        fi
        
        # Verify installation
        if command -v kubectl &> /dev/null; then
            echo "✅ kubectl installed successfully"
            kubectl version --client --short 2>/dev/null || echo "   kubectl client ready"
            return 0
        else
            echo "❌ kubectl installation verification failed"
            return 1
        fi
    else
        echo "❌ Failed to download kubectl"
        return 1
    fi
}

# Function to ensure kubectl is installed (combines check and install)
ensure_kubectl_installed() {
    echo "🔍 Checking kubectl installation..."
    
    if command -v kubectl &> /dev/null; then
        echo "✅ kubectl is already installed"
        kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || echo "   kubectl client version available"
        return 0
    else
        echo "🔧 kubectl not found. Proceeding with installation..."
        install_kubectl
        return $?
    fi
}

# Function to check if SHO pods are running
check_sho_pods_status() {
    local release_name="$1"
    local namespace="$2"
    local max_wait_time=300  # 5 minutes
    local check_interval=10  # 10 seconds
    local elapsed_time=0
    
    echo "🔍 Checking OutSystems Self-Hosted Operator pod status..."
    echo "   Namespace: $namespace"
    echo "   Release: $release_name"
    echo ""
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        # Get pod status
        local pod_info
        pod_info=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/instance=$release_name" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" --no-headers 2>/dev/null)
        
        if [ -z "$pod_info" ]; then
            echo "⏳ No pods found yet... (${elapsed_time}s elapsed)"
        else
            echo "📋 Current pod status:"
            echo "$pod_info"
            echo ""
            
            # Check if any pod is running and ready
            local running_pods
            running_pods=$(echo "$pod_info" | grep "Running" | grep "true" | wc -l | tr -d ' ')
            
            local total_pods
            total_pods=$(echo "$pod_info" | wc -l | tr -d ' ')
            
            if [ "$running_pods" -gt 0 ] && [ "$running_pods" -eq "$total_pods" ]; then
                echo "✅ All SHO pods are running and ready!"
                return 0
            elif echo "$pod_info" | grep -q "Error\|CrashLoopBackOff\|ImagePullBackOff"; then
                echo "❌ Pod(s) in error state detected!"
                echo ""
                echo "🔍 Detailed pod status:"
                kubectl describe pods -n "$namespace" -l "app.kubernetes.io/instance=$release_name"
                echo ""
                echo "📋 Pod events:"
                kubectl get events -n "$namespace" --field-selector involvedObject.kind=Pod --sort-by=.metadata.creationTimestamp
                return 1
            else
                echo "⏳ Pods still starting... ($running_pods/$total_pods ready) - waiting ${check_interval}s..."
            fi
        fi
        
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
        echo "   Elapsed time: ${elapsed_time}s / ${max_wait_time}s"
        echo ""
    done
    
    echo "⚠️  Timeout reached while waiting for pods to be ready"
    echo ""
    echo "🔍 Final pod status:"
    kubectl get pods -n "$namespace" -l "app.kubernetes.io/instance=$release_name" -o wide 2>/dev/null || echo "No pods found"
    echo ""
    echo "📋 Recent events:"
    kubectl get events -n "$namespace" --sort-by=.metadata.creationTimestamp --tail=10 2>/dev/null || echo "No events available"
    
    return 1
}

# Function to show useful troubleshooting commands
show_troubleshooting_commands() {
    local release_name="$1"
    local namespace="$2"
    
    echo "🛠️  Troubleshooting Commands:"
    echo ""
    echo "📊 Check pod status:"
    echo "   kubectl get pods -n $namespace -l app.kubernetes.io/instance=$release_name"
    echo ""
    echo "📋 Describe pods:"
    echo "   kubectl describe pods -n $namespace -l app.kubernetes.io/instance=$release_name"
    echo ""
    echo "📝 View pod logs:"
    echo "   kubectl logs -n $namespace -l app.kubernetes.io/instance=$release_name --tail=50"
    echo ""
    echo "📋 Check events:"
    echo "   kubectl get events -n $namespace --sort-by=.metadata.creationTimestamp"
    echo ""
    echo "⚡ Check helm status:"
    echo "   helm status $release_name -n $namespace"
    echo ""
    echo "🔄 Restart deployment:"
    echo "   kubectl rollout restart deployment -n $namespace -l app.kubernetes.io/instance=$release_name"
}

# Function to test if URL is accessible using curl with retries
test_url_accessible() {
    local url="$1"
    local timeout=10
    local max_tries=10  # Default to 10 tries
    local retry_interval=20    # Wait 20 seconds between retries
    local try=1
    
    echo "🔍 Testing URL accessibility: $url"
    echo "   Will try up to $max_tries times with ${retry_interval}s intervals"
    
    while [ $try -le $max_tries ]; do
        echo "   Attempt $try/$max_tries..."
        
        # Use curl to test if the URL is accessible
        if curl -s -f --connect-timeout "$timeout" --max-time "$timeout" --head "$url" >/dev/null 2>&1; then
            echo "✅ URL is accessible after $try attempt(s)"
            return 0
        else
            if [ $try -lt $max_tries ]; then
                echo "   ⏳ URL not accessible yet, waiting ${retry_interval}s before next attempt..."
                sleep $retry_interval
            else
                echo "⚠️  URL is not accessible after $max_tries attempts"
            fi
        fi
        
        try=$((try + 1))
    done
    
    return 1
}

expose_sho_service() {
    local release_name="$1"
    local namespace="$2"
    local service_name="${release_name}"
    local route_name="${release_name}-public"
    local port=5050
    local max_attempts=30
    local connect_timeout=5  # curl connection timeout in seconds
    
    echo "🌐 Creating LoadBalancer for service $service_name..."
    
    # Check if the source service exists
    if ! kubectl get svc "$service_name" -n "$namespace" >/dev/null 2>&1; then 
        echo "❌ Error: Service $service_name does not exist in namespace $namespace"
        return 1
    fi
    
    # Check if the LoadBalancer service already exists
    if ! kubectl get svc "$route_name" -n "$namespace" >/dev/null 2>&1; then 
        echo "📦 LoadBalancer does not exist, creating it..."
        kubectl expose svc "$service_name" --name="$route_name" --type=LoadBalancer --port="$port" --target-port="$port" -n "$namespace"
        
        if [ $? -ne 0 ]; then
            echo "❌ Failed to create LoadBalancer service"
            return 1
        fi
    else 
        echo "ℹ️ LoadBalancer service already exists"
    fi
    
    echo "⏳ Waiting for the LoadBalancer to become ready..."
    local attempts=0
    
    while [ ${attempts} -lt "$max_attempts" ]; do 
        # Try to get hostname first, then IP if hostname is not available
        local route_url
        route_url=$(kubectl get svc "$route_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
        
        if [ -z "${route_url}" ]; then
            route_url=$(kubectl get svc "$route_name" -n "$namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        fi
        
        if [ -n "${route_url}" ]; then 
            local full_url="http://${route_url}:$port"
            echo "✅ LoadBalancer is ready!"
            echo "🌐 The external URL for SHO is: $full_url"
            echo ""
            echo "📝 To access SHO later:"
            echo "   $full_url"
            echo ""
            echo "📋 To check status:"
            echo "   kubectl get svc $route_name -n $namespace"
            echo ""
            echo "🗑️ To remove this LoadBalancer:"
            echo "   kubectl delete svc $route_name -n $namespace"
            
            # Wait for DNS record to propagate and service to start responding
            echo ""
            echo "🔍 Checking if SHO console is responding..."
            sleep 5
            
            # Test URL accessibility before opening browser
            if test_url_accessible "$full_url" 10; then
                echo "🎉 SHO console is responding! Opening browser..."
                
                if command -v open &>/dev/null; then
                    # macOS
                    open "$full_url"
                    echo "✅ Browser opened successfully"
                    return 0
                else
                    echo "ℹ️ Could not detect a browser opener. Please open this URL manually:"
                    echo "   $full_url"
                fi
            else
                echo "⚠️  SHO console is not yet responding"
                echo "ℹ️ The LoadBalancer is ready, but the application might still be starting up"
                echo "📝 Please wait a few minutes and try accessing:"
                continue
            fi
        fi
        
        echo "   LoadBalancer not ready yet. Attempt $((attempts + 1))/$max_attempts - waiting 10 seconds..."
        sleep 10
        attempts=$((attempts + 1))
    done
      
    echo "❌ Error: LoadBalancer creation timed out after $((max_attempts * 10)) seconds"
    echo "   This might be due to:"
    echo "   - Your cloud provider is still provisioning the LoadBalancer"
    echo "   - Quota limitations in your cloud account"
    echo "   - Network policies blocking external access"
    echo ""
    echo "📋 Check status with:"
    echo "   kubectl get svc $route_name -n $namespace"
    echo "   kubectl describe svc $route_name -n $namespace"
    
    return 1
}

# Function to uninstall OutSystems Self-Hosted Operator and remove its route
uninstall_sho() {
    local release_name="${1:-self-hosted-operator}"
    local route_name="${release_name}-public"
    
    echo "⚠️  WARNING: You are about to uninstall OutSystems Self-Hosted Operator"
    echo "    This will remove the Helm release, LoadBalancer service, and the namespace"
    echo ""
    echo "    Release: $release_name"
    echo "    Namespace: $NAMESPACE"
    echo ""
    read -r -p "🚨 Are you sure you want to proceed with uninstallation? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "🛑 Uninstallation cancelled"
        return 0
    fi
    
    echo ""
    echo "🗑️ Uninstalling OutSystems Self-Hosted Operator..."
    
    # Check if the release exists
    if ! helm status "$release_name" -n "$NAMESPACE" &>/dev/null; then
        echo "❌ Error: Release $release_name not found in namespace $NAMESPACE"
        echo "   To see installed releases, run: helm list --all-namespaces"
        return 1
    fi
    
    # Check for LoadBalancer service and remove it
    echo "🔍 Checking for LoadBalancer service..."
    if kubectl get svc "$route_name" -n "$NAMESPACE" &>/dev/null; then
        echo "🗑️ Removing LoadBalancer service $route_name..."
        kubectl delete svc "$route_name" -n "$NAMESPACE"
        
        if [ $? -eq 0 ]; then
            echo "✅ LoadBalancer service successfully removed"
        else
            echo "⚠️ Failed to remove LoadBalancer service"
        fi
    else
        echo "ℹ️ No LoadBalancer service found"
    fi

    echo "Cleaning up resources..."
    kubectl get selfhostedruntimes -o name | xargs -I{} kubectl patch {} --type merge -p '{"metadata":{"finalizers":null}}' || true
	kubectl get selfhostedvaultoperators -o name | xargs -I{} kubectl patch {} --type merge -p '{"metadata":{"finalizers":null}}' || true
	kubectl delete selfhostedruntime --ignore-not-found self-hosted-runtime || true

    # Uninstall the Helm release
    echo ""
    echo "🗑️ Uninstalling SHO Helm release..."
    local uninstall_output
    uninstall_output=$(helm uninstall "$release_name" -n "$NAMESPACE" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "✅ SHO release $release_name successfully uninstalled"
        echo "Waiting for resources to cleanup..."
        sleep 30
        kubectl get vaultroles.self-hosted-vault-operator.outsystemscloud.com -o name | xargs -I{} kubectl patch {} --type merge -p '{"metadata":{"finalizers":null}}' || true
        for ns in flux-sdlc sh-registry vault istio-system outsystems-gloo-system nats-auth nats2crd outsystems-gloo-system flux-system outsystems-prometheus outsystems-rbac-manager outsystems-stakater vault-operator seaweedfs authorization-services; do \
            echo "Patching up namespace: $ns"; \
            kubectl get helmcharts,helmreleases,kustomizations,helmrepositories -n $ns -o name | \
            xargs -I{} kubectl patch {} -n $ns --type merge -p '{"metadata":{"finalizers":null}}'; \
        done
        sleep 10
        for ns in flux-sdlc nats-auth sh-registry seaweedfs outsystems-otel outsystems-fluentbit outsystems-prometheus nats-auth nats-leaf authorization-services nats2crd; do \
            echo "Cleaning up namespace: $ns"; \
            kubectl get pods -n "$ns" -o name | \
            xargs -I{} kubectl delete {} -n "$ns" --force; \
        done

        echo "🗑️ Deleting namespace $NAMESPACE..."
        kubectl delete namespace "$NAMESPACE" --wait=false && kubectl delete namespace "$NAMESPACE_CRED_JOB" --wait=false 
            
        if [ $? -eq 0 ]; then
            echo "✅ Namespace deletion initiated"
            echo "   Note: Namespace deletion might take some time to complete"
        else
            echo "❌ Failed to delete namespace"
        fi
    else
        echo "❌ Failed to uninstall SHO release"
        echo "🔍 Error details:"
        echo "$uninstall_output"
        return 1
    fi
    
    echo ""
    echo "🎉 OutSystems Self-Hosted Operator was successfully uninstalled!"
    return 0
}

# Main execution if script is run directly
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version=*)
                HELM_CHART_VERSION="${1#*=}"
                echo "📝 Using version: $HELM_CHART_VERSION"
                shift
                ;;
            --repository=*)
                CUSTOM_REPO="${1#*=}"
                CHART_REPO="$CUSTOM_REPO/$CHART_NAME"
                echo "📝 Using repository: $CUSTOM_REPO"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --uninstall)
                UNINSTALL_MODE=true
                echo "🗑️ Uninstall mode selected"
                shift
                ;;
            --env=*)
                ENV="${1#*=}"
                echo "📝 Setting current environment: $ENV"
                shift
                ;;
            --get-console-url)
                GET_CONSOLE_URL=true
                echo "🔍 Get console url operation selected."
                shift
                ;;
            *)
                echo "❌ Error: Unknown option $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done

    # Check if SHO console url is needed
    if [ "$GET_CONSOLE_URL" = true ]; then
        # Check SHO is installed
        if ! helm status "$CHART_NAME" -n "$NAMESPACE" &>/dev/null; then
            echo "❌ Error: OutSystems Self-Hosted Operator is not installed"
            echo "   Please install it first using: $0"
            exit 1
        fi
        # Get the LoadBalancer service URL
        echo "🌐 Retrieving LoadBalancer service URL for $CHART_NAME..."
        if kubectl get svc "$CHART_NAME-public" -n "$NAMESPACE" >/dev/null 2>&1; then
            route_url=$(kubectl get svc "$CHART_NAME-public" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
            if [ -z "$route_url" ]; then
                route_url=$(kubectl get svc "$CHART_NAME-public" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            fi

            if [ -n "$route_url" ]; then
                echo "✅ LoadBalancer URL: http://$route_url:5050"
                local full_url="http://${route_url}:5050"

                if test_url_accessible "$full_url" 10; then
                   echo "🎉 SHO console is responding! Opening browser..."

                   if command -v open &>/dev/null; then
                        # macOS
                        open "$full_url"
                        echo "✅ Browser opened successfully"
                    else
                        echo "ℹ️ Could not detect a browser opener. Please open this URL manually:"
                        echo "   $full_url"
                    fi
                fi
                exit 0
            else
                echo "❌ Error: LoadBalancer service URL not found. Please contact support!!!"
                exit 1    
            fi
        else
            echo "❌ Error: LoadBalancer service $CHART_NAME-public not found in namespace $NAMESPACE. Creating it now..."
            expose_sho_service "$CHART_NAME" "$NAMESPACE"
            exit 0
        fi
    fi

    if [ "$UNINSTALL_MODE" = true ]; then
        echo "🗑️ Uninstalling OutSystems Self-Hosted Operator..."
        uninstall_sho "$CHART_NAME" "$NAMESPACE"
        exit 0
    fi
    
    # Set default version if not provided
    if [ -z "$HELM_CHART_VERSION" ]; then
        echo "📝 Version not provided, checking latest version available"
        get_latest_sho_version
    fi

    # Show current configuration
    echo "=== Configuration ==="
    echo "Repository URL: ${CHART_REPO}"
    echo "Version: ${HELM_CHART_VERSION}"
    echo ""

    
    echo "=== OutSystems Self-Hosted Operator Installation Dependencies Check ==="
    check_dependencies
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🔍 Analyzing Kubernetes cluster..."
        identify_cluster
        echo ""
        echo "🚀 Ready to install SHO!"
        sho_install
        expose_sho_service "$CHART_NAME" "$NAMESPACE"
        echo ""
        echo "🎉 OutSystems Self-Hosted Operator was successfully installed!"
        echo ""
        echo "Your OutSystems Self-Hosted environment is now ready for use."
        echo "📊 Management Commands:"
        echo "   helm status $CHART_NAME -n $NAMESPACE"
        echo "   kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$release_name"
        echo ""
        echo "🗑️  To uninstall:"
        echo "   $0 --uninstall"
    else
        echo ""
        echo "💥 Please resolve dependency issues before proceeding"
        echo "💡 Run '$0 --help' for usage information"
        exit 1
    fi
fi
