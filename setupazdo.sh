#!/bin/bash

###################################################
# Azure DevOps Self-Hosted Agent Installation Script
# Compatible with Ubuntu, Debian, CentOS/RHEL
###################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

###################################################
# Configuration Variables
###################################################

# Azure DevOps Settings (REQUIRED)
AZDO_URL="${AZDO_URL:-}"                                    # Azure DevOps organization URL (e.g., https://dev.azure.com/yourorg)
AZDO_PAT="${AZDO_PAT:-}"                                    # Personal Access Token with Agent Pools (read, manage) scope
AZDO_POOL="${AZDO_POOL:-Default}"                           # Agent pool name
AZDO_AGENT_NAME="${AZDO_AGENT_NAME:-$(hostname)}"          # Agent name (default: hostname)

# Agent Configuration
AGENT_USER="${AGENT_USER:-azpagent}"                        # User to run the agent as
AGENT_HOME="${AGENT_HOME:-/home/$AGENT_USER}"              # Agent home directory
AGENT_DIR="${AGENT_DIR:-$AGENT_HOME/azagent}"              # Agent installation directory
AGENT_WORK_DIR="${AGENT_WORK_DIR:-$AGENT_DIR/_work}"       # Agent work directory

# Agent Options
RUN_AS_SERVICE="${RUN_AS_SERVICE:-true}"                    # Run agent as systemd service (true/false)
REPLACE_AGENT="${REPLACE_AGENT:-false}"                     # Replace existing agent with same name
ACCEPT_TEE_EULA="${ACCEPT_TEE_EULA:-y}"                     # Accept Team Explorer Everywhere license
AGENT_TAGS="${AGENT_TAGS:-}"                                # Comma-separated tags (e.g., docker,linux,production)

# Additional Tools Installation
INSTALL_DOCKER="${INSTALL_DOCKER:-true}"                    # Install Docker
INSTALL_DOTNET="${INSTALL_DOTNET:-true}"                    # Install .NET SDK
INSTALL_NODEJS="${INSTALL_NODEJS:-true}"                    # Install Node.js
INSTALL_AZURE_CLI="${INSTALL_AZURE_CLI:-true}"              # Install Azure CLI
INSTALL_KUBECTL="${INSTALL_KUBECTL:-true}"                  # Install kubectl
INSTALL_HELM="${INSTALL_HELM:-false}"                       # Install Helm
INSTALL_TERRAFORM="${INSTALL_TERRAFORM:-false}"             # Install Terraform
INSTALL_POWERSHELL="${INSTALL_POWERSHELL:-false}"           # Install PowerShell

# Version Settings
DOTNET_VERSION="${DOTNET_VERSION:-8.0}"                     # .NET SDK version
NODEJS_VERSION="${NODEJS_VERSION:-20}"                      # Node.js major version
TERRAFORM_VERSION="${TERRAFORM_VERSION:-latest}"            # Terraform version

