#!/bin/bash
# MSR4 Installation Script
#
# Installs Mirantis Secure Registry v4 on a MKE cluster via Helm,
# supporting both single-replica (default) and high-availability modes.
#
# Usage: ./install_msr4.sh [options]
#
# Options:
#   --ha                    Enable HA mode (external PostgreSQL + Redis with Sentinel)
#   --msr-version <ver>     MSR Helm chart version (default: ${MSR4_VERSION})
#   --domain <fqdn>         FQDN for MSR4 UI (default: \$MSR4_DOMAIN or msr4.<root_domain>)
#   --namespace <ns>        Kubernetes namespace (default: msr4)
#   --nfs-node <host>       NFS server hostname/IP (HA mode, default: auto-detect)
#   --nfs-path <path>       NFS export path (HA mode, default: /msr4)
#   --http-node-port <p>    NodePort for HTTP (default: 34002)
#   --https-node-port <p>   NodePort for HTTPS (default: 34003)
#   --helm-username <u>     Mirantis registry Helm username
#   --helm-password <p>     Mirantis registry Helm password
#   --ssh-key <path>        SSH key for NFS node access (default: auto-detect)
#   --ssh-user <user>       SSH user for NFS node (default: ec2-user)
#   --values <file>         Custom Helm values file (merged on top of defaults)
#   --yes                   Skip confirmation prompts
#   --help                  Show this help
#
# Environment variables:
#   MSR4_DOMAIN              Domain for MSR4 UI (overrides terraform output)
#   MSR4_HELM_USERNAME       Mirantis registry username
#   MSR4_HELM_PASSWORD       Mirantis registry password
#   MSR4_NFS_NODE            NFS server node (overrides auto-detect)
#   MSR4_SSH_KEY             SSH key path
#   MSR4_STORAGE_CLASS       Storage class (default: nfs-storage)
#   MSR4_PG_HOST             External PostgreSQL host (HA mode)
#   MSR4_PG_PORT             External PostgreSQL port (HA mode, default: 5432)
#   MSR4_REDIS_ADDR          External Redis/Sentinel address (HA mode)
#   MSR4_SENTINEL_MASTER_SET Redis Sentinel master set name (HA mode, default: mymaster)
#   CUSTOM_VALUES            Path to custom Helm values file (same as --values)
#   KUBECONFIG               Path to kubeconfig file
#   DEBUG                    Set to any value to enable debug output
#
# Makefile variables (make msr4 MSR4_HA=true ...):
#   MSR4_HA                  Set to "true" for HA mode
#   MSR4_VERSION             MSR version (default: 4.13.5)
#   MSR4_DOMAIN              Domain for MSR4 UI
#   MSR4_HTTP_NODE_PORT      HTTP NodePort (default: 34002)
#   MSR4_HTTPS_NODE_PORT     HTTPS NodePort (default: 34003)
#   MSR4_NFS_NODE            NFS server node
#   MSR4_NFS_PATH            NFS export path (default: /msr4)
#   MSR4_SSH_KEY             SSH key path
#   MSR4_HELM_USERNAME       Mirantis registry username
#   MSR4_HELM_PASSWORD       Mirantis registry password
#   MSR4_YES                 Set to "true" to skip confirmation prompts
#   CUSTOM_VALUES            Custom Helm values file path
#
# Examples:
#   ./install_msr4.sh                                    # single-replica, interactive
#   ./install_msr4.sh --ha                                # HA mode
#   ./install_msr4.sh --ha --msr-version 4.13.4          # specific version
#   ./install_msr4.sh --domain msr4.mycompany.com        # custom domain
#   ./install_msr4.sh --ha --nfs-node 10.0.0.5           # specify NFS node
#   make msr4 MSR4_HA=true                               # HA mode via Makefile
#   make msr4 MSR4_VERSION=4.13.4                        # specific version via Makefile
#   make msr4 MSR4_YES=true                              # skip confirmation prompts

set -euo pipefail

# Enable debug mode if DEBUG env is set
if [ -n "${DEBUG:-}" ]; then
  set -x
fi

# ==============================================================================
# Configuration & Defaults
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ARTIFACTS_DIR="${PROJECT_ROOT}/artifacts"
MSR_DIR="${ARTIFACTS_DIR}/configs/msr4"
VALUES_DIR="${MSR_DIR}/values"
MANIFESTS_DIR="${MSR_DIR}/manifests"
SSH_DIR="${ARTIFACTS_DIR}/ssh"
TLS_DIR="${ARTIFACTS_DIR}/tlscerts"
COMMON_SCRIPTS_DIR="${ARTIFACTS_DIR}/scripts/common"
NFS_SETUP_SCRIPT="${COMMON_SCRIPTS_DIR}/nfs_setup.sh"

HA_MODE=false
MSR4_VERSION="4.13.5"
DOMAIN=""
NAMESPACE="msr4"
NFS_NODE=""
NFS_PATH="/msr4"
HTTP_NODE_PORT=34002
HTTPS_NODE_PORT=34003
HELM_USERNAME=""
HELM_PASSWORD=""
SSH_KEY=""
SSH_USER="ec2-user"
SKIP_CONFIRM=false
CUSTOM_VALUES=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug() { if [ -n "${DEBUG:-}" ]; then echo -e "[DEBUG] $*"; fi; }

die() {
  log_error "$*"
  exit 1
}

