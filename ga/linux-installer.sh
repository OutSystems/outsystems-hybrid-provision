#!/bin/bash

set -e

# Script Configuration
SCRIPT_NAME="linux-installer.sh"
SCRIPT_VERSION="1.0.0"

# Default Configuration
NAMESPACE="self-hosted-operator"
CHART_NAME="self-hosted-operator"
IMAGE_NAME="self-hosted-operator"
DEFAULT_ENV="ga" # Default environment as per the release state. Change this value as release progress.
DEFAULT_OPERATION="install"
DEFAULT_USE_ACR="false"  # Temporary backward compatibility for Azure ACR

# Environment-specific settings
ECR_ALIAS_GA="j0s5s8b0/ga"    # GA ECR alias
ECR_ALIAS_EA="g4u4y4x2/lab"    # EA ECR alias #m5i8c6m7/ea
ECR_ALIAS_TEST="u4p0z5h7/test"  # Test ECR alias
ECR_ALIAS_DEV="g4u4y4x2/lab"  # Dev ECR alias
PUB_REGISTRY="public.ecr.aws"

# Global variables (set by parse_arguments)
SHO_VERSION=""
ENV="$DEFAULT_ENV"
OPERATION="$DEFAULT_OPERATION"
USE_ACR="$DEFAULT_USE_ACR"

# Derived configuration (set by setup_environment)
ECR_ALIAS=""
CHART_REPOSITORY=""
IMAGE_REGISTRY=""
IMAGE_REPOSITORY=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "${BLUE}🔍 $1${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - OutSystems Self-Hosted Operator for Linux

OPTIONS:
    --version=VERSION        SHO version to install/manage (default: latest)
    --env=ENVIRONMENT       Environment: test, ea, ga (default: ga)
    --operation=OPERATION   Operation: install, uninstall, get-console-url (default: install)
    --use-acr=BOOLEAN       Use ACR registry: true, false (default: false)
                           [TEMPORARY: Backward compatibility for Azure ACR]
    --help, -h              Show this help message

OPERATIONS:
    install                 Install OutSystems Self-Hosted Operator
    uninstall               Uninstall OutSystems Self-Hosted Operator  
    get-console-url         Get console URL for installed SHO

EXAMPLES:
    # Install latest version in GA environment
    ${SCRIPT_NAME}
    
    # Install specific version in EA environment
    ${SCRIPT_NAME} --operation=install --version=0.2.3 --env=ea
    
    # Get console URL for test environment
    ${SCRIPT_NAME} --operation=get-console-url --env=test
    
    # Uninstall from GA environment
    ${SCRIPT_NAME} --operation=uninstall --env=ga

EOF
}

logout_ecr_public() {
    # Remove Helm and Docker credentials for the public registry if they exist
    helm registry logout "$PUB_REGISTRY" 2>/dev/null || true
    docker logout "$PUB_REGISTRY" 2>/dev/null || true
}