###################################################
# Functions
###################################################

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Validate required variables
validate_config() {
    print_header "Validating Configuration"
    
    if [ -z "$AZDO_URL" ]; then
        print_error "AZDO_URL is required. Set it via environment variable or edit the script."
        print_info "Example: export AZDO_URL=https://dev.azure.com/yourorg"
        exit 1
    fi
    
    if [ -z "$AZDO_PAT" ]; then
        print_error "AZDO_PAT is required. Set it via environment variable or edit the script."
        print_info "Example: export AZDO_PAT=your_personal_access_token"
        print_info "Create PAT at: ${AZDO_URL}/_usersSettings/tokens"
        print_info "Required scopes: Agent Pools (read, manage)"
        exit 1
    fi
    
    print_success "Configuration validated"
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        print_info "Detected OS: $PRETTY_NAME"
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# Install dependencies - Ubuntu/Debian
install_dependencies_ubuntu_debian() {
    print_info "Installing dependencies for Ubuntu/Debian..."
    sudo apt-get update -y
    sudo apt-get install -y \
        curl \
        wget \
        git \
        jq \
        ca-certificates \
        apt-transport-https \
        software-properties-common \
        libicu-dev \
        build-essential
    print_success "Dependencies installed"
}

# Install dependencies - CentOS/RHEL
install_dependencies_centos_rhel() {
    print_info "Installing dependencies for CentOS/RHEL..."
    sudo yum install -y \
        curl \
        wget \
        git \
        jq \
        ca-certificates \
        libicu \
        gcc \
        gcc-c++ \
        make
    print_success "Dependencies installed"
}

# Create agent user
create_agent_user() {
    print_header "Creating Agent User"
    
    if id "$AGENT_USER" &>/dev/null; then
        print_warning "User '$AGENT_USER' already exists"
    else
        print_info "Creating user '$AGENT_USER'..."
        sudo useradd -m -d "$AGENT_HOME" -s /bin/bash "$AGENT_USER"
        print_success "User '$AGENT_USER' created"
    fi
    
    # Create agent directory
    sudo mkdir -p "$AGENT_DIR"
    sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME"
}

# Download and extract agent
download_agent() {
    print_header "Downloading Azure DevOps Agent"
    
    # Try to get latest agent version from GitHub API
    print_info "Fetching latest agent version..."
    AGENT_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name' | sed 's/v//' 2>/dev/null)
    
    # Fallback to a known working version if GitHub API fails
    if [ -z "$AGENT_VERSION" ] || [ "$AGENT_VERSION" = "null" ]; then
        print_warning "Could not fetch latest version from GitHub, using fallback version"
        AGENT_VERSION="3.243.1"
    fi
    
    print_info "Agent version: $AGENT_VERSION"
    
    AGENT_PACKAGE="vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
    
    # Try multiple download sources
    DOWNLOAD_SOURCES=(
        "https://download.agent.dev.azure.com/agent/${AGENT_VERSION}/${AGENT_PACKAGE}"
        "https://github.com/microsoft/azure-pipelines-agent/releases/download/v${AGENT_VERSION}/${AGENT_PACKAGE}"
        "https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/${AGENT_PACKAGE}"
    )
    
    DOWNLOAD_SUCCESS=false
    
    for AGENT_URL in "${DOWNLOAD_SOURCES[@]}"; do
        print_info "Attempting download from: $AGENT_URL"
        
        # Try to download as the agent user
        if sudo -u "$AGENT_USER" bash <<EOF
cd "$AGENT_DIR"
curl -L -f -o "$AGENT_PACKAGE" "$AGENT_URL" 2>/dev/null || wget -O "$AGENT_PACKAGE" "$AGENT_URL" 2>/dev/null
EOF
        then
            if [ -f "$AGENT_DIR/$AGENT_PACKAGE" ]; then
                print_success "Successfully downloaded agent"
                DOWNLOAD_SUCCESS=true
                break
            fi
        fi
        
        print_warning "Download failed, trying next source..."
    done
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        print_error "Failed to download agent from all sources"
        print_info "Please download manually from:"
        print_info "  https://github.com/microsoft/azure-pipelines-agent/releases"
        print_info "Place the file in: $AGENT_DIR"
        exit 1
    fi
    
    # Extract the agent
    print_info "Extracting agent..."
    sudo -u "$AGENT_USER" bash <<EOF
cd "$AGENT_DIR"
tar -xzf "$AGENT_PACKAGE"
rm "$AGENT_PACKAGE"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Agent extracted successfully"
    else
        print_error "Failed to extract agent package"
        exit 1
    fi
}

# Configure agent
configure_agent() {
    print_header "Configuring Azure DevOps Agent"
    
    print_info "Configuring agent '$AZDO_AGENT_NAME' in pool '$AZDO_POOL'..."
    
    # Build configuration command
    CONFIG_CMD="./config.sh --unattended --url \"$AZDO_URL\" --auth pat --token \"$AZDO_PAT\" --pool \"$AZDO_POOL\" --agent \"$AZDO_AGENT_NAME\" --work \"$AGENT_WORK_DIR\" --acceptTeeEula"
    
    if [ "$REPLACE_AGENT" = "true" ]; then
        CONFIG_CMD="$CONFIG_CMD --replace"
    fi
    
    if [ -n "$AGENT_TAGS" ]; then
        CONFIG_CMD="$CONFIG_CMD --addvirtualmachineresourcetags --virtualmachineresourcetags \"$AGENT_TAGS\""
    fi
    
    # Run configuration as agent user
    sudo -u "$AGENT_USER" bash <<EOF
cd "$AGENT_DIR"
$CONFIG_CMD
EOF
    
    print_success "Agent configured successfully"
}

# Install agent as service
install_agent_service() {
    if [ "$RUN_AS_SERVICE" = "true" ]; then
        print_header "Installing Agent as Service"
        
        print_info "Installing systemd service..."
        sudo "$AGENT_DIR/svc.sh" install "$AGENT_USER"
        
        print_info "Starting agent service..."
        sudo "$AGENT_DIR/svc.sh" start
        
        print_info "Enabling agent service on boot..."
        sudo systemctl enable azdevops-agent
        
        print_success "Agent service installed and started"
    else
        print_warning "Service installation skipped (RUN_AS_SERVICE=false)"
        print_info "To start agent manually, run: sudo -u $AGENT_USER $AGENT_DIR/run.sh"
    fi
}

# Install Docker
install_docker() {
    if [ "$INSTALL_DOCKER" = "true" ]; then
        print_header "Installing Docker"
        
        case $OS in
            ubuntu|debian)
                curl -fsSL https://get.docker.com -o get-docker.sh
                sudo sh get-docker.sh
                rm get-docker.sh
                ;;
            centos|rhel|rocky|almalinux)
                sudo yum install -y yum-utils
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo yum install -y docker-ce docker-ce-cli containerd.io
                sudo systemctl enable docker
                sudo systemctl start docker
                ;;
        esac
        
        # Add agent user to docker group
        sudo usermod -aG docker "$AGENT_USER"
        
        print_success "Docker installed"
    fi
}

