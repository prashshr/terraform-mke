#!/usr/bin/env bash
# mkestack.sh — orchestrate full cluster build
# Called via: make mkestack [YES=1] [LOG=1] [CLUSTER_TYPE=...] [MKE_VERSION=...] [MSR_VERSION=...]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"

# Load config from single config.env file
source "$REPO/artifacts/scripts/common/config_parser.sh"
load_config "$REPO/config.env"

AUTO_YES="${YES:-}"
USE_LOG="${LOG:-}"

# CLI args override config file
CLUSTER_TYPE="${CLUSTER_TYPE:-$CLUSTER_TYPE}"
MKECTL_TIMEOUT_MINS="${MKECTL_TIMEOUT_MINS:-60}"

# Resolve MKE version from config if not set via CLI
if [[ -z "${MKE_VERSION:-}" ]]; then
    if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
        MKE_VERSION="$MKE3_VERSION"
    else
        MKE_VERSION="$MKE4_VERSION"
    fi
fi

MSR_VERSION="${MSR_VERSION:-$MSR_VERSION}"
# If MSR4_ENABLED in config but MSR_VERSION empty, use MSR4_VERSION
if [[ -z "$MSR_VERSION" && "${MSR4_ENABLED:-false}" == "true" ]]; then
    MSR_VERSION="$MSR4_VERSION"
fi

# Logging
if [[ "$USE_LOG" == "1" ]]; then
    mkdir -p "$REPO/logs"
    exec > >(tee -a "$REPO/logs/mkestack-$(date +%Y%m%d-%H%M%S).log") 2>&1
fi

# Prompt helper
ask() {
    [[ "$AUTO_YES" == "1" ]] && return 0
    read -rp "$1 [y/N]: " a
    [[ "$a" =~ ^[Yy]$ ]] || exit 1
}

echo ""
echo "=== MKE Stack ==="
echo "  Type: $CLUSTER_TYPE"
echo "  MKE:  $MKE_VERSION"
echo "  MCR:  $MCR_VERSION"
echo "  MSR:  ${MSR_VERSION:-integrated}"
echo ""

ask "Proceed?" || exit 1

# 1. Destroy if state exists
if terraform -chdir="$REPO" state list &>/dev/null 2>&1; then
    ask "Existing infrastructure found. Destroy?" || exit 1
    terraform -chdir="$REPO" destroy -auto-approve
fi

# 2. Native SSH host-key bypass (k0sctl/rig respects SSH_KNOWN_HOSTS)
export SSH_KNOWN_HOSTS=/dev/null
# Legacy fallback kept for tools that don't respect it:
# rm -f "$HOME/.ssh/known_hosts"

# 3. Init
terraform -chdir="$REPO" init -input=false

# 4. Apply
TF_ARGS=(-auto-approve -var "cluster_type=$CLUSTER_TYPE")
if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
    TF_ARGS+=(-var "mke3_version=$MKE_VERSION")
else
    TF_ARGS+=(-var "mke4_version=$MKE_VERSION")
fi
terraform -chdir="$REPO" apply "${TF_ARGS[@]}"

# 5. (SSH_KNOWN_HOSTS=/dev/null exported — no need to clear known_hosts)

# 6. Install MKE
if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
    SSH_KNOWN_HOSTS=/dev/null launchpad apply -c "$REPO/artifacts/configs/launchpad.yaml" --debug
    SSH_KNOWN_HOSTS=/dev/null launchpad client-config -c "$REPO/artifacts/configs/launchpad.yaml"
    echo "MKE3 $MKE_VERSION + MSR installed via launchpad."
else
    MINOR=$(echo "$MKE_VERSION" | cut -d. -f1-2)
    BIN="$REPO/artifacts/bin/mkectl-v$MKE_VERSION"
    [ -f "$BIN" ] || "$REPO/artifacts/bin/download_mkectl.sh" "$MKE_VERSION"
    SSH_KNOWN_HOSTS=/dev/null "$BIN" apply -f "$REPO/artifacts/configs/mke4-v$MINOR.yaml" --admin-password "$ADMIN_PASSWORD" -l debug --timeout-minutes "$MKECTL_TIMEOUT_MINS" --lease-adopt-stale
    echo "MKE4 $MKE_VERSION installed."
fi

# 7. Refresh kubeconfig (certs rotate on each apply, old kubeconfig has stale CA)
MANAGER_IP=$(terraform -chdir="$REPO" output -json all_hosts 2>/dev/null | jq -r '.[0].public_ip')
if [[ "$CLUSTER_TYPE" == "mke4" && -f "$HOME/.mke/mke.kubeconf" ]]; then
    # MKE4: mkectl writes kubeconfig to ~/.mke/mke.kubeconf
    cp "$HOME/.mke/mke.kubeconf" "$REPO/artifacts/configs/kubeconfig.yaml"
    sed -i "s|server: .*|server: https://${MANAGER_IP}:6443|" "$REPO/artifacts/configs/kubeconfig.yaml"
    echo "Kubeconfig copied from ~/.mke/mke.kubeconf"
else
    # MKE3 or fallback: SSH to manager
    SSH_KEY=$(find "$REPO/artifacts/ssh" -name '*.pem' | head -1)
    SSH_USER="ec2-user"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "${SSH_USER}@${MANAGER_IP}" \
        "sudo cat /var/lib/k0s/pki/admin.conf" > "$REPO/artifacts/configs/kubeconfig.yaml"
    sed -i "s|server: .*|server: https://${MANAGER_IP}:6443|" "$REPO/artifacts/configs/kubeconfig.yaml"
    echo "Kubeconfig refreshed from manager ${MANAGER_IP}"
fi

# 8. Install NFS client packages on ALL worker nodes before MSR4
if [[ -n "$MSR_VERSION" ]]; then
    echo ""
    echo "=== Installing NFS client packages on all worker nodes ==="
    SSH_KEY=$(find "$REPO/artifacts/ssh" -name '*.pem' | head -1)
    SSH_USER="ec2-user"
    ALL_HOSTS=$(terraform -chdir="$REPO" output -json all_hosts 2>/dev/null)

    for row in $(echo "$ALL_HOSTS" | jq -r '.[] | @base64'); do
        _jq() { echo "$row" | base64 -d | jq -r "$1"; }
        HOST_IP=$(_jq '.public_ip')
        HOST_NAME=$(_jq '.name')
        ROLE=$(_jq '.role')
        [[ "$ROLE" == "manager" ]] && continue
        echo "  Installing NFS on ${HOST_NAME} (${HOST_IP})..."
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "${SSH_USER}@${HOST_IP}" \
            'bash -s' < "$REPO/artifacts/scripts/common/nfs_setup.sh" -- "/msr4" client || \
            echo "  WARN: NFS install on ${HOST_NAME} had issues"
    done
    echo "=== NFS client packages installed ==="
fi

# 9. Install MSR4 (if MSR_VERSION set)
if [[ -n "$MSR_VERSION" ]]; then
    MSR_DOMAIN="msr4.${ROOT_DOMAIN}"
    echo ""
    echo "=== Installing MSR4 ${MSR_VERSION} ==="
    KUBECONFIG="$REPO/artifacts/configs/kubeconfig.yaml" \
        "$REPO/artifacts/scripts/msr4/install_msr4.sh" \
        --msr-version "$MSR_VERSION" \
        --domain "$MSR_DOMAIN" \
        --yes
    echo "MSR4 ${MSR_VERSION} installed at https://${MSR_DOMAIN}"
else
    echo ""
    echo "=== Skipping MSR4 (MSR_VERSION not set) ==="
fi