# Function to validate arguments
validate_arguments() {
    log_step "Validating arguments..."
    
    # Set ENV to default if not provided
    if [[ -z "$ENV" ]]; then
        log_info "No environment specified. Using default: $DEFAULT_ENV"
        ENV="$DEFAULT_ENV"
    fi
    # Validate environment
    case "$ENV" in
        ga|ea|test|dev)
            log_success "Environment '$ENV' is valid"
            ;;
        *)
            log_error "Invalid environment: '$ENV'. Must be one of: ga, ea, test, dev"
            return 1
            ;;
    esac
    
    # Validate operation
    case "$OPERATION" in
        install|uninstall|get-console-url)
            # Temporarily disable uninstall operation
            if [[ "$OPERATION" == "uninstall" ]]; then
                log_error "The uninstall operation is currently unavailable. Please contact support for assistance with uninstallation."
                return 1
            fi
            log_success "Operation '$OPERATION' is valid"
            ;;
        *)
            log_error "Invalid operation: '$OPERATION'. Must be one of: install, uninstall, get-console-url"
            return 1
            ;;
    esac
    
    # Validate version format if provided
    if [[ -n "$SHO_VERSION" && "$SHO_VERSION" != "latest" ]]; then
        if [[ ! "$SHO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Invalid version format: '$SHO_VERSION'. Expected format: x.y.z (e.g., 0.2.3)"
            return 1
        fi
        log_success "Version '$SHO_VERSION' format is valid"
    fi
    
    # Validate ACR configuration only for install operation
    if [[ "$USE_ACR" == "true" ]]; then
        if [[ "$OPERATION" == "install" ]]; then
            log_step "Validating ACR configuration..."
            local missing_vars=()
            if [[ -z "${SP_ID}" ]]; then
                missing_vars+=("SP_ID")
            fi
            if [[ -z "${SP_SECRET}" ]]; then
                missing_vars+=("SP_SECRET")
            fi
            if [[ -z "${SH_REGISTRY}" ]]; then
                missing_vars+=("SH_REGISTRY")
            fi
            if [[ ${#missing_vars[@]} -gt 0 ]]; then
                log_error "Missing required environment variables for ACR: ${missing_vars[*]}"
                log_info "Please set the following environment variables:"
                for var in "${missing_vars[@]}"; do
                    log_info "  export $var=<value>"
                done
                return 1
            fi
            log_success "ACR configuration is valid"
        else
            log_info "Skipping ACR configuration validation (not required for operation: $OPERATION)"
        fi
    fi
    
    return 0
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version=*)
                SHO_VERSION="${1#*=}"
                log_info "Version specified: $SHO_VERSION"
                ;;
            --env=*)
                ENV="${1#*=}"
                log_info "Environment specified: $ENV"
                ;;
            --operation=*)
                OPERATION="${1#*=}"
                log_info "Operation specified: $OPERATION"
                ;;
            --use-acr=*)
                USE_ACR="${1#*=}"
                # Normalize boolean values
                case "$(echo "${USE_ACR}" | tr '[:upper:]' '[:lower:]')" in
                    true|1|yes|on)
                        USE_ACR="true"
                        log_info "ACR registry mode enabled"
                        ;;
                    false|0|no|off)
                        USE_ACR="false"
                        ;;
                    *)
                        log_error "Invalid value for --use-acr: '$USE_ACR'. Must be true or false"
                        exit 1
                        ;;
                esac
                ;;
            --use-acr)
                # Support flag without value (defaults to true for backward compatibility)
                USE_ACR="true"
                log_info "ACR registry mode enabled"
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo
                show_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Function to setup environment-specific configuration
setup_environment() {
    log_step "Setting up environment configuration for: $ENV"

    case "$ENV" in
        ga)
            ECR_ALIAS="$ECR_ALIAS_GA"
            log_info "Using GA ECR alias: $ECR_ALIAS"
            ;;
        ea)
            ECR_ALIAS="$ECR_ALIAS_EA"
            log_info "Using EA ECR alias: $ECR_ALIAS"
            ;;
        test)
            ECR_ALIAS="$ECR_ALIAS_TEST"
            log_info "Using Test ECR alias: $ECR_ALIAS"
            ;;
        dev)
            ECR_ALIAS="$ECR_ALIAS_DEV"
            log_info "Using Dev ECR alias: $ECR_ALIAS"
            ;;
        *)
            log_error "Invalid environment: '$ENV'. Must be one of: ga, ea, test, dev"
            exit 1
            ;;
    esac

    # Set repository URLs
    CHART_REPOSITORY="${ECR_ALIAS}/helm/self-hosted-operator"
    IMAGE_REGISTRY="${ECR_ALIAS}"
    IMAGE_REPOSITORY="${ECR_ALIAS}/$IMAGE_NAME"
    log_info "Using ECR repository: $PUB_REGISTRY/$CHART_REPOSITORY"

    log_success "Environment setup completed"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package using Linux package managers
install_package() {
    local package="$1"
    
    log_step "Installing $package..."
    
    if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y "$package"
    elif command_exists yum; then
        sudo yum install -y "$package"
    elif command_exists dnf; then
        sudo dnf install -y "$package"
    elif command_exists pacman; then
        sudo pacman -S --noconfirm "$package"
    elif command_exists zypper; then
        sudo zypper install -y "$package"
    else
        log_error "No supported package manager found. Please install $package manually."
        return 1
    fi
}

# Function to install kubectl
install_kubectl() {
    log_step "Installing kubectl..."
    
    # Get the latest stable version
    local version
    version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    if [[ -z "$version" ]]; then
        log_error "Failed to get kubectl version"
        return 1
    fi
    
    log_info "Downloading kubectl $version..."
    
    # Download kubectl binary for Linux
    if curl -LO "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl"; then
        chmod +x kubectl
        
        # Try to move to system PATH
        if sudo mv kubectl /usr/local/bin/ 2>/dev/null; then
            log_success "kubectl installed to /usr/local/bin/"
        elif mkdir -p ~/bin && mv kubectl ~/bin/ && export PATH="$HOME/bin:$PATH"; then
            log_success "kubectl installed to ~/bin/"
            log_info "Added ~/bin to PATH for this session"
            log_info "Add 'export PATH=\"\$HOME/bin:\$PATH\"' to your shell profile for permanent access"
        else
            log_error "Failed to install kubectl to system PATH"
            return 1
        fi
        
        # Verify installation
        if command_exists kubectl; then
            log_success "kubectl installed successfully"
            return 0
        else
            log_error "kubectl installation verification failed"
            return 1
        fi
    else
        log_error "Failed to download kubectl"
        return 1
    fi
}