confirm() {
  if [ "${SKIP_CONFIRM}" = true ]; then
    return 0
  fi
  read -r -p "$1 [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

run_step() {
  local step_name="$1"
  echo ""
  echo "=== ${step_name} ==="
}

wait_for_pods() {
  local label="$1"
  local ns="$2"
  local timeout="$3"
  local desc="$4"

  echo "Waiting for ${desc} pods to be ready (timeout: ${timeout}s)..."
  log_debug "Kubectl wait command: kubectl wait --for=condition=ready pod -l \"${label}\" -n \"${ns}\" --timeout=\"${timeout}s\""
  if kubectl wait --for=condition=ready pod -l "${label}" -n "${ns}" --timeout="${timeout}s" 2>/dev/null; then
    log_ok "${desc} pods are ready"
  else
    log_warn "Timed out waiting for ${desc} pods. Checking current state..."
    log_debug "Current pods with label ${label}:"
    kubectl get pods -l "${label}" -n "${ns}" -o wide 2>/dev/null || true
  fi
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --ha                    Enable HA mode (external PostgreSQL + Redis with Sentinel)"
  echo "  --msr-version <ver>     MSR Helm chart version (default: ${MSR4_VERSION})"
  echo "  --domain <fqdn>         FQDN for MSR4 UI"
  echo "  --namespace <ns>        Kubernetes namespace (default: ${NAMESPACE})"
  echo "  --nfs-node <host>       NFS server hostname/IP (default: auto-detect)"
  echo "  --nfs-path <path>       NFS export path (default: ${NFS_PATH})"
  echo "  --http-node-port <p>    NodePort for HTTP (default: ${HTTP_NODE_PORT})"
  echo "  --https-node-port <p>   NodePort for HTTPS (default: ${HTTPS_NODE_PORT})"
  echo "  --helm-username <u>     Mirantis registry Helm username"
  echo "  --helm-password <p>     Mirantis registry Helm password"
  echo "  --ssh-key <path>        SSH key for NFS node access"
  echo "  --ssh-user <user>       SSH user for NFS node (default: ${SSH_USER})"
  echo "  --values <file>         Custom Helm values file (merged on top of defaults)"
  echo "  --yes                   Skip confirmation prompts"
  echo "  --help                  Show this help"
  echo ""
  echo "Environment variables:"
  echo "  MSR4_DOMAIN              Domain for MSR4 UI (overrides terraform output)"
  echo "  MSR4_HELM_USERNAME       Mirantis registry username"
  echo "  MSR4_HELM_PASSWORD       Mirantis registry password"
  echo "  MSR4_NFS_NODE            NFS server node (overrides auto-detect)"
  echo "  MSR4_SSH_KEY             SSH key path"
  echo "  MSR4_STORAGE_CLASS       Storage class (default: nfs-storage)"
  echo "  MSR4_PG_HOST             External PostgreSQL host (HA mode)"
  echo "  MSR4_PG_PORT             External PostgreSQL port (HA mode, default: 5432)"
  echo "  MSR4_REDIS_ADDR          External Redis/Sentinel address (HA mode)"
  echo "  MSR4_SENTINEL_MASTER_SET Redis Sentinel master set (HA mode, default: mymaster)"
  echo "  CUSTOM_VALUES            Path to custom Helm values file (same as --values)"
  echo "  KUBECONFIG               Path to kubeconfig file"
  echo "  DEBUG                    Set to any value to enable debug output"
  echo ""
  echo "Makefile variables (make msr4 MSR4_HA=true ...):"
  echo "  MSR4_HA                  Set to 'true' for HA mode"
  echo "  MSR4_VERSION             MSR version (default: ${MSR4_VERSION})"
  echo "  MSR4_DOMAIN              Domain for MSR4 UI"
  echo "  MSR4_HTTP_NODE_PORT      HTTP NodePort (default: ${HTTP_NODE_PORT})"
  echo "  MSR4_HTTPS_NODE_PORT     HTTPS NodePort (default: ${HTTPS_NODE_PORT})"
  echo "  MSR4_NFS_NODE            NFS server node"
  echo "  MSR4_NFS_PATH            NFS export path (default: ${NFS_PATH})"
  echo "  MSR4_SSH_KEY             SSH key path"
  echo "  MSR4_HELM_USERNAME       Mirantis registry username"
  echo "  MSR4_HELM_PASSWORD       Mirantis registry password"
  echo "  MSR4_YES                 Set to 'true' to skip confirmation prompts"
  echo "  CUSTOM_VALUES            Custom Helm values file path"
  echo ""
  echo "Examples:"
  echo "  $0                                    # single-replica, interactive"
  echo "  $0 --ha                                # HA mode"
  echo "  $0 --ha --msr-version 4.13.4          # specific version"
  echo "  $0 --domain msr4.mycompany.com        # custom domain"
  echo "  $0 --ha --nfs-node 10.0.0.5           # specify NFS node"
  echo "  make msr4 MSR4_HA=true                # HA mode via Makefile"
  echo "  make msr4 MSR4_VERSION=4.13.4         # specific version via Makefile"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ha)               HA_MODE=true; shift ;;
    --msr-version)      MSR4_VERSION="$2"; shift 2 ;;
    --domain)           DOMAIN="$2"; shift 2 ;;
    --namespace)        NAMESPACE="$2"; shift 2 ;;
    --nfs-node)         NFS_NODE="$2"; shift 2 ;;
    --nfs-path)         NFS_PATH="$2"; shift 2 ;;
    --http-node-port)   HTTP_NODE_PORT="$2"; shift 2 ;;
    --https-node-port)  HTTPS_NODE_PORT="$2"; shift 2 ;;
    --helm-username)    HELM_USERNAME="$2"; shift 2 ;;
    --helm-password)    HELM_PASSWORD="$2"; shift 2 ;;
    --ssh-key)          SSH_KEY="$2"; shift 2 ;;
    --ssh-user)         SSH_USER="$2"; shift 2 ;;
    --values)           CUSTOM_VALUES="$2"; shift 2 ;;
    --yes)              SKIP_CONFIRM=true; shift ;;
    --help)             usage ;;
    *)                  die "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ==============================================================================
# Pre-flight Checks
# ==============================================================================

echo ""
echo "============================================================"
echo " MSR4 Installation Script"
echo " Mode:       $([ "${HA_MODE}" = true ] && echo "HA (High Availability)" || echo "Single-Replica")"
echo " Version:    ${MSR4_VERSION}"
echo " Namespace:  ${NAMESPACE}"
echo "============================================================"
echo ""

# Check prerequisites
command -v kubectl &>/dev/null || die "kubectl is required but not found"
command -v helm &>/dev/null || die "helm is required but not found"
command -v yq &>/dev/null || die "yq is required but not found. Install with: pip install yq or snap install yq"
command -v openssl &>/dev/null || die "openssl is required but not found"

# Check KUBECONFIG
if [ -z "${KUBECONFIG:-}" ]; then
  log_warn "KUBECONFIG is not set. Attempting to detect..."
  if [ -f "${PROJECT_ROOT}/artifacts/configs/kubeconfig.yaml" ]; then
    export KUBECONFIG="${PROJECT_ROOT}/artifacts/configs/kubeconfig.yaml"
    log_ok "Using KUBECONFIG from artifacts/configs/kubeconfig.yaml"
  elif [ -f "${HOME}/.mke/mke.kubeconf" ]; then
    export KUBECONFIG="${HOME}/.mke/mke.kubeconf"
    log_ok "Using KUBECONFIG from ~/.mke/mke.kubeconf"
  else
    die "KUBECONFIG not set and no kubeconfig found in artifacts/configs/ or ~/.mke/"
  fi
fi

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
  die "Cannot connect to Kubernetes cluster. Check KUBECONFIG and cluster state."
fi
log_ok "Kubernetes cluster is reachable"

# Check Helm version (need 3.8+)
HELM_VERSION=$(helm version --short 2>/dev/null | grep -Eo 'v[0-9]+' | head -1 | tr -d 'v')
if [ -n "${HELM_VERSION}" ] && [ "${HELM_VERSION}" -lt 3 ]; then
  die "Helm 3.8+ is required. Current: $(helm version --short)"
fi
log_ok "Helm version: $(helm version --short)"

# ==============================================================================
# Domain Resolution
# ==============================================================================

resolve_domain() {
  # Priority: 1) --domain flag  2) MSR4_DOMAIN env  3) Terraform root_domain output
  if [ -n "${DOMAIN}" ]; then
    log_ok "Domain set via --domain flag: ${DOMAIN}"
    return
  fi

  if [ -n "${MSR4_DOMAIN:-}" ]; then
    DOMAIN="${MSR4_DOMAIN}"
    log_ok "Domain set via MSR4_DOMAIN env: ${DOMAIN}"
    return
  fi

  # Try Terraform output (requires existing state)
  if command -v terraform &>/dev/null; then
    local ROOT_DOMAIN
    ROOT_DOMAIN=$(terraform -chdir="${PROJECT_ROOT}" output -raw root_domain 2>/dev/null || true)
    if [ -n "${ROOT_DOMAIN}" ]; then
      DOMAIN="msr4.${ROOT_DOMAIN}"
      log_ok "Domain derived from Terraform root_domain: ${DOMAIN}"
      return
    fi
  fi

  # Fallback: parse root_domain default from variables.tf
  if [ -f "${PROJECT_ROOT}/variables.tf" ]; then
    local ROOT_DOMAIN
    ROOT_DOMAIN=$(grep -A5 'variable "root_domain"' "${PROJECT_ROOT}/variables.tf" 2>/dev/null | grep 'default' | sed 's/.*"\(.*\)".*/\1/' || true)
    if [ -n "${ROOT_DOMAIN}" ]; then
      DOMAIN="msr4.${ROOT_DOMAIN}"
      log_ok "Domain derived from variables.tf root_domain default: ${DOMAIN}"
      return
    fi
  fi

  # Ultimate fallback: assume standard pattern
  DOMAIN="msr4.samkhya.cloud"
  log_warn "Could not determine domain from terraform. Using fallback: ${DOMAIN}"
}

resolve_domain

