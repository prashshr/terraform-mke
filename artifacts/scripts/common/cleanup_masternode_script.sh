#!/bin/bash
set -euo pipefail

log() {
    echo "[$(date +'%H:%M:%S')] $1"
}

# --- Stop all services first ---
stop_services() {
    log "=== Stopping services ==="
    sudo systemctl stop docker containerd kubelet k0s 2>/dev/null || true
    sudo systemctl disable docker containerd kubelet k0s 2>/dev/null || true
}

# --- Safe process killing ---
kill_processes() {
    log "=== Killing processes ==="
    local shell_pid=$$

    # Kill by exact name (safer than -f)
    for proc in dockerd containerd kubelet k0s; do
        sudo pkill -9 -x "$proc" 2>/dev/null || true
    done

    # Kill by cgroup (excluding current shell)
    for cgroup in $(find /sys/fs/cgroup -name "*docker*" -o -name "*containerd*" -o -name "*kubelet*" -o -name "*k0s*" 2>/dev/null); do
        grep -v "^$shell_pid$" "$cgroup/cgroup.procs" 2>/dev/null | xargs -r sudo kill -9 2>/dev/null || true
    done
}

# --- Unmount filesystems ---
unmount_all() {
    log "=== Unmounting filesystems ==="
    find /var/lib/kubelet -type d -name 'volumes' -exec sudo umount -f -l {} \; 2>/dev/null || true
    find /var/lib/kubelet -type d -name 'volume-subpaths' -exec sudo umount -f -l {} \; 2>/dev/null || true
    mount | grep -E 'docker|containerd|kubelet|k0s' | awk '{print $3}' | xargs -r sudo umount -f -l 2>/dev/null || true
}

# --- Clean all files ---
clean_files() {
    log "=== Cleaning files ==="

    # k0s reset (safe if binary missing)
    if [ -x /usr/local/bin/k0s ]; then
        sudo /usr/local/bin/k0s reset --data-dir=/var/lib/k0s --kubelet-root-dir=/var/lib/kubelet 2>/dev/null || true
    fi

    # Remove k0s binary
    sudo rm -f /usr/local/bin/k0s

    # Remove Docker/containerd/k0s data directories
    sudo find \
        /etc/docker \
        /var/lib/docker \
        /var/lib/containerd \
        /var/lib/kubelet \
        /etc/containerd \
        /var/run/containerd \
        /etc/kubernetes \
        /etc/cni \
        /var/lib/cni \
        /etc/k0s \
        /var/lib/k0s \
        /var/run/k0s \
        /run/k0s \
        /var/log/k0s \
        -mindepth 1 -delete 2>/dev/null || true

    # Remove Docker socket (may be a directory on some systems)
    sudo rm -rf /var/run/docker.sock

    # Network
    sudo ip link delete docker0 2>/dev/null || true
    sudo ip link delete flannel.1 2>/dev/null || true
    sudo ip link delete cni0 2>/dev/null || true
}

# --- Remove k0s systemd service files ---
clean_systemd() {
    log "=== Cleaning systemd units ==="
    sudo rm -f /etc/systemd/system/k0s*.service
    sudo rm -rf /etc/systemd/system/k0s*.service.d
    sudo rm -f /usr/lib/systemd/system/k0s*.service
    sudo rm -f /etc/systemd/system/mke*.service
    sudo systemctl daemon-reload 2>/dev/null || true
}

# --- Uninstall packages (SELinux-safe) ---
uninstall_packages() {
    log "=== Uninstalling packages ==="

    if command -v yum &> /dev/null; then
        # Remove specific packages without wildcards
        sudo yum remove -y \
            docker \
            docker-ce \
            docker-ce-cli \
            docker-common \
            docker-engine \
            docker-client \
            docker-client-latest \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            containerd.io \
            kubelet \
            k0s 2>/dev/null || true
    elif command -v apt-get &> /dev/null; then
        sudo apt-get remove -y \
            docker \
            docker-engine \
            docker.io \
            containerd \
            runc \
            kubelet \
            k0s 2>/dev/null || true
    fi
}

# --- Main execution ---
main() {
    log "Starting cleanup..."

    stop_services
    kill_processes
    unmount_all
    clean_files
    clean_systemd
    uninstall_packages

    log "Cleanup complete! Node ${HOSTNAME} is ready."
}

main "$@"