# Function to install Helm
install_helm() {
    log_step "Installing Helm..."
    
    # Use official Helm installation script
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
    
    if command_exists helm; then
        log_success "Helm installed successfully"
        helm version --short
        return 0
    else
        log_error "Helm installation failed"
        return 1
    fi
}

# Function to check dependencies
check_dependencies() {
    log_step "Checking dependencies for Linux..."
    local all_deps_ok=true
    
    # Check jq
    if ! command_exists jq; then
        log_warning "jq not found. Installing..."
        if ! install_package jq; then
            all_deps_ok=false
        fi
    else
        log_success "jq is installed"
    fi
    
    # Check curl
    if ! command_exists curl; then
        log_warning "curl not found. Installing..."
        if ! install_package curl; then
            all_deps_ok=false
        fi
    else
        log_success "curl is installed"
    fi
    
    # Check kubectl
    if ! command_exists kubectl; then
        log_warning "kubectl not found. Installing..."
        if ! install_kubectl; then
            all_deps_ok=false
        fi
    else
        log_success "kubectl is installed"
    fi
    
    # Check Helm
    if ! command_exists helm; then
        log_warning "Helm not found. Installing..."
        if ! install_helm; then
            all_deps_ok=false
        fi
    else
        log_success "Helm is installed"
        helm version --short
    fi
    
    # Check Kubernetes connectivity
    log_step "Checking Kubernetes cluster connectivity..."
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Connected to Kubernetes cluster"
    else
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Make sure you have a valid kubeconfig and cluster access"
        all_deps_ok=false
    fi
    
    if [[ "$all_deps_ok" == true ]]; then
        log_success "All dependencies are satisfied"
        return 0
    else
        log_error "Some dependencies are missing or failed to install"
        return 1
    fi
}

