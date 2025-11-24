#!/bin/bash

#########################################
# Docker Installation Script for Linux VM
# Compatible with Ubuntu, Debian, CentOS/RHEL
#########################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#########################################
# Configuration Variables
#########################################

DOCKER_USER="${DOCKER_USER:-azureuser}"              # User to add to docker group
INSTALL_DOCKER_COMPOSE="${INSTALL_COMPOSE:-true}"    # Install Docker Compose (true/false)
COMPOSE_VERSION="${COMPOSE_VERSION:-latest}"         # Docker Compose version (latest or specific version like 2.24.0)
ENABLE_DOCKER_SERVICE="${ENABLE_SERVICE:-true}"      # Enable Docker service to start on boot
START_DOCKER_NOW="${START_NOW:-true}"                # Start Docker service immediately
INSTALL_DOCKER_BUILDX="${INSTALL_BUILDX:-true}"      # Install Docker Buildx plugin
CONFIGURE_LOGGING="${CONFIGURE_LOGGING:-true}"       # Configure Docker logging driver
LOG_DRIVER="${LOG_DRIVER:-json-file}"                # Logging driver (json-file, syslog, journald, etc.)
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10m}"                  # Max log file size
LOG_MAX_FILE="${LOG_MAX_FILE:-3}"                    # Max number of log files
INSTALL_DOCKER_SCAN="${INSTALL_SCAN:-false}"         # Install Docker Scan (Snyk)

#########################################
# Functions
#########################################

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

# Install Docker on Ubuntu/Debian
install_docker_ubuntu_debian() {
    print_header "Installing Docker on Ubuntu/Debian"
    
    # Update package index
    print_info "Updating package index..."
    sudo apt-get update -y
    
    # Install prerequisites
    print_info "Installing prerequisites..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
    
    # Add Docker's official GPG key
    print_info "Adding Docker's GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up Docker repository
    print_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    sudo apt-get update -y
    
    # Install Docker Engine
    print_info "Installing Docker Engine..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_success "Docker installed successfully on Ubuntu/Debian"
}

# Install Docker on CentOS/RHEL
install_docker_centos_rhel() {
    print_header "Installing Docker on CentOS/RHEL"
    
    # Remove old versions
    print_info "Removing old Docker versions (if any)..."
    sudo yum remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine \
        podman \
        runc 2>/dev/null || true
    
    # Install prerequisites
    print_info "Installing prerequisites..."
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # Add Docker repository
    print_info "Adding Docker repository..."
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine
    print_info "Installing Docker Engine..."
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_success "Docker installed successfully on CentOS/RHEL"
}

# Configure Docker daemon
configure_docker() {
    if [ "$CONFIGURE_LOGGING" = "true" ]; then
        print_header "Configuring Docker Daemon"
        
        print_info "Creating Docker daemon configuration..."
        sudo mkdir -p /etc/docker
        
        cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "log-driver": "$LOG_DRIVER",
  "log-opts": {
    "max-size": "$LOG_MAX_SIZE",
    "max-file": "$LOG_MAX_FILE"
  },
  "storage-driver": "overlay2"
}
EOF
        
        print_success "Docker daemon configured"
    fi
}

# Add user to docker group
add_user_to_docker_group() {
    print_header "Configuring Docker Permissions"
    
    if id "$DOCKER_USER" &>/dev/null; then
        print_info "Adding user '$DOCKER_USER' to docker group..."
        sudo usermod -aG docker $DOCKER_USER
        print_success "User '$DOCKER_USER' added to docker group"
        print_warning "Note: User needs to log out and back in for group changes to take effect"
        print_info "Or run: newgrp docker"
    else
        print_warning "User '$DOCKER_USER' does not exist. Skipping group assignment."
    fi
}

# Enable and start Docker service
manage_docker_service() {
    print_header "Managing Docker Service"
    
    if [ "$ENABLE_DOCKER_SERVICE" = "true" ]; then
        print_info "Enabling Docker service to start on boot..."
        sudo systemctl enable docker
        print_success "Docker service enabled"
    fi
    
    if [ "$START_DOCKER_NOW" = "true" ]; then
        print_info "Starting Docker service..."
        sudo systemctl start docker
        print_success "Docker service started"
    fi
    
    # Check Docker service status
    print_info "Docker service status:"
    sudo systemctl status docker --no-pager | head -n 5 || true
}