# Install .NET SDK
install_dotnet() {
    if [ "$INSTALL_DOTNET" = "true" ]; then
        print_header "Installing .NET SDK $DOTNET_VERSION"
        
        case $OS in
            ubuntu|debian)
                wget https://packages.microsoft.com/config/$OS/$VER/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
                sudo dpkg -i packages-microsoft-prod.deb
                rm packages-microsoft-prod.deb
                sudo apt-get update
                sudo apt-get install -y dotnet-sdk-$DOTNET_VERSION
                ;;
            centos|rhel|rocky|almalinux)
                sudo rpm -Uvh https://packages.microsoft.com/config/centos/8/packages-microsoft-prod.rpm
                sudo yum install -y dotnet-sdk-$DOTNET_VERSION
                ;;
        esac
        
        print_success ".NET SDK $DOTNET_VERSION installed"
    fi
}

# Install Node.js
install_nodejs() {
    if [ "$INSTALL_NODEJS" = "true" ]; then
        print_header "Installing Node.js $NODEJS_VERSION"
        
        curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VERSION}.x | sudo -E bash -
        
        case $OS in
            ubuntu|debian)
                sudo apt-get install -y nodejs
                ;;
            centos|rhel|rocky|almalinux)
                sudo yum install -y nodejs
                ;;
        esac
        
        print_success "Node.js $(node --version) installed"
    fi
}

# Install Azure CLI
install_azure_cli() {
    if [ "$INSTALL_AZURE_CLI" = "true" ]; then
        print_header "Installing Azure CLI"
        
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
        
        print_success "Azure CLI $(az --version | head -n1) installed"
    fi
}

