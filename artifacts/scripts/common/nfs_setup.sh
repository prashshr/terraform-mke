#!/bin/bash
# NFS server + client setup for MSR4
# Called by install_msr4.sh — not meant to be run directly.
#
# Arguments:
#   $1 = NFS export path (e.g. /msr4)
#   $2 = role: "server" or "client"

set -euo pipefail

NFS_PATH="${1:-/msr4}"
ROLE="${2:-client}"

# ── OS detection ──────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="${ID}"
else
  OS_ID="unknown"
fi

# ── Package installation ──────────────────────────────────────────────────────
install_packages() {
  local pkgs_server_rhel="nfs-utils rpcbind cifs-utils"
  local pkgs_client_rhel="nfs-utils rpcbind cifs-utils"
  local pkgs_server_deb="nfs-kernel-server nfs-common rpcbind cifs-utils"
  local pkgs_client_deb="nfs-common rpcbind cifs-utils"
  local pkgs_server_sles="nfs-kernel-server rpcbind cifs-utils"
  local pkgs_client_sles="nfs-client rpcbind cifs-utils"

  local pkgs=""
  case "${ROLE}" in
    server)
      case "${OS_ID}" in
        rhel|centos|amzn|rocky|alma|fedora) pkgs="${pkgs_server_rhel}" ;;
        ubuntu|debian)                       pkgs="${pkgs_server_deb}" ;;
        sles|opensuse*)                      pkgs="${pkgs_server_sles}" ;;
        *)                                   pkgs="${pkgs_server_rhel}" ;;
      esac
      ;;
    client)
      case "${OS_ID}" in
        rhel|centos|amzn|rocky|alma|fedora) pkgs="${pkgs_client_rhel}" ;;
        ubuntu|debian)                       pkgs="${pkgs_client_deb}" ;;
        sles|opensuse*)                      pkgs="${pkgs_client_sles}" ;;
        *)                                   pkgs="${pkgs_client_rhel}" ;;
      esac
      ;;
  esac

  echo "[nfs_setup] OS=${OS_ID}  role=${ROLE}  packages=${pkgs}"

  case "${OS_ID}" in
    rhel|centos|amzn|rocky|alma|fedora)
      PKG_MGR="dnf"
      command -v dnf &>/dev/null || PKG_MGR="yum"
      sudo ${PKG_MGR} install -y ${pkgs}
      ;;
    ubuntu|debian)
      sudo apt-get update -qq
      sudo apt-get install -y ${pkgs}
      ;;
    sles|opensuse*)
      sudo zypper install -y ${pkgs}
      ;;
    *)
      if command -v dnf &>/dev/null; then
        sudo dnf install -y ${pkgs}
      elif command -v yum &>/dev/null; then
        sudo yum install -y ${pkgs}
      elif command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y ${pkgs}
      elif command -v zypper &>/dev/null; then
        sudo zypper install -y ${pkgs}
      fi
      ;;
  esac
}

# ── Verify mount helpers ──────────────────────────────────────────────────────
verify_helpers() {
  local missing=""
  for bin in mount.nfs mount.cifs; do
    local found=false
    for dir in /sbin /usr/sbin; do
      if [ -x "${dir}/${bin}" ]; then
        found=true
        break
      fi
    done
    if [ "${found}" = false ]; then
      missing="${missing} ${bin}"
    fi
  done
  if [ -n "${missing}" ]; then
    echo "[nfs_setup] ERROR: missing mount helpers:${missing}" >&2
    return 1
  fi
  echo "[nfs_setup] OK: all mount helpers present"
}

# ── Server-specific setup ─────────────────────────────────────────────────────
setup_server() {
  echo "[nfs_setup] Configuring NFS server exports..."
  sudo mkdir -p "${NFS_PATH}"
  sudo chmod 777 "${NFS_PATH}"
  sudo mkdir -p "${NFS_PATH}/postgres-data" \
               "${NFS_PATH}/trivy-data" \
               "${NFS_PATH}/jobservice-data" \
               "${NFS_PATH}/registry-data" \
               "${NFS_PATH}/redis-data"
  sudo chown -R 999:999     "${NFS_PATH}/postgres-data"
  sudo chown -R 10000:10000 "${NFS_PATH}/trivy-data"
  sudo chown -R 10000:10000 "${NFS_PATH}/jobservice-data"
  sudo chown -R 10000:10000 "${NFS_PATH}/registry-data"
  sudo chown -R 999:999     "${NFS_PATH}/redis-data"

  # Write exports file
  sudo tee /etc/exports > /dev/null <<EOF
${NFS_PATH} *(rw,sync,no_subtree_check,no_root_squash,fsid=0)
EOF
  sudo exportfs -ra

  # Enable and start the appropriate NFS service
  case "${OS_ID}" in
    rhel|centos|amzn|rocky|alma|fedora)
      sudo systemctl enable --now nfs-server
      ;;
    ubuntu|debian)
      sudo systemctl enable --now nfs-kernel-server
      ;;
    sles|opensuse*)
      sudo systemctl enable --now nfsserver
      ;;
    *)
      if command -v systemctl &>/dev/null; then
        sudo systemctl enable --now nfs-server 2>/dev/null || \
        sudo systemctl enable --now nfs-kernel-server 2>/dev/null || \
        sudo systemctl enable --now nfsserver 2>/dev/null || true
      fi
      ;;
  esac

  # SELinux tweaks (RHEL-family only)
  if command -v setsebool &>/dev/null && selinuxenabled 2>/dev/null; then
    sudo setsebool -P nfs_export_all_rw 1 2>/dev/null || true
    sudo setsebool -P use_nfs_home_dirs 1 2>/dev/null || true
    sudo restorecon -Rv "${NFS_PATH}" 2>/dev/null || true
  fi

  echo "[nfs_setup] NFS server configured and running"
}

# ── Main ──────────────────────────────────────────────────────────────────────
install_packages
verify_helpers || exit 1

if [ "${ROLE}" = "server" ]; then
  setup_server
fi

echo "[nfs_setup] Done (${ROLE})"