# Install Docker Compose (standalone - legacy)
install_docker_compose_standalone() {
    if [ "$INSTALL_DOCKER_COMPOSE" = "true" ]; then
        print_header "Installing Docker Compose (Standalone)"
        
        if [ "$COMPOSE_VERSION" = "latest" ]; then
            print_info "Fetching latest Docker Compose version..."
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
            print_info "Latest version: $COMPOSE_VERSION"
        fi
        
        print_info "Downloading Docker Compose $COMPOSE_VERSION..."
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        
        sudo chmod +x /usr/local/bin/docker-compose
        
        # Create symbolic link
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
        
        print_success "Docker Compose installed"
    fi
}

# Verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    # Check Docker version
    print_info "Docker version:"
    docker --version
    
    # Check Docker Compose version (plugin)
    print_info "Docker Compose (plugin) version:"
    docker compose version 2>/dev/null || print_warning "Docker Compose plugin not installed"
    
    # Check Docker Compose version (standalone)
    if [ -f /usr/local/bin/docker-compose ]; then
        print_info "Docker Compose (standalone) version:"
        docker-compose --version 2>/dev/null || true
    fi
    
    # Check Docker service status
    print_info "Docker service status:"
    sudo systemctl is-active docker
    
    # Run test container (if Docker is running)
    if sudo systemctl is-active docker &>/dev/null; then
        print_info "Running test container..."
        if sudo docker run --rm hello-world &>/dev/null; then
            print_success "Docker is working correctly!"
        else
            print_warning "Docker test container failed"
        fi
    fi
}

# Cleanup
cleanup() {
    print_header "Cleanup"
    
    # Remove test images
    print_info "Removing test images..."
    sudo docker rmi hello-world 2>/dev/null || true
    
    print_success "Cleanup complete"
}

# Display post-installation info
display_post_install_info() {
    print_header "Post-Installation Information"
    
    echo -e "${GREEN}Docker has been successfully installed!${NC}\n"
    
    echo -e "${CYAN}Important Notes:${NC}"
    echo -e "1. User '$DOCKER_USER' has been added to the docker group"
    echo -e "2. Log out and back in for group changes to take effect"
    echo -e "3. Or run: ${YELLOW}newgrp docker${NC} to activate group in current session\n"
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${YELLOW}docker --version${NC}              - Check Docker version"
    echo -e "  ${YELLOW}docker ps${NC}                     - List running containers"
    echo -e "  ${YELLOW}docker ps -a${NC}                  - List all containers"
    echo -e "  ${YELLOW}docker images${NC}                 - List images"
    echo -e "  ${YELLOW}docker compose version${NC}        - Check Docker Compose version"
    echo -e "  ${YELLOW}sudo systemctl status docker${NC}  - Check Docker service status"
    echo -e "  ${YELLOW}sudo systemctl restart docker${NC} - Restart Docker service"
    echo -e "  ${YELLOW}docker run hello-world${NC}        - Test Docker installation\n"
    
    echo -e "${CYAN}Configuration Files:${NC}"
    echo -e "  ${YELLOW}/etc/docker/daemon.json${NC}      - Docker daemon configuration"
    echo -e "  ${YELLOW}/var/lib/docker/${NC}             - Docker data directory\n"
    
    echo -e "${CYAN}Documentation:${NC}"
    echo -e "  https://docs.docker.com/\n"
}

#########################################
# Main Execution
#########################################

main() {
    print_header "Docker Installation Script"
    echo ""
    
    # Detect operating system
    detect_os
    echo ""
    
    # Install Docker based on OS
    case $OS in
        ubuntu|debian)
            install_docker_ubuntu_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_docker_centos_rhel
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    echo ""
    
    # Configure Docker daemon
    configure_docker
    echo ""
    
    # Add user to docker group
    add_user_to_docker_group
    echo ""
    
    # Enable and start Docker service
    manage_docker_service
    echo ""
    
    # Install Docker Compose standalone (optional)
    # Uncomment if you need standalone docker-compose
    # install_docker_compose_standalone
    # echo ""
    
    # Verify installation
    verify_installation
    echo ""
    
    # Cleanup
    cleanup
    echo ""
    
    # Display post-installation information
    display_post_install_info
    
    print_success "Installation complete!"
}

# Run main function
main "$@"