# Function to get latest SHO version
get_latest_sho_version() {
    log_step "Fetching latest SHO version..."
    
    # Get public ECR token
    local token_json
    token_json=$(curl -sL "https://${PUB_REGISTRY}/token?scope=repository:${CHART_REPOSITORY}:pull")
    
    if [[ $? -ne 0 || -z "$token_json" ]]; then
        log_error "Failed to get ECR token"
        return 1
    fi
    
    local token
    token=$(echo "$token_json" | jq -r '.token')
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        log_error "Failed to extract token from ECR response"
        return 1
    fi
    
    # Get chart tags
    local tags_json
    tags_json=$(curl -s -H "Authorization: Bearer $token" "https://${PUB_REGISTRY}/v2/${CHART_REPOSITORY}/tags/list")
    
    if [[ $? -ne 0 || -z "$tags_json" ]]; then
        log_error "Failed to fetch chart tags"
        return 1
    fi
    
    # Find latest version (assumes semantic versioning)
    local latest_version
    latest_version=$(echo "$tags_json" | jq -r '.tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
    
    if [[ -z "$latest_version" ]]; then
        log_error "Failed to find valid chart version"
        echo "Available tags:"
        echo "$tags_json" | jq -r '.tags[]'
        return 1
    fi
    
    SHO_VERSION="$latest_version"
    log_success "Latest version found: $SHO_VERSION"
    return 0
}

# Function to install SHO
sho_install() {
    log_step "Installing OutSystems Self-Hosted Operator..."

    # Validate if self-hosted-operator namespace already exists and its not in terminating state
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        local ns_status
        ns_status=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [[ "$ns_status" == "Terminating" ]]; then
            log_error "Namespace '$NAMESPACE' is in 'Terminating' state. Please resolve this before proceeding."
            return 1
        else
            log_info "Namespace '$NAMESPACE' already exists."
        fi
    fi
    
    log_info "Installing SHO version: $SHO_VERSION"
    log_info "Environment: $ENV"
    log_info "Namespace: $NAMESPACE"
    
    # Enable OCI mode for Helm
    export HELM_EXPERIMENTAL_OCI=1

    # Logout from ECR public registry to avoid stale credentials
    logout_ecr_public
    
    # Pull chart to temp directory
    local chart_oci="oci://${PUB_REGISTRY}/${CHART_REPOSITORY}"
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
    
    log_step "Pulling chart from: $chart_oci"
    if ! helm pull "${chart_oci}" --version "${SHO_VERSION}" -d "${tmpdir}"; then
        log_error "Failed to pull Helm chart"
        return 1
    fi
    
    # Find chart file
    local chart_file="${tmpdir}/${CHART_NAME}-${SHO_VERSION}.tgz"
    if [[ ! -f "$chart_file" ]]; then
        chart_file="$(find "${tmpdir}" -maxdepth 1 -type f -name '*.tgz' | head -n1)"
    fi
    
    if [[ -z "$chart_file" || ! -f "$chart_file" ]]; then
        log_error "Could not find pulled chart package in ${tmpdir}"
        return 1
    fi
    
    log_success "Chart package ready: $chart_file"
    
    # Install/upgrade chart
    log_step "Installing/upgrading SHO in namespace $NAMESPACE..."
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local install_output
    if [[ "$USE_ACR" == "true" ]]; then
        log_info "Installing with ACR registry configuration"
        install_output=$(helm upgrade --install "${CHART_NAME}" "${chart_file}" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --set "image.registry=${PUB_REGISTRY}/${IMAGE_REGISTRY}" \
            --set "image.repository=${IMAGE_NAME}" \
            --set "image.tag=v${SHO_VERSION}" \
            --set-string "podAnnotations.timestamp=$timestamp" \
            --set "ring=$ENV" \
            --set "registry.url=${SH_REGISTRY}" \
            --set "registry.username=${SP_ID}" \
            --set "registry.password=${SP_SECRET}" \
            --set "enableECR.enabled=false" 2>&1)
    else
        install_output=$(helm upgrade --install "${CHART_NAME}" "${chart_file}" \
            --namespace "$NAMESPACE" \
            --create-namespace \
            --set "image.registry=${PUB_REGISTRY}/${IMAGE_REGISTRY}" \
            --set "image.repository=${IMAGE_NAME}" \
            --set "image.tag=v${SHO_VERSION}" \
            --set-string "podAnnotations.timestamp=$timestamp" \
            --set "ring=$ENV" 2>&1)
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "OutSystems Self-Hosted Operator installed successfully!"
        log_info "Installation details:"
        echo "$install_output"
        
        # Wait for pods to be ready
        if wait_for_pods_ready; then
            log_success "SHO is running successfully!"
            start_port_forwarding
        else
            log_warning "Installation completed but pods are not ready yet"
            show_troubleshooting_commands
            return 2  # Return special code to indicate warning
        fi
        
        return 0
    else
        log_error "Failed to install SHO"
        log_info "Error details:"
        echo "$install_output"
        return 1
    fi
}

# Function to wait for pods to be ready
wait_for_pods_ready() {
    log_step "Waiting for SHO pods to be ready..."
    
    # Disable debug output for this function to prevent variable assignments from being displayed
    local previous_debug_state
    if [[ $- == *x* ]]; then
        previous_debug_state="x"
        set +x
    fi
    
    local max_wait=300  # 5 minutes
    local check_interval=10
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local pod_info
        pod_info=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$CHART_NAME" \
            -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" \
            --no-headers 2>/dev/null)
        
        if [[ -n "$pod_info" ]]; then
            local running_pods
            running_pods=$(echo "$pod_info" | grep "Running" | grep "true" | wc -l | tr -d ' ')
            local total_pods
            total_pods=$(echo "$pod_info" | wc -l | tr -d ' ')
            
            if [[ $running_pods -gt 0 && $running_pods -eq $total_pods ]]; then
                log_success "All SHO pods are running and ready!"
                # Restore debug state if it was enabled
                [[ "$previous_debug_state" == "x" ]] && set -x
                return 0
            elif echo "$pod_info" | grep -q "Error\|CrashLoopBackOff\|ImagePullBackOff"; then
                log_error "Pod(s) in error state detected!"
                kubectl describe pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$CHART_NAME"
                # Restore debug state if it was enabled
                [[ "$previous_debug_state" == "x" ]] && set -x
                return 1
            else
                log_info "Pods still starting... ($running_pods/$total_pods ready) - waiting ${check_interval}s..."
            fi
        else
            log_info "No pods found yet... (${elapsed}s elapsed)"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log_warning "Timeout reached while waiting for pods to be ready"
    # Restore debug state if it was enabled
    [[ "$previous_debug_state" == "x" ]] && set -x
    return 1
}