get_worker_public_ip() {
  local launchpad_yaml="${PROJECT_ROOT}/artifacts/configs/launchpad.yaml"

  if [ ! -f "${launchpad_yaml}" ]; then
    log_debug "Launchpad config not found at ${launchpad_yaml}"
    return 0
  fi

  python3 -c "
import yaml, sys

with open('${launchpad_yaml}') as f:
    data = yaml.safe_load(f)

hosts = data.get('spec', {}).get('hosts', [])

# Prefer msr role, then worker, then manager
for role in ('msr', 'worker', 'manager'):
    for host in hosts:
        if host.get('role') == role:
            addr = host.get('ssh', {}).get('address')
            if addr:
                print(addr)
                sys.exit(0)
" 2>/dev/null || true
}

# ==============================================================================
# Detect SSH Key
# ==============================================================================

if [ -z "${SSH_KEY}" ]; then
  if [ -n "${MSR4_SSH_KEY:-}" ]; then
    SSH_KEY="${MSR4_SSH_KEY}"
  elif [ -d "${SSH_DIR}" ]; then
    SSH_KEY=$(find "${SSH_DIR}" -name '*.pem' | head -1 || true)
  fi
fi

# ==============================================================================
# Summary & Confirmation
# ==============================================================================

echo ""
echo "--- Installation Summary ---"
echo "  Mode:           $([ "${HA_MODE}" = true ] && echo "HA" || echo "Single")"
echo "  MSR Version:    ${MSR4_VERSION}"
echo "  Domain:         ${DOMAIN}"
echo "  Namespace:      ${NAMESPACE}"
echo "  HTTP NodePort:  ${HTTP_NODE_PORT}"
echo "  HTTPS NodePort: ${HTTPS_NODE_PORT}"
echo "  NFS Node:       ${NFS_NODE:-<auto-detect>}"
echo "  NFS Path:       ${NFS_PATH}"
echo ""

confirm "Proceed with MSR4 installation?" || die "Installation cancelled by user"

# ==============================================================================
# STEP 0: Create Namespace
# ==============================================================================

run_step "Step 1: Creating namespace"
log_debug "Applying namespace '${NAMESPACE}' (dry-run: client, then apply)"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
log_debug "Namespace manifest applied, checking readiness..."
kubectl get namespace "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Active && log_debug "Namespace phase: Active"
log_ok "Namespace '${NAMESPACE}' ready"

# ==============================================================================
# STEP 2: Prepare MKE Nodes
# ==============================================================================

run_step "Step 2: Preparing MKE nodes"

# Get MSR nodes (prefer nodes with msr role, fallback to workers)
log_debug "Querying nodes with msr role..."
MSR_NODES=$(kubectl get nodes -l node-role.kubernetes.io/msr=true -o name 2>/dev/null || true)
log_debug "MSR role nodes found: $(echo ${MSR_NODES} | wc -w)"
if [ -z "${MSR_NODES}" ]; then
  log_warn "No nodes with msr role found. Using first 3 worker nodes..."
  MSR_NODES=$(kubectl get nodes -l node-role.kubernetes.io/worker=true -o name 2>/dev/null | head -3 || true)
  log_debug "Worker nodes selected: $(echo ${MSR_NODES} | wc -w)"
fi
if [ -z "${MSR_NODES}" ]; then
  MSR_NODES=$(kubectl get nodes -o name | head -3)
  log_debug "Falling back to first 3 nodes: $(echo ${MSR_NODES})"
fi

for NODE in ${MSR_NODES}; do
  NODE_NAME=$(echo "${NODE}" | sed 's|node/||')
  log_info "Labeling node ${NODE_NAME} with msr4=true"
  if kubectl label node "${NODE_NAME}" msr4=true --overwrite 2>&1; then
    log_debug "Node ${NODE_NAME} labeled successfully"
  else
    log_warn "Could not label ${NODE_NAME} (MKE RBAC may restrict labeling). Continuing with node name as-is."
  fi
done
log_ok "MSR4 nodes labeled"

# ==============================================================================
# STEP 3: Storage Setup — NFS
# ==============================================================================

run_step "Step 3: Storage setup — NFS"

# Check if dedicated NFS server exists in terraform outputs
TF_NFS_PRIV=$(terraform -chdir="${PROJECT_ROOT}" output -raw nfs_private_ip 2>/dev/null || true)
TF_NFS_PUB=$(terraform -chdir="${PROJECT_ROOT}" output -raw nfs_public_ip 2>/dev/null || true)

if [ -n "${TF_NFS_PRIV}" ] && [ "${TF_NFS_PRIV}" != "null" ]; then
  NFS_NODE="dedicated-nfs"
  NFS_NODE_INTERNAL_IP="${TF_NFS_PRIV}"
  NFS_SSH_ADDR="${TF_NFS_PUB:-$TF_NFS_PRIV}"
  NFS_PATH="${NFS_PATH:-/srv/nfs}"
  log_info "Detected dedicated NFS server: ${NFS_SSH_ADDR} (internal: ${NFS_NODE_INTERNAL_IP}, export: ${NFS_PATH})"
