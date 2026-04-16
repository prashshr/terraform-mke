#!/bin/bash

# NFS Server Setup Script
# Supports RHEL/CentOS and Ubuntu/Debian systems
# Usage: ./setup_nfs_server.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if sudo is available and set SUDO variable
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
        log "Running as root"
    elif command -v sudo &> /dev/null; then
        SUDO="sudo"
        log "Running as regular user with sudo"
        # Test sudo access
        if ! $SUDO -n true 2>/dev/null; then
            log "Testing sudo access..."
            $SUDO true || {
                error "This script requires sudo privileges"
                exit 1
            }
        fi
    else
        error "This script must be run as root or with sudo available"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        log "Detected RHEL/CentOS system"
    elif [[ -f /etc/debian_version ]]; then
        OS="ubuntu"
        log "Detected Ubuntu/Debian system"
    else
        error "Unsupported operating system"
        exit 1
    fi
}



# Install NFS packages for RHEL/CentOS
install_nfs_rhel() {
    log "Installing NFS packages for RHEL/CentOS..."
    
    # Install NFS utilities
    $SUDO yum install -y nfs-utils rpcbind cifs-utils
    
    # Enable and start core services
    $SUDO systemctl enable rpcbind
    
    $SUDO systemctl start rpcbind
    
    # Enable and start optional services (may not exist on all versions)
    enable_service_if_exists "nfs-lock"
    enable_service_if_exists "nfs-idmap"
    enable_service_if_exists "nfs-mountd"
    
    success "NFS packages installed and services started on RHEL/CentOS"
}

# Install NFS packages for Ubuntu/Debian
install_nfs_ubuntu() {
    log "Installing NFS packages for Ubuntu/Debian..."
    
    # Update package list
    $SUDO apt-get update
    
    # Install NFS kernel server and utilities
    $SUDO apt-get install -y nfs-kernel-server cifs-utils nfs-common
    
    # Start and enable services
    $SUDO systemctl restart nfs-kernel-server
    
    success "NFS packages installed and services started on Ubuntu/Debian"
}


# Display final information
display_final_info() {
    echo
    echo "=========================================="
    echo -e "${GREEN}NFS Server Setup Complete!${NC}"
    echo "=========================================="

}

# Main function
main() {
    log "Starting NFS package installation..."
    
    check_sudo
    detect_os
    
    if [[ "$OS" == "rhel" ]]; then
        install_nfs_rhel
    else
        install_nfs_ubuntu
    fi

    display_final_info
    
    success "NFS package installation completed successfully!"
}

# Run main function
main "$@"