# Function to start port forwarding
start_port_forwarding() {
    log_step "Setting up port forwarding..."
    
    local service_name="$CHART_NAME"
    local local_port=5050
    local service_port=5050
    
    if ! kubectl get svc "$service_name" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Service $service_name does not exist in namespace $NAMESPACE"
        return 1
    fi
    
    # Kill any existing port forwarding on the same port
    log_info "Checking for existing port forwarding on port $local_port..."
    local existing_pids
    existing_pids=$(pgrep -f "kubectl.*port-forward.*:$local_port" 2>/dev/null || true)
    
    if [[ -n "$existing_pids" ]]; then
        log_info "Stopping existing port forwarding process(es)..."
        echo "$existing_pids" | xargs kill 2>/dev/null || true
        sleep 2
    fi
    
    # Start port forwarding in background
    log_info "Starting port forwarding: localhost:$local_port -> $service_name:$service_port"
    kubectl port-forward -n "$NAMESPACE" svc/"$service_name" "$local_port:$service_port" >/dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment for port forwarding to establish
    log_info "Waiting for port forwarding to establish..."
    sleep 5
    
    local local_url="http://localhost:$local_port"
    log_success "Port forwarding established!"
    log_success "SHO Console URL: $local_url"
    
    # Test URL accessibility
    local max_attempts=12  # 60 seconds total
    local attempts=0
    local accessible=false
    
    log_step "Testing console accessibility..."
    while [[ $attempts -lt $max_attempts && "$accessible" == "false" ]]; do
        if test_url_accessible "$local_url"; then
            accessible=true
            log_success "SHO console is responding!"
            open_browser "$local_url"
            log_success "Port forwarding is running in the background (PID: $pf_pid)"
            log_info "To stop port forwarding, run: kill $pf_pid"
        else
            attempts=$((attempts + 1))
            if [[ $attempts -lt $max_attempts ]]; then
                log_info "Console not ready yet. Attempt $attempts/$max_attempts - waiting 5s..."
                sleep 5
            fi
        fi
    done
    
    if [[ "$accessible" == "false" ]]; then
        log_warning "SHO console is not yet responding"
        log_info "Please wait a few minutes and access: $local_url"
        log_info "Port forwarding is running in the background (PID: $pf_pid)"
    fi
    
    return 0
}

# Function to test URL accessibility
test_url_accessible() {
    local url="$1"
    local max_tries=5
    local try=1
    
    while [[ $try -le $max_tries ]]; do
        if curl -s -f --connect-timeout 10 --max-time 10 --head "$url" >/dev/null 2>&1; then
            return 0
        fi
        try=$((try + 1))
        sleep 5
    done
    return 1
}

# Function to open browser (Linux)
open_browser() {
    local url="$1"
    
    if command_exists xdg-open; then
        xdg-open "$url"
        log_success "Browser opened"
    else
        log_info "Please open the URL manually: $url"
    fi
}