# Install kubectl
install_kubectl() {
    if [ "$INSTALL_KUBECTL" = "true" ]; then
        print_header "Installing kubectl"
        
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
        
        print_success "kubectl $(kubectl version --client --short 2>/dev/null) installed"
    fi
}

# Install Helm
install_helm() {
    if [ "$INSTALL_HELM" = "true" ]; then
        print_header "Installing Helm"
        
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        
        print_success "Helm $(helm version --short) installed"
    fi
}

# Install Terraform
install_terraform() {
    if [ "$INSTALL_TERRAFORM" = "true" ]; then
        print_header "Installing Terraform"
        
        if [ "$TERRAFORM_VERSION" = "latest" ]; then
            TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')
        fi
        
        wget "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
        sudo unzip -o "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /usr/local/bin/
        rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
        
        print_success "Terraform $(terraform --version | head -n1) installed"
    fi
}

# Install PowerShell
install_powershell() {
    if [ "$INSTALL_POWERSHELL" = "true" ]; then
        print_header "Installing PowerShell"
        
        case $OS in
            ubuntu)
                wget -q "https://packages.microsoft.com/config/ubuntu/$VER/packages-microsoft-prod.deb"
                sudo dpkg -i packages-microsoft-prod.deb
                rm packages-microsoft-prod.deb
                sudo apt-get update
                sudo apt-get install -y powershell
                ;;
            debian)
                wget https://packages.microsoft.com/config/debian/$VER/packages-microsoft-prod.deb
                sudo dpkg -i packages-microsoft-prod.deb
                rm packages-microsoft-prod.deb
                sudo apt-get update
                sudo apt-get install -y powershell
                ;;
            centos|rhel|rocky|almalinux)
                sudo rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
                sudo yum install -y powershell
                ;;
        esac
        
        print_success "PowerShell $(pwsh --version) installed"
    fi
}

# Verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    print_info "Agent configuration:"
    if [ -f "$AGENT_DIR/.agent" ]; then
        cat "$AGENT_DIR/.agent" | jq '.'
    fi
    
    print_info "Installed tools:"
    [ "$INSTALL_DOCKER" = "true" ] && docker --version 2>/dev/null || true
    [ "$INSTALL_DOTNET" = "true" ] && dotnet --version 2>/dev/null || true
    [ "$INSTALL_NODEJS" = "true" ] && node --version 2>/dev/null || true
    [ "$INSTALL_AZURE_CLI" = "true" ] && az --version 2>/dev/null | head -n1 || true
    [ "$INSTALL_KUBECTL" = "true" ] && kubectl version --client --short 2>/dev/null || true
    [ "$INSTALL_HELM" = "true" ] && helm version --short 2>/dev/null || true
    [ "$INSTALL_TERRAFORM" = "true" ] && terraform --version 2>/dev/null | head -n1 || true
    [ "$INSTALL_POWERSHELL" = "true" ] && pwsh --version 2>/dev/null || true
    
    if [ "$RUN_AS_SERVICE" = "true" ]; then
        print_info "Agent service status:"
        sudo systemctl status azdevops-agent --no-pager | head -n 10 || true
    fi
}

