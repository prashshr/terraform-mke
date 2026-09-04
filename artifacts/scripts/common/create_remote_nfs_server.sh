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

# Get local IP address
get_local_ip() {
    # Try to get the IP of the default route interface
    LOCAL_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    
    if [[ -z "$LOCAL_IP" ]]; then
        # Fallback: get first non-loopback IP
        LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    fi
    
    if [[ -z "$LOCAL_IP" ]]; then
        error "Could not determine local IP address"
        exit 1
    fi
    
    log "Local IP address: $LOCAL_IP"
}

# Enable and start service if it exists
enable_service_if_exists() {
    local service_name="$1"
    if $SUDO systemctl list-unit-files | grep -q "^${service_name}"; then
        $SUDO systemctl enable "$service_name" 2>/dev/null || warning "Could not enable $service_name"
        $SUDO systemctl start "$service_name" 2>/dev/null || warning "Could not start $service_name"
        log "Service $service_name enabled and started"
    else
        warning "Service $service_name does not exist, skipping"
    fi
}

# Install NFS packages for RHEL/CentOS
install_nfs_rhel() {
    log "Installing NFS packages for RHEL/CentOS..."
    
    # Install NFS utilities
    $SUDO yum install -y nfs-utils rpcbind cifs-utils
    
    # Enable and start core services
    $SUDO systemctl enable nfs-server
    $SUDO systemctl enable rpcbind
    
    $SUDO systemctl start rpcbind
    $SUDO systemctl start nfs-server
    
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

# Create NFS directories and set permissions
setup_nfs_directories() {
    log "Setting up NFS directories..."
    
    # Create the exported directory on the server.
    $SUDO mkdir -p /opt/nfs
    
    # Set permissions
    $SUDO chmod 777 /opt/nfs
    $SUDO chown -R nobody:nogroup /opt/nfs 2>/dev/null || $SUDO chown -R nobody:nobody /opt/nfs
    
    # Seed the export with a file clients can verify after mounting.
    $SUDO touch /opt/nfs/testfile
    
    success "NFS directories created and configured"
}

# Configure NFS exports
configure_nfs_exports() {
    log "Configuring NFS exports..."
    
    # Backup existing exports file
    if [[ -f /etc/exports ]]; then
        $SUDO cp /etc/exports /etc/exports.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Create exports configuration
    $SUDO tee /etc/exports > /dev/null << EOF
/opt/nfs *(rw,sync,no_subtree_check,no_root_squash)
EOF
    
    # Export the filesystems
    $SUDO exportfs -a
    
    # Restart NFS services based on OS
    if [[ "$OS" == "rhel" ]]; then
        $SUDO systemctl restart nfs-server
        # Restart optional services if they exist
        enable_service_if_exists "nfs-mountd"
        enable_service_if_exists "rpc-statd-notify"
        enable_service_if_exists "nfs-idmap"
    else
        $SUDO systemctl restart nfs-kernel-server
    fi
    
    success "NFS exports configured and services restarted"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    if [[ "$OS" == "rhel" ]]; then
        # RHEL/CentOS firewall configuration
        if $SUDO systemctl is-active --quiet firewalld; then
            $SUDO firewall-cmd --permanent --add-service=nfs
            $SUDO firewall-cmd --permanent --add-service=mountd
            $SUDO firewall-cmd --permanent --add-service=rpc-bind
            $SUDO firewall-cmd --reload
            success "Firewall configured for RHEL/CentOS"
        else
            warning "Firewalld is not running on RHEL/CentOS"
        fi
    else
        # Ubuntu/Debian firewall configuration
        if command -v ufw &> /dev/null && $SUDO ufw status | grep -q "Status: active"; then
            $SUDO ufw allow from any to any port nfs
            $SUDO ufw allow from any to any port 111
            $SUDO ufw allow from any to any port 2049
            success "UFW firewall configured for Ubuntu/Debian"
        else
            warning "UFW is not active on Ubuntu/Debian"
        fi
    fi
}

# Test NFS setup
test_nfs_setup() {
    log "Testing NFS setup..."
    
    # Check if NFS is exporting correctly
    if $SUDO exportfs -v | grep -q "/opt/nfs"; then
        success "NFS exports are active"
    else
        error "NFS exports are not active"
        return 1
    fi
    
    # Check if services are running
    if [[ "$OS" == "rhel" ]]; then
        $SUDO systemctl is-active --quiet nfs-server && success "NFS server is running"
    else
        $SUDO systemctl is-active --quiet nfs-kernel-server && success "NFS kernel server is running"
    fi
    
    # Show current exports
    log "Current NFS exports:"
    $SUDO exportfs -v
}

# Display final information
display_final_info() {
    echo
    echo "=========================================="
    echo -e "${GREEN}NFS Server Setup Complete!${NC}"
    echo "=========================================="
    echo
    echo -e "${BLUE}Server Information:${NC}"
    echo "  IP Address: $LOCAL_IP"
    echo "  NFS Paths:"
    echo "    /opt/nfs"
    echo
    echo -e "${BLUE}Client Mount Commands:${NC}"
    echo "  mount -t nfs $LOCAL_IP:/opt/nfs /mnt/nfs"
    echo
    echo -e "${BLUE}To test from client:${NC}"
    echo "  showmount -e $LOCAL_IP"
    echo
    echo -e "${BLUE}/etc/fstab entry example:${NC}"
    echo "  $LOCAL_IP:/opt/nfs nfs defaults 0 0"
    echo
    echo "=========================================="
}

# Main function
main() {
    log "Starting NFS server setup..."
    
    check_sudo
    detect_os
    get_local_ip
    
    if [[ "$OS" == "rhel" ]]; then
        install_nfs_rhel
    else
        install_nfs_ubuntu
    fi
    
    setup_nfs_directories
    configure_nfs_exports
    configure_firewall
    test_nfs_setup
    display_final_info
    
    success "NFS server setup completed successfully!"
}

# Run main function
main "$@"