# Function to uninstall SHO
sho_uninstall() {
    log_step "Uninstalling OutSystems Self-Hosted Operator..."
    
    local route_name="${CHART_NAME}-public"
    
    echo
    log_warning "WARNING: You are about to uninstall OutSystems Self-Hosted Operator"
    log_info "This will remove the Helm release and stop any port forwarding"
    log_info "Release: $CHART_NAME"
    log_info "Namespace: $NAMESPACE"
    echo
    read -p "Are you sure you want to proceed? (y/n): " -r confirm
    
    if [[ ! "$confirm" =~ ^(yes|y)$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
    
    # Check if release exists
    if ! helm status "$CHART_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Release $CHART_NAME not found in namespace $NAMESPACE"
        return 1
    fi
    
    # Stop any existing port forwarding processes
    log_step "Stopping port forwarding processes..."
    local pf_pids
    pf_pids=$(pgrep -f "kubectl.*port-forward" 2>/dev/null || true)
    if [[ -n "$pf_pids" ]]; then
        echo "$pf_pids" | xargs kill 2>/dev/null || true
        log_info "Port forwarding processes stopped"
    else
        log_info "No port forwarding processes found"
    fi
    
    # Clean up resources
    log_step "Cleaning up resources..."
    kubectl get selfhostedruntimes -o name 2>/dev/null | xargs -I{} kubectl patch {} --type merge -p '{"metadata":{"finalizers":null}}' || true
    kubectl get selfhostedvaultoperators -o name 2>/dev/null | xargs -I{} kubectl patch {} --type merge -p '{"metadata":{"finalizers":null}}' || true
    kubectl delete selfhostedruntime --ignore-not-found self-hosted-runtime || true
    
    # Uninstall Helm release
    log_step "Uninstalling Helm release..."
    if helm uninstall "$CHART_NAME" -n "$NAMESPACE"; then
        log_success "SHO release uninstalled successfully"
        
        # Optional: Delete namespace
        read -p "Do you want to delete the namespace '$NAMESPACE'? (y/n): " -r delete_ns
        if [[ "$delete_ns" =~ ^(yes|y)$ ]]; then
            kubectl delete namespace "$NAMESPACE" --wait=false || true
            log_info "Namespace deletion initiated"
        fi
        
        log_success "OutSystems Self-Hosted Operator uninstalled successfully!"
        return 0
    else
        log_error "Failed to uninstall SHO release"
        return 1
    fi
}

# Function to get console URL
get_console_url() {
    log_step "Getting console URL for OutSystems Self-Hosted Operator..."
    
    # Check if SHO is installed
    if ! helm status "$CHART_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "OutSystems Self-Hosted Operator is not installed"
        log_info "Please install it first using: $SCRIPT_NAME --operation=install"
        return 1
    fi
    
    # Check if pods are running
    local pods_status
    pods_status=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name="$CHART_NAME" -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
    if [[ "$pods_status" != *"Running"* ]]; then
        log_error "SHO pods are not running"
        log_info "Please ensure the SHO installation is healthy"
        return 1
    fi
    log_success "SHO is installed and pods are running"
    # Start new port forwarding
    log_info "Starting port forwarding..."
    start_port_forwarding
}

# Function to show troubleshooting commands
show_troubleshooting_commands() {
    cat << EOF

🛠️  Troubleshooting Commands:

📊 Check pod status:
   kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME

📋 Describe pods:
   kubectl describe pods -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME

📝 View pod logs:
   kubectl logs -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME --tail=50

📋 Check events:
   kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp

⚡ Check helm status:
   helm status $CHART_NAME -n $NAMESPACE

🔄 Restart deployment:
   kubectl rollout restart deployment -n $NAMESPACE -l app.kubernetes.io/instance=$CHART_NAME

EOF
}

# Function to show configuration summary
show_configuration() {
    echo ""
    echo "=== Configuration Summary ==="
    echo "Script Version: $SCRIPT_VERSION"
    echo "Platform:       macOS"
    echo "Operation:      $OPERATION"
    echo "Environment:    $ENV"
    if [[ "$OPERATION" == "install" ]]; then
        echo "Version:        ${SHO_VERSION:-latest}"
        echo "Use ACR:        $USE_ACR"
    fi
    echo "Namespace:      $NAMESPACE"
    echo "Chart Name:     $CHART_NAME"
    echo "Repository:     $PUB_REGISTRY/$CHART_REPOSITORY"
    echo "Image Registry: $PUB_REGISTRY/$IMAGE_REGISTRY"
    echo ""
}

# Main function
main() {
    echo "🐧 OutSystems Self-Hosted Operator Linux Installer v${SCRIPT_VERSION}"
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate arguments
    if ! validate_arguments; then
        exit 1
    fi
    
    # Setup environment
    setup_environment

    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed. Please resolve issues and try again."
        exit 1
    fi
    
    # For install operation, get version if not specified before showing configuration
    if [[ "$OPERATION" == "install" ]]; then
        if [[ -z "$SHO_VERSION" || "$SHO_VERSION" == "latest" ]]; then
            if ! get_latest_sho_version; then
                log_error "Failed to fetch latest SHO version"
                return 1
            fi
        fi
    fi
    
    # Show configuration
    show_configuration
    
    # Execute operation
    case "$OPERATION" in
        install)
            sho_install
            ;;
        uninstall)
            sho_uninstall
            ;;
        get-console-url)
            get_console_url
            ;;
        *)
            log_error "Unknown operation: $OPERATION"
            exit 1
            ;;
    esac
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Operation '$OPERATION' completed successfully!"
    elif [[ $exit_code -eq 2 ]]; then
        log_warning "Operation '$OPERATION' completed with warning!"
        exit_code=0  # Still exit successfully for automation
    else
        log_error "Operation '$OPERATION' failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

# Run main function if script is executed directly or piped to shell
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]]; then
    main "$@"
fi