else
  # Auto-detect NFS node if not specified
  if [ -z "${NFS_NODE}" ] && [ -n "${MSR4_NFS_NODE:-}" ]; then
    NFS_NODE="${MSR4_NFS_NODE}"
    log_debug "NFS node set from MSR4_NFS_NODE env: ${NFS_NODE}"
  fi
  if [ -z "${NFS_NODE}" ]; then
    log_debug "Auto-detecting NFS node from MSR4-labeled nodes..."
    NFS_NODE=$(kubectl get nodes -l msr4=true -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -z "${NFS_NODE}" ]; then
      NFS_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi
    log_debug "Auto-detected NFS node name: ${NFS_NODE}"
  fi

  if [ -z "${NFS_NODE}" ]; then
    log_error "Could not auto-detect NFS node. Specify with --nfs-node or MSR4_NFS_NODE env"
    exit 1
  fi

  # Resolve node IPs from launchpad describe hosts, hosts.yaml (MKE4), or terraform output
  NFS_SSH_ADDR=""
  NFS_NODE_INTERNAL_IP=""
  # Try launchpad first (MKE3)
  while IFS=$'\t' read -r addr internal_ip hostname role rest; do
    if [ "${hostname}" = "${NFS_NODE}" ]; then
      NFS_SSH_ADDR="${addr}"
      NFS_NODE_INTERNAL_IP="${internal_ip}"
      break
    fi
  done < <(launchpad describe -c "${PROJECT_ROOT}/artifacts/configs/launchpad.yaml" hosts 2>/dev/null | tail -n +2)
  # Try terraform output (MKE4) — map K8s internal IP to public IP
  if [ -z "${NFS_SSH_ADDR}" ] && command -v terraform &>/dev/null; then
    NFS_NODE_INTERNAL_IP=$(kubectl get node "${NFS_NODE}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    if [ -n "${NFS_NODE_INTERNAL_IP}" ]; then
      NFS_SSH_ADDR=$(terraform -chdir="${PROJECT_ROOT}" output -json all_hosts 2>/dev/null | \
        jq -r --arg ip "${NFS_NODE_INTERNAL_IP}" '.[] | select(.private_ip == $ip) | .public_ip' 2>/dev/null || true)
    fi
  fi
  # Final fallback: K8s InternalIP
  if [ -z "${NFS_SSH_ADDR}" ]; then
    log_warn "Could not resolve public IP for NFS node ${NFS_NODE}; falling back to K8s InternalIP"
    NFS_NODE_INTERNAL_IP=$(kubectl get node "${NFS_NODE}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "${NFS_NODE}")
    NFS_SSH_ADDR="${NFS_NODE_INTERNAL_IP}"
  fi
fi
log_info "Using NFS server node: ${NFS_NODE} (SSH: ${NFS_SSH_ADDR}, internal: ${NFS_NODE_INTERNAL_IP})"

# Check if nfs-storage SC already exists — skip setup if it does
if kubectl get sc nfs-storage &>/dev/null; then
  log_ok "StorageClass 'nfs-storage' already exists — reusing existing NFS setup"
else
  # Ensure NFS node resolves to something meaningful for SSH
  if [ -z "${NFS_SSH_ADDR}" ]; then
    log_error "Could not resolve SSH address for NFS node ${NFS_NODE}"
    exit 1
  fi

  SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
  if [ -n "${SSH_KEY}" ] && [ -f "${SSH_KEY}" ]; then
    SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
  fi

  log_info "Setting up NFS server on ${NFS_SSH_ADDR}..."
  ${SSH_CMD} "${SSH_USER}@${NFS_SSH_ADDR}" 'bash -s' < "${NFS_SETUP_SCRIPT}" -- "${NFS_PATH}" server || {
    log_warn "Could not setup NFS via SSH. Will attempt using existing NFS script..."
    if [ -f "${COMMON_SCRIPTS_DIR}/nfs-server-install-ubuntu.sh" ]; then
      log_info "Running nfs-server-install-ubuntu.sh on ${NFS_SSH_ADDR}..."
      ${SSH_CMD} "${SSH_USER}@${NFS_SSH_ADDR}" 'bash -s' < "${COMMON_SCRIPTS_DIR}/nfs-server-install-ubuntu.sh" || log_warn "NFS script had issues, check manually"
    fi
  }

  # Install NFS/CIFS client packages on all MSR4-labeled worker nodes
  log_info "Installing NFS/CIFS client packages on all MSR4-labeled nodes..."
  NFS_CLIENT_FAIL=0
  for CLIENT_NODE in ${MSR_NODES}; do
    CLIENT_NODE_NAME=$(echo "${CLIENT_NODE}" | sed 's|node/||')
    CLIENT_NODE_SSH_ADDR=""
    # Try launchpad first (MKE3)
    while IFS=$'\t' read -r addr internal_ip hostname role rest; do
      if [ "${hostname}" = "${CLIENT_NODE_NAME}" ]; then
        CLIENT_NODE_SSH_ADDR="${addr}"
        break
      fi
    done < <(launchpad describe -c "${PROJECT_ROOT}/artifacts/configs/launchpad.yaml" hosts 2>/dev/null | tail -n +2)
    # Try terraform output (MKE4) — map K8s internal IP to public IP
    if [ -z "${CLIENT_NODE_SSH_ADDR}" ] && command -v terraform &>/dev/null; then
      CLIENT_NODE_INTERNAL_IP=$(kubectl get node "${CLIENT_NODE_NAME}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
      if [ -n "${CLIENT_NODE_INTERNAL_IP}" ]; then
        CLIENT_NODE_SSH_ADDR=$(terraform -chdir="${PROJECT_ROOT}" output -json all_hosts 2>/dev/null | \
          jq -r --arg ip "${CLIENT_NODE_INTERNAL_IP}" '.[] | select(.private_ip == $ip) | .public_ip' 2>/dev/null || true)
      fi
    fi
    # Fallback: K8s InternalIP
    if [ -z "${CLIENT_NODE_SSH_ADDR}" ]; then
      CLIENT_NODE_SSH_ADDR=$(kubectl get node "${CLIENT_NODE_NAME}" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
    fi
    if [ -z "${CLIENT_NODE_SSH_ADDR}" ]; then
      log_error "Could not resolve address for node ${CLIENT_NODE_NAME} — NFS/CIFS client install skipped"
      NFS_CLIENT_FAIL=1
      continue
    fi
    CLIENT_SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    if [ -n "${SSH_KEY}" ] && [ -f "${SSH_KEY}" ]; then
      CLIENT_SSH_CMD="${CLIENT_SSH_CMD} -i ${SSH_KEY}"
    fi
    log_info "  Installing on ${CLIENT_NODE_NAME} (${CLIENT_NODE_SSH_ADDR})..."
    ${CLIENT_SSH_CMD} "${SSH_USER}@${CLIENT_NODE_SSH_ADDR}" 'bash -s' < "${NFS_SETUP_SCRIPT}" -- "${NFS_PATH}" client 2>&1 || {
      log_error "FAILED to install NFS/CIFS client packages on ${CLIENT_NODE_NAME} (${CLIENT_NODE_SSH_ADDR})"
      NFS_CLIENT_FAIL=1
    }
  done

  if [ "${NFS_CLIENT_FAIL}" -ne 0 ]; then
    log_error "NFS/CIFS client installation failed on one or more nodes."
    log_error "MSR4 pods will fail to mount NFS volumes. Fix the nodes and re-run."
    die "Aborting due to NFS client install failures"
  fi
  log_ok "NFS/CIFS client packages installed and verified on all MSR4-labeled nodes"

  # Install nfs-subdir-external-provisioner using InternalIP (pods within cluster need private IP to reach NFS)
  helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner 2>/dev/null || true
  helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --set nfs.server="${NFS_NODE_INTERNAL_IP}" \
    --set nfs.path="${NFS_PATH}" \
    --set storageClass.defaultClass=false \
    --set storageClass.name=nfs-storage \
    --set storageClass.reclaimPolicy=Retain \
    --set-string nodeSelector.msr4=true \
    --wait

  log_ok "NFS storage class 'nfs-storage' installed"
fi

# ==============================================================================
# STEP 4: Redis Setup (HA mode only)
# ==============================================================================

if [ "${HA_MODE}" = true ]; then
  run_step "Step 4: Redis setup (HA mode — Sentinel)"

  # Install Redis Operator
  log_info "Installing Redis Operator..."
  log_debug "Adding ot-container-kit Helm repo and installing redis-operator chart..."
  helm upgrade --install redis-operator redis-operator \
    --repo https://ot-container-kit.github.io/helm-charts \
    --namespace "${NAMESPACE}" \
    --set featureGates.GenerateConfigInInitContainer=true \
    --wait

  # Generate random password
  REDIS_PASSWORD=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 24 || true)
  log_debug "Redis password generated (hidden)"

  # Create Kubernetes secret
  kubectl create secret generic msr-redis-secret \
    --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  log_ok "Redis secret created"

  # Wait for Redis operator to be fully ready before deploying Redis cluster
  log_info "Waiting for Redis operator to be ready..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis-operator -n "${NAMESPACE}" --timeout=120s 2>&1 | grep -v "condition met" || true
  sleep 10
  # Verify operator is ready by checking for leader election
  if kubectl get lease -n "${NAMESPACE}" -l app.kubernetes.io/name=redis-operator -o name 2>/dev/null | grep -q lease; then
    log_ok "Redis operator is ready"
  else
    log_warn "Redis operator lease not found, waiting additional time..."
    sleep 15
  fi

  # Deploy Redis with Sentinel — per MSR 4.13 documentation
  log_info "Deploying Redis with Sentinel cluster..."
  helm upgrade --install msr-redis redis-replication \
    --repo https://ot-container-kit.github.io/helm-charts \
    --namespace "${NAMESPACE}" \
    --set redisReplication.clusterSize=3 \
    --set redisReplication.image=quay.io/opstree/redis \
    --set redisReplication.tag=v7.2.13 \
    --set redisReplication.redisSecret.secretName=msr-redis-secret \
    --set redisReplication.redisSecret.secretKey=REDIS_PASSWORD \
    --set podSecurityContext.runAsUser=1000 \
    --set podSecurityContext.fsGroup=1000 \
    --set sentinel.enabled=true \
    --set sentinel.size=3 \
    --set sentinel.image=quay.io/opstree/redis-sentinel \
    --set sentinel.tag=v7.2.13 \
    --set storageSpec.volumeClaimTemplate.spec.accessModes={ReadWriteOnce} \
    --set storageSpec.volumeClaimTemplate.spec.resources.requests.storage=8Gi \
    --set storageSpec.volumeClaimTemplate.spec.storageClassName=nfs-storage

  # Verify the RedisReplication CR was created — retry helm upgrade if missing
  if ! kubectl get redisreplication -n "${NAMESPACE}" msr-redis &>/dev/null; then
    log_warn "RedisReplication CR not found after helm install. Retrying helm upgrade..."
    sleep 10
    helm upgrade --install msr-redis redis-replication \
      --repo https://ot-container-kit.github.io/helm-charts \
      --namespace "${NAMESPACE}" \
      --set redisReplication.clusterSize=3 \
      --set redisReplication.image=quay.io/opstree/redis \
      --set redisReplication.tag=v7.2.13 \
      --set redisReplication.redisSecret.secretName=msr-redis-secret \
      --set redisReplication.redisSecret.secretKey=REDIS_PASSWORD \
      --set podSecurityContext.runAsUser=1000 \
      --set podSecurityContext.fsGroup=1000 \
      --set sentinel.enabled=true \
      --set sentinel.size=3 \
      --set sentinel.image=quay.io/opstree/redis-sentinel \
      --set sentinel.tag=v7.2.13 \
      --set storageSpec.volumeClaimTemplate.spec.accessModes={ReadWriteOnce} \
      --set storageSpec.volumeClaimTemplate.spec.resources.requests.storage=8Gi \
      --set storageSpec.volumeClaimTemplate.spec.storageClassName=nfs-storage 2>&1 | tail -3
    if ! kubectl get redisreplication -n "${NAMESPACE}" msr-redis &>/dev/null; then
      log_warn "RedisReplication CR still missing after retry. Check operator logs."
    fi
  fi

  # Wait for Redis pods (not using --wait since chart creates CRD, not StatefulSet directly)
  wait_for_pods "app.kubernetes.io/name=msr-redis" "${NAMESPACE}" 300 "Redis"
  wait_for_pods "app.kubernetes.io/name=msr-redis,redis-role=sentinel" "${NAMESPACE}" 300 "Redis Sentinel"

  # Retrieve Sentinel connection details
  SENTINEL_SVC="msr-redis-s-hl"
  CLUSTER_DOMAIN="cluster.local"
  SENTINEL_ADDR=""

  for i in 0 1 2; do
    if [ -n "${SENTINEL_ADDR}" ]; then
      SENTINEL_ADDR+=","
    fi
    SENTINEL_ADDR+="msr-redis-s-${i}.${SENTINEL_SVC}.${NAMESPACE}.svc.${CLUSTER_DOMAIN}:26379"
  done

  # Store for use in values customization
  export MSR4_REDIS_ADDR="${SENTINEL_ADDR}"
  export MSR4_SENTINEL_MASTER_SET="mymaster"

  log_ok "Redis with Sentinel deployed"
  log_info "  Sentinel addresses: ${SENTINEL_ADDR}"
  log_info "  Sentinel master set: mymaster"
fi

# ==============================================================================
# STEP 5: PostgreSQL Setup (HA mode only)
# ==============================================================================

if [ "${HA_MODE}" = true ]; then
  run_step "Step 5: PostgreSQL setup (HA mode — Zalando)"

  # Install Zalando Postgres Operator with Mirantis Spilo image
  log_info "Installing PostgreSQL Operator..."
  log_debug "Adding Zalando postgres-operator Helm repo..."
  helm upgrade --install postgres-operator postgres-operator \
    --repo https://opensource.zalando.com/postgres-operator/charts/postgres-operator \
    --namespace "${NAMESPACE}" \
    --skip-crds \
    --set configGeneral.docker_image=registry.mirantis.com/msr/spilo:17-4.0-p3-20251117010013 \
    --set configKubernetes.spilo_privileged=false \
    --set configKubernetes.spilo_allow_privilege_escalation=false \
    --wait

  # Wait for postgres-operator to be ready before applying manifest
  log_debug "Waiting for postgres-operator to be ready..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgres-operator -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true
  sleep 5

  # Clean up orphaned PDBs from previous runs that would block cluster creation
  kubectl delete pdb -n "${NAMESPACE}" -l postgres-operator=postgres-operator 2>/dev/null || true
  kubectl delete pdb -n "${NAMESPACE}" postgres-msr-postgres-pdb postgres-msr-postgres-critical-op-pdb 2>/dev/null || true

  # Apply PostgreSQL manifest
  if [ -f "${MANIFESTS_DIR}/msr-postgres-manifest.yaml" ]; then
    log_info "Applying PostgreSQL manifest..."
    kubectl apply -n "${NAMESPACE}" -f "${MANIFESTS_DIR}/msr-postgres-manifest.yaml"
  else
    # Apply inline
    kubectl apply -n "${NAMESPACE}" -f- <<'PGF'
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: msr-postgres
  namespace: msr4
spec:
  teamId: "msr"
  volume:
    size: 1Gi
    storageClass: nfs-storage
  numberOfInstances: 3
  users:
    msr:
    - superuser
    - createdb
  databases:
    registry: msr
  postgresql:
    version: "17"
    parameters:
      shared_preload_libraries: "pg_stat_statements,pgextwlist,pg_auth_mon,set_user,timescaledb,pg_cron,pg_stat_kcache"
PGF
  fi

  # Verify NFS provisioner is working before deploying PostgreSQL
  log_debug "Checking NFS provisioner health..."
  if kubectl get po -n default -l app=nfs-subdir-external-provisioner 2>/dev/null | grep -q "Running"; then
    log_ok "NFS provisioner is running"
  else
    log_warn "NFS provisioner not running; PVCs may not be provisioned"
  fi

  # Wait for PostgreSQL pods
  wait_for_pods "cluster-name=msr-postgres" "${NAMESPACE}" 600 "PostgreSQL"
  sleep 10

  # Get connection details
  PG_HOST=$(kubectl -n "${NAMESPACE}" get svc \
    -l application=spilo,cluster-name=msr-postgres,spilo-role=master \
    -o jsonpath='{.items..spec.clusterIP}' 2>/dev/null || true)
  PG_PORT=$(kubectl -n "${NAMESPACE}" get svc \
    -l application=spilo,cluster-name=msr-postgres,spilo-role=master \
    -o jsonpath='{.items..spec.ports..port}' 2>/dev/null || echo "5432")

  if [ -z "${PG_HOST}" ]; then
    log_error "Could not determine PostgreSQL host IP"
    log_info "Available services:"
    kubectl -n "${NAMESPACE}" get svc -l application=spilo 2>/dev/null || true
    log_info "You will need to manually get the IP and update the values file."
    PG_HOST="CHANGE_ME"
  fi

  export MSR4_PG_HOST="${PG_HOST}"
  export MSR4_PG_PORT="${PG_PORT}"

  log_ok "PostgreSQL deployed"
  log_info "  Host: ${PG_HOST}"
  log_info "  Port: ${PG_PORT}"
  log_info "  Secret: msr.msr-postgres.credentials.postgresql.acid.zalan.do"
fi

# ==============================================================================
# STEP 6: TLS Certificate Setup
# ==============================================================================

run_step "Step 6: TLS certificate setup"

# Follow the same ACME + disk-caching pattern as MKE3/MKE4/ingress
# Store at: artifacts/tlscerts/msr4/<domain>/ (server.pem, key.pem, ca.pem)
MSR4_TLS_DIR="${TLS_DIR}/msr4/${DOMAIN}"
MSR4_TLS_CERT="${MSR4_TLS_DIR}/server.pem"
MSR4_TLS_KEY="${MSR4_TLS_DIR}/key.pem"
MSR4_TLS_CA="${MSR4_TLS_DIR}/ca.pem"
TLS_SECRET_NAME="msr4-tls-cert"
MIN_VALID_HOURS=168  # 7 days minimum validity before re-issuance

use_existing_cert=false

# Check if a cached ACME cert exists, is still valid, and matches the domain
if [ -f "${MSR4_TLS_CERT}" ] && [ -f "${MSR4_TLS_KEY}" ]; then
  log_info "Found cached cert at ${MSR4_TLS_DIR}"
  MIN_VALID_SECONDS=$((MIN_VALID_HOURS * 3600))
  if openssl x509 -in "${MSR4_TLS_CERT}" -noout -checkend "${MIN_VALID_SECONDS}" 2>/dev/null; then
    # Check domain matches in CN or SubjectAltName
    CERT_NAMES=$(openssl x509 -in "${MSR4_TLS_CERT}" -noout -subject -ext subjectAltName 2>/dev/null || true)
    DOMAIN_ESC=$(echo "${DOMAIN}" | sed 's/\./\\./g')
    if echo "${CERT_NAMES}" | grep -Eq "(DNS:|CN[ =])${DOMAIN_ESC}([,[:space:]]|$)"; then
      log_ok "Cached ACME cert is valid (${MIN_VALID_HOURS}h+) and matches ${DOMAIN} — reusing"
      use_existing_cert=true
    else
      log_info "Cached cert does not match domain ${DOMAIN} — will re-issue"
    fi
  else
    log_info "Cached cert expired or expiring soon — will re-issue"
  fi
fi

if [ "${use_existing_cert}" = true ]; then
  # Bundle leaf cert with CA chain for proper validation
  MSR4_TLS_CERT_BUNDLE="${MSR4_TLS_DIR}/fullchain.pem"
  cat "${MSR4_TLS_CERT}" "${MSR4_TLS_CA}" > "${MSR4_TLS_CERT_BUNDLE}" 2>/dev/null || cp "${MSR4_TLS_CERT}" "${MSR4_TLS_CERT_BUNDLE}"
  kubectl create secret tls "${TLS_SECRET_NAME}" \
    --cert="${MSR4_TLS_CERT_BUNDLE}" \
    --key="${MSR4_TLS_KEY}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  log_ok "TLS secret '${TLS_SECRET_NAME}' created from cached ACME certs"

else
  LE_ISSUED=false

  # Method 1: cert-manager (if ClusterIssuer exists)
  if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
    log_info "Found ClusterIssuer 'letsencrypt-prod' — requesting Let's Encrypt certificate..."
    ACME_CERT_NAME="msr4-tls-${NAMESPACE}"
    kubectl delete certificate "${ACME_CERT_NAME}" -n "${NAMESPACE}" 2>/dev/null || true

    log_info "Creating Certificate resource for ${DOMAIN}..."
    cat <<CERTEOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${ACME_CERT_NAME}
  namespace: ${NAMESPACE}
spec:
  secretName: ${TLS_SECRET_NAME}
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - ${DOMAIN}
CERTEOF

    log_info "Waiting for Let's Encrypt certificate to be issued (up to 60s)..."
    if kubectl wait --for=condition=Ready certificate "${ACME_CERT_NAME}" -n "${NAMESPACE}" --timeout=60s 2>/dev/null; then
      log_ok "Let's Encrypt certificate issued successfully via cert-manager"
      mkdir -p "${MSR4_TLS_DIR}"
      kubectl get secret "${TLS_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d > "${MSR4_TLS_CERT}" || true
      kubectl get secret "${TLS_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.key}' 2>/dev/null | base64 -d > "${MSR4_TLS_KEY}" || true
      kubectl get secret "${TLS_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.ca\.crt}' 2>/dev/null | base64 -d > "${MSR4_TLS_CA}" 2>/dev/null || true
      chmod 600 "${MSR4_TLS_KEY}" "${MSR4_TLS_CA}" 2>/dev/null || true
      log_ok "ACME certificate cached to ${MSR4_TLS_DIR}"
      LE_ISSUED=true
    else
      log_warn "cert-manager issuance timed out. Checking cert status..."
      kubectl describe certificate "${ACME_CERT_NAME}" -n "${NAMESPACE}" 2>/dev/null | tail -10 || true
    fi
  else
    log_info "ClusterIssuer 'letsencrypt-prod' not found. cert-manager not available."
  fi

  # Method 2: acme.sh with Cloudflare DNS-01 challenge (no cert-manager required)
  if [ "${LE_ISSUED}" != true ]; then
    CF_API_TOKEN="${CF_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-}}"
    if [ -n "${CF_API_TOKEN}" ]; then
      log_info "Cloudflare API token found — attempting Let's Encrypt via acme.sh DNS-01 challenge..."
      ACME_SH="${HOME}/.acme.sh/acme.sh"
      if [ ! -f "${ACME_SH}" ]; then
        log_info "Downloading acme.sh..."
        curl -sL https://get.acme.sh | sh -s -- --install-online --no-profile 2>/dev/null || log_warn "acme.sh download failed"
        ACME_SH="${HOME}/.acme.sh/acme.sh"
      fi
      if [ -f "${ACME_SH}" ]; then
        TMP_DIR=$(mktemp -d)
        export CF_Token="${CF_API_TOKEN}"
        export CF_Zone_Email=""
        if ${ACME_SH} --issue --dns dns_cf -d "${DOMAIN}" --keylength 2048 --ocsp --home "${TMP_DIR}/acme" 2>/dev/null; then
          if ${ACME_SH} --install-cert -d "${DOMAIN}" --cert-file "${TMP_DIR}/cert.pem" --key-file "${TMP_DIR}/key.pem" --ca-file "${TMP_DIR}/ca.pem" --home "${TMP_DIR}/acme" 2>/dev/null; then
            mkdir -p "${MSR4_TLS_DIR}"
            cp "${TMP_DIR}/cert.pem" "${MSR4_TLS_CERT}"
            cp "${TMP_DIR}/key.pem" "${MSR4_TLS_KEY}"
            cp "${TMP_DIR}/ca.pem" "${MSR4_TLS_CA}" 2>/dev/null || true
            chmod 600 "${MSR4_TLS_KEY}" "${MSR4_TLS_CA}" 2>/dev/null || true
            MSR4_TLS_CERT_BUNDLE="${MSR4_TLS_DIR}/fullchain.pem"
            cat "${MSR4_TLS_CERT}" "${MSR4_TLS_CA}" > "${MSR4_TLS_CERT_BUNDLE}" 2>/dev/null || cp "${MSR4_TLS_CERT}" "${MSR4_TLS_CERT_BUNDLE}"

            kubectl create secret tls "${TLS_SECRET_NAME}" \
              --cert="${MSR4_TLS_CERT_BUNDLE}" \
              --key="${MSR4_TLS_KEY}" \
              --namespace "${NAMESPACE}" \
              --dry-run=client -o yaml | kubectl apply -f -
            log_ok "Let's Encrypt certificate issued and cached to ${MSR4_TLS_DIR}"
            LE_ISSUED=true
          fi
        else
          log_warn "acme.sh certificate issuance failed"
        fi
        rm -rf "${TMP_DIR}"
      else
        log_warn "acme.sh not available. Cannot issue Let's Encrypt certificate."
      fi
      unset CF_Token
    else
      log_info "No Cloudflare API token (CF_API_TOKEN) available for DNS-01 challenge."
    fi
  fi

  # Final fallback: self-signed certificate
  if [ "${LE_ISSUED}" != true ]; then
    log_info "Generating self-signed certificate for ${DOMAIN}..."
    TMP_DIR=$(mktemp -d)
    cat > "${TMP_DIR}/certs.conf" <<CONF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = msr4

[v3_req]
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
CONF

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "${TMP_DIR}/tls.key" \
      -out "${TMP_DIR}/tls.crt" \
      -config "${TMP_DIR}/certs.conf" 2>/dev/null

    kubectl create secret tls "${TLS_SECRET_NAME}" \
      --cert="${TMP_DIR}/tls.crt" \
      --key="${TMP_DIR}/tls.key" \
      --namespace "${NAMESPACE}" \
      --dry-run=client -o yaml | kubectl apply -f -

    mkdir -p "${MSR4_TLS_DIR}"
    cp "${TMP_DIR}/tls.crt" "${MSR4_TLS_CERT}"
    cp "${TMP_DIR}/tls.key" "${MSR4_TLS_KEY}"
    chmod 600 "${MSR4_TLS_KEY}"
    rm -rf "${TMP_DIR}"
    log_ok "Self-signed TLS certificate generated and cached to ${MSR4_TLS_DIR}"
  fi
fi

# ==============================================================================
# STEP 7: Customize Values & Install MSR
# ==============================================================================

run_step "Step 7: Installing MSR4 via Helm"

# Determine values file
VALUES_FILE="${VALUES_DIR}/msr-values-${MSR4_VERSION}-single.yaml"
HA_OVERRIDES="${VALUES_DIR}/msr-ha-overrides.yaml"
OVERRIDE_FILE="/tmp/msr4-dynamic-overrides-$$.yaml"

if [ ! -f "${VALUES_FILE}" ]; then
  log_warn "Values file ${VALUES_FILE} not found. Attempting to fetch from upstream..."
  log_debug "Running: helm show values oci://registry.mirantis.com/harbor/helm/msr --version ${MSR4_VERSION}"
  if helm show values "oci://registry.mirantis.com/harbor/helm/msr" --version "${MSR4_VERSION}" > "${VALUES_FILE}" 2>/dev/null; then
    log_ok "Values file fetched from upstream"
  else
    die "Could not fetch values. Ensure you are logged in to registry.mirantis.com with 'helm registry login'"
  fi
fi

# Generate random master key (16 chars)
MSR_SECRET_KEY=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 16 || true)
log_debug "Generated secret key"

MSR4_STORAGE_CLASS="${MSR4_STORAGE_CLASS:-nfs-storage}"
log_debug "Using storage class ${MSR4_STORAGE_CLASS}"

log_debug "Generating dynamic override file..."
python3 -c "
import yaml
data = {}
data['secretKey'] = '${MSR_SECRET_KEY}'
data['externalURL'] = 'https://${DOMAIN}'
data.setdefault('expose', {})
data['expose']['type'] = 'nodePort'
data.setdefault('expose', {}).setdefault('tls', {})
data['expose']['tls']['certSource'] = 'secret'
data['expose']['tls']['secret'] = {'secretName': 'msr4-tls-cert'}
data.setdefault('nodePort', {}).setdefault('ports', {})
data['nodePort']['ports'].setdefault('http', {})['nodePort'] = ${HTTP_NODE_PORT}
data['nodePort']['ports'].setdefault('https', {})['nodePort'] = ${HTTPS_NODE_PORT}
# Set storageClass default for internal components
data.setdefault('persistence', {}).setdefault('persistentVolumeClaim', {})
for comp in ['database', 'redis', 'registry', 'jobservice', 'trivy']:
    data['persistence']['persistentVolumeClaim'].setdefault(comp, {})
    data['persistence']['persistentVolumeClaim'][comp]['storageClass'] = '${MSR4_STORAGE_CLASS}'
js = data['persistence']['persistentVolumeClaim']['jobservice']
js.setdefault('jobLog', {})
js['jobLog']['storageClass'] = '${MSR4_STORAGE_CLASS}'
with open('${OVERRIDE_FILE}', 'w') as f:
    yaml.dump(data, f)
" 2>/dev/null || die "Failed to generate dynamic overrides"

# Apply HA-specific settings (replicas, persistence) to the override file
if [ "${HA_MODE}" = true ]; then
  python3 -c "
import yaml
with open('${OVERRIDE_FILE}') as f:
    data = yaml.safe_load(f) or {}
data['persistence'] = data.get('persistence', {})
data['persistence']['resourcePolicy'] = 'keep'
for comp in ['portal', 'core', 'jobservice', 'registry', 'trivy']:
    data[comp] = data.get(comp, {})
    data[comp]['replicas'] = 2
with open('${OVERRIDE_FILE}', 'w') as f:
    yaml.dump(data, f)
" 2>/dev/null || log_warn "Failed to apply HA overrides"
fi

# Apply HA overrides by merging into the override file
if [ "${HA_MODE}" = true ] && [ -f "${HA_OVERRIDES}" ]; then
  log_info "Merging HA mode overrides..."
  python3 -c "
import yaml
with open('${OVERRIDE_FILE}') as f: v1 = yaml.safe_load(f)
with open('${HA_OVERRIDES}') as f: v2 = yaml.safe_load(f)
def merge(a, b):
    for k in b:
        if k in a and isinstance(a[k], dict) and isinstance(b[k], dict):
            merge(a[k], b[k])
        else:
            a[k] = b[k]
merge(v1, v2)
with open('${OVERRIDE_FILE}', 'w') as f: yaml.dump(v1, f)
" 2>/dev/null || log_warn "Failed to merge HA overrides"
fi

# Inject HA-specific connection details into override file
if [ "${HA_MODE}" = true ]; then
  if [ -n "${MSR4_PG_HOST:-}" ] && [ "${MSR4_PG_HOST}" != "CHANGE_ME" ]; then
    log_debug "Setting external PostgreSQL host: ${MSR4_PG_HOST}:${MSR4_PG_PORT}"
    python3 -c "
import yaml
with open('${OVERRIDE_FILE}') as f:
    data = yaml.safe_load(f)
data['database'] = {'type': 'external'}
data['database']['external'] = {
    'sslmode': 'require',
    'host': '${MSR4_PG_HOST}',
    'port': ${MSR4_PG_PORT:-5432},
    'coreDatabase': 'registry',
    'username': 'msr',
    'existingSecret': 'msr.msr-postgres.credentials.postgresql.acid.zalan.do'
}
with open('${OVERRIDE_FILE}', 'w') as f:
    yaml.dump(data, f)
" 2>/dev/null || log_warn "Failed to inject PostgreSQL config"
  fi
  if [ -n "${MSR4_REDIS_ADDR:-}" ]; then
    log_debug "Setting external Redis Sentinel addresses"
    python3 -c "
import yaml
with open('${OVERRIDE_FILE}') as f:
    data = yaml.safe_load(f)
data.setdefault('redis', {})['type'] = 'external'
data['redis']['external'] = {
    'addr': '${MSR4_REDIS_ADDR}',
    'existingSecret': 'msr-redis-secret',
    'sentinelMasterSet': '${MSR4_SENTINEL_MASTER_SET:-mymaster}'
}
with open('${OVERRIDE_FILE}', 'w') as f:
    yaml.dump(data, f)
" 2>/dev/null || log_warn "Failed to inject Redis config"
  fi
fi

# Merge custom values overrides on top of all other overrides
CUSTOM_VALUES_FILE=""
if [ -n "${CUSTOM_VALUES:-}" ]; then
  if [ -f "${CUSTOM_VALUES}" ]; then
    CUSTOM_VALUES_FILE="${CUSTOM_VALUES}"
    log_info "Using custom values file: ${CUSTOM_VALUES_FILE}"
  else
    log_warn "Specified custom values file not found: ${CUSTOM_VALUES}"
  fi
elif [ -f "${VALUES_DIR}/msr4-overrides.yaml" ]; then
  CUSTOM_VALUES_FILE="${VALUES_DIR}/msr4-overrides.yaml"
  log_info "Found local overrides file: ${CUSTOM_VALUES_FILE}"
fi
if [ -n "${CUSTOM_VALUES_FILE}" ]; then
  python3 -c "
import yaml
with open('${OVERRIDE_FILE}') as f: base = yaml.safe_load(f) or {}
with open('${CUSTOM_VALUES_FILE}') as f: overrides = yaml.safe_load(f) or {}
def merge(a, b):
    for k in b:
        if k in a and isinstance(a[k], dict) and isinstance(b[k], dict):
            merge(a[k], b[k])
        else:
            a[k] = b[k]
merge(base, overrides)
with open('${OVERRIDE_FILE}', 'w') as f: yaml.dump(base, f)
" 2>/dev/null && log_ok "Custom overrides merged into values file"
fi

# Helm registry login
HELM_USER="${HELM_USERNAME:-${MSR4_HELM_USERNAME:-}}"
HELM_PASS="${HELM_PASSWORD:-${MSR4_HELM_PASSWORD:-}}"
if [ -n "${HELM_USER}" ] && [ -n "${HELM_PASS}" ]; then
  log_info "Logging into registry.mirantis.com..."
  log_debug "Authenticating as '${HELM_USER}' to registry.mirantis.com"
  echo "${HELM_PASS}" | helm registry login registry.mirantis.com --username "${HELM_USER}" --password-stdin 2>/dev/null || log_warn "Helm login failed. Continuing..."
else
  log_warn "No Helm registry credentials provided. Install may fail if not already logged in."
  log_info "Set --helm-username/--helm-password or MSR4_HELM_USERNAME/MSR4_HELM_PASSWORD env vars"
fi

# Print key configuration for debugging
log_debug "=== Helm install configuration ==="
log_debug "  Chart:     oci://registry.mirantis.com/harbor/helm/msr"
log_debug "  Version:   ${MSR4_VERSION}"
log_debug "  Namespace: ${NAMESPACE}"
log_debug "  Timeout:   30m"
log_debug "  Values:    ${VALUES_FILE} + ${OVERRIDE_FILE}${CUSTOM_VALUES_FILE:+ + custom:${CUSTOM_VALUES_FILE}}"
log_debug "  externalURL: https://${DOMAIN}"
log_debug "  expose.certSource: secret"
log_debug "  expose.secret.secretName: msr4-tls-cert"
log_debug "================================"

# Install or upgrade MSR with verbose progress
log_info "Installing MSR4 (${MSR4_VERSION}) via Helm..."
log_info "This may take 5-15 minutes while containers are pulled and started..."
log_info "Watching pod status in namespace '${NAMESPACE}'..."

# Start background pod watcher
(
  sleep 10
  WATCH_COUNT=0
  while [ $WATCH_COUNT -lt 180 ]; do
    PENDING=$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
    if [ "${PENDING}" -gt 0 ]; then
      echo "[$(date +%H:%M:%S)] Pods not ready: ${PENDING} pending — latest status:"
      kubectl get pods -n "${NAMESPACE}" -o wide --no-headers 2>/dev/null | head -10
    fi
    sleep 10
    WATCH_COUNT=$((WATCH_COUNT + 1))
  done
) &
WATCHER_PID=$!

# Run helm install with debug output piped to tee for visibility
log_info "Running: helm upgrade --install msr4 oci://registry.mirantis.com/harbor/helm/msr \\"
log_info "  --version ${MSR4_VERSION} --namespace ${NAMESPACE} \\"
log_info "  -f ${VALUES_FILE} -f ${OVERRIDE_FILE} --timeout 30m --wait"
set +e
helm upgrade --install msr4 "oci://registry.mirantis.com/harbor/helm/msr" \
  --version "${MSR4_VERSION}" \
  --namespace "${NAMESPACE}" \
  -f "${VALUES_FILE}" \
  -f "${OVERRIDE_FILE}" \
  --timeout 30m \
  --wait \
  --debug 2>&1 | tee /tmp/msr4-helm-output-$$.log
HELM_EXIT_CODE=$?
set -e

# Stop the background watcher
kill "${WATCHER_PID}" 2>/dev/null || true

if [ "${HELM_EXIT_CODE}" -ne 0 ]; then
  log_error "Helm install failed (exit code: ${HELM_EXIT_CODE})"
  log_info "Full Helm output saved to: /tmp/msr4-helm-output-$$.log"
  log_info "Last 30 lines of Helm output:"
  tail -20 /tmp/msr4-helm-output-$$.log
  log_info "Current pod status in namespace '${NAMESPACE}':"
  kubectl get pods -n "${NAMESPACE}" -o wide 2>/dev/null || true
  log_info "Check pod logs for troubleshooting: kubectl logs -n ${NAMESPACE} <pod-name>"
  die "MSR4 installation failed. See output above for details."
fi

log_ok "Helm install/upgrade completed successfully"

# Show deployed resources
log_debug "Deployed resources in namespace '${NAMESPACE}':"
log_debug "--- Pods ---"
kubectl get pods -n "${NAMESPACE}" -o wide 2>/dev/null | while IFS= read -r line; do log_debug "${line}"; done
log_debug "--- Services ---"
kubectl get svc -n "${NAMESPACE}" 2>/dev/null | while IFS= read -r line; do log_debug "${line}"; done
log_debug "--- Ingresses ---"
kubectl get ingress -n "${NAMESPACE}" 2>/dev/null | while IFS= read -r line; do log_debug "${line}"; done

# Show MSR login endpoint
MSR_NODE_PORT=""
MSR_NODE_PORT=$(kubectl get svc -n "${NAMESPACE}" -l app=harbor,component=portal -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}' 2>/dev/null || echo "${HTTPS_NODE_PORT}")
log_info "MSR4 should be accessible at: https://${DOMAIN}"

# Save admin credentials
mkdir -p "${MSR_DIR}"
log_debug "Saving admin credentials to ${MSR_DIR}/msr4-admin.env"
cat > "${MSR_DIR}/msr4-admin.env" <<ENVEOF
# MSR4 Admin Credentials — KEEP SECURE
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Default password — change after first login
MSR4_DOMAIN=${DOMAIN}
MSR4_HTTPS_PORT=${HTTPS_NODE_PORT}
MSR4_USERNAME=admin
MSR4_PASSWORD=Harbor12345
ENVEOF
chmod 600 "${MSR_DIR}/msr4-admin.env"
log_ok "Admin credentials saved to ${MSR_DIR}/msr4-admin.env"

# Clean up dynamic overrides
rm -f "${OVERRIDE_FILE}"
log_debug "Dynamic override file cleaned up"

log_ok "MSR4 installation/upgrade completed successfully"

# ==============================================================================
# STEP 8: Post-Install Output
# ==============================================================================

echo ""
echo "============================================================"
echo -e "${GREEN} MSR4 Installation Complete!${NC}"
echo "============================================================"
echo ""
echo "  UI URL:      https://${DOMAIN}"
  echo "  Login:       admin"
  echo "  Password:    See ${MSR_DIR}/msr4-admin.env"
  echo ""
  echo "  Docker login:"
  echo "    docker login ${DOMAIN}"
echo ""
echo "  Admin credentials saved to: ${MSR_DIR}/msr4-admin.env"
echo ""

if [ "${HA_MODE}" = true ]; then
  echo "  HA Components:"
  echo "    Redis:      3 nodes with Sentinel"
  echo "    PostgreSQL: 3 instances (Zalando Spilo)"
  echo "    MSR:        2 replicas per component"
  echo ""
fi

echo "  Quick checks:"
echo "    kubectl get pods -n ${NAMESPACE}"
echo "    kubectl get svc -n ${NAMESPACE}"
echo ""