# Display post-installation info
display_post_install_info() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}Azure DevOps self-hosted agent has been successfully installed!${NC}\n"
    
    echo -e "${CYAN}Agent Information:${NC}"
    echo -e "  Organization: ${YELLOW}$AZDO_URL${NC}"
    echo -e "  Agent Pool:   ${YELLOW}$AZDO_POOL${NC}"
    echo -e "  Agent Name:   ${YELLOW}$AZDO_AGENT_NAME${NC}"
    echo -e "  Agent User:   ${YELLOW}$AGENT_USER${NC}"
    echo -e "  Agent Dir:    ${YELLOW}$AGENT_DIR${NC}\n"
    
    echo -e "${CYAN}Service Management:${NC}"
    if [ "$RUN_AS_SERVICE" = "true" ]; then
        echo -e "  ${YELLOW}sudo systemctl status azdevops-agent${NC}  - Check service status"
        echo -e "  ${YELLOW}sudo systemctl start azdevops-agent${NC}   - Start service"
        echo -e "  ${YELLOW}sudo systemctl stop azdevops-agent${NC}    - Stop service"
        echo -e "  ${YELLOW}sudo systemctl restart azdevops-agent${NC} - Restart service"
        echo -e "  ${YELLOW}sudo journalctl -u azdevops-agent -f${NC}  - View service logs\n"
    else
        echo -e "  ${YELLOW}sudo -u $AGENT_USER $AGENT_DIR/run.sh${NC} - Run agent interactively\n"
    fi
    
    echo -e "${CYAN}Agent Management:${NC}"
    echo -e "  View agent in Azure DevOps:"
    echo -e "  ${YELLOW}${AZDO_URL}/_settings/agentpools?poolId=$(echo $AZDO_POOL)&view=agents${NC}\n"
    
    echo -e "${CYAN}Installed Tools:${NC}"
    [ "$INSTALL_DOCKER" = "true" ] && echo -e "  ✓ Docker"
    [ "$INSTALL_DOTNET" = "true" ] && echo -e "  ✓ .NET SDK $DOTNET_VERSION"
    [ "$INSTALL_NODEJS" = "true" ] && echo -e "  ✓ Node.js $NODEJS_VERSION"
    [ "$INSTALL_AZURE_CLI" = "true" ] && echo -e "  ✓ Azure CLI"
    [ "$INSTALL_KUBECTL" = "true" ] && echo -e "  ✓ kubectl"
    [ "$INSTALL_HELM" = "true" ] && echo -e "  ✓ Helm"
    [ "$INSTALL_TERRAFORM" = "true" ] && echo -e "  ✓ Terraform"
    [ "$INSTALL_POWERSHELL" = "true" ] && echo -e "  ✓ PowerShell"
    echo ""
    
    echo -e "${CYAN}Configuration Files:${NC}"
    echo -e "  ${YELLOW}$AGENT_DIR/.agent${NC}           - Agent configuration"
    echo -e "  ${YELLOW}$AGENT_DIR/.credentials${NC}     - Agent credentials"
    echo -e "  ${YELLOW}/etc/systemd/system/azdevops-agent.service${NC} - Service file\n"
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "1. Verify agent is online in Azure DevOps"
    echo -e "2. Configure agent capabilities if needed"
    echo -e "3. Create a pipeline and assign it to the '$AZDO_POOL' pool\n"
    
    echo -e "${CYAN}Documentation:${NC}"
    echo -e "  https://docs.microsoft.com/azure/devops/pipelines/agents/linux-agent\n"
}

###################################################
# Main Execution
###################################################

main() {
    print_header "Azure DevOps Self-Hosted Agent Setup"
    echo ""
    
    # Validate configuration
    validate_config
    echo ""
    
    # Detect operating system
    detect_os
    echo ""
    
    # Install dependencies based on OS
    print_header "Installing Dependencies"
    case $OS in
        ubuntu|debian)
            install_dependencies_ubuntu_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_dependencies_centos_rhel
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    echo ""
    
    # Create agent user and directory
    create_agent_user
    echo ""
    
    # Download and extract agent
    download_agent
    echo ""
    
    # Configure agent
    configure_agent
    echo ""
    
    # Install agent as service
    install_agent_service
    echo ""
    
    # Install additional tools
    install_docker
    echo ""
    
    install_dotnet
    echo ""
    
    install_nodejs
    echo ""
    
    install_azure_cli
    echo ""
    
    install_kubectl
    echo ""
    
    install_helm
    echo ""
    
    install_terraform
    echo ""
    
    install_powershell
    echo ""
    
    # Verify installation
    verify_installation
    echo ""
    
    # Display post-installation information
    display_post_install_info
    
    print_success "Setup complete!"
}

# Run main function
main "$@"
