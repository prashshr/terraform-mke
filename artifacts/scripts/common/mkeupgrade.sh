#!/usr/bin/env bash
# mkeupgrade.sh — upgrade MKE/MSR cluster from OLD to NEW versions
# Called via: make upgrade OLD_MKE_VERSION=... NEW_MKE_VERSION=... [OLD_MSR_VERSION=...] [NEW_MSR_VERSION=...]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"

# Load config from single config.env file
source "$REPO/artifacts/scripts/common/config_parser.sh"
load_config "$REPO/config.env"

# ── Defaults ──────────────────────────────────────────────────────────────────
AUTO_YES="${YES:-}"
USE_LOG="${LOG:-}"

OLD_MKE_VERSION="${OLD_MKE_VERSION:-}"
NEW_MKE_VERSION="${NEW_MKE_VERSION:-}"
OLD_MSR_VERSION="${OLD_MSR_VERSION:-}"
NEW_MSR_VERSION="${NEW_MSR_VERSION:-}"
OLD_MCR_VERSION="${OLD_MCR_VERSION:-25.0.13}"
NEW_MCR_VERSION="${NEW_MCR_VERSION:-25.0.13}"

# ── Logging ───────────────────────────────────────────────────────────────────
if [[ "$USE_LOG" == "1" ]]; then
    mkdir -p "$REPO/logs"
    exec > >(tee -a "$REPO/logs/mkeupgrade-$(date +%Y%m%d-%H%M%S).log") 2>&1
fi

# ── Prompt helper ─────────────────────────────────────────────────────────────
ask() {
    [[ "$AUTO_YES" == "1" ]] && return 0
    read -rp "$1 [y/N]: " a
    [[ "$a" =~ ^[Yy]$ ]] || exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────
version_major() { echo "$1" | cut -d. -f1; }
version_minor() { echo "$1" | cut -d. -f1-2; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "=== MKE Upgrade ==="
echo "  Cluster type: $CLUSTER_TYPE"
echo "  MKE:  ${OLD_MKE_VERSION:-<current>} → ${NEW_MKE_VERSION:-<same>}"
echo "  MSR:  ${OLD_MSR_VERSION:-<current>} → ${NEW_MSR_VERSION:-<same>}"
echo "  MCR:  ${OLD_MCR_VERSION} → ${NEW_MCR_VERSION}"
echo ""

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ -z "$NEW_MKE_VERSION" && -z "$NEW_MSR_VERSION" ]]; then
    echo "ERROR: Nothing to upgrade. Set NEW_MKE_VERSION and/or NEW_MSR_VERSION."
    exit 1
fi

ask "Proceed with upgrade?" || exit 1

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1: Install OLD versions if cluster doesn't exist yet
# ══════════════════════════════════════════════════════════════════════════════
phase_install_old() {
    echo ""
    echo "=== Phase 1: Install OLD versions (if needed) ==="

    # Check if cluster already exists
    if terraform -chdir="$REPO" state list &>/dev/null 2>&1; then
        echo "Cluster already exists — skipping OLD version install."
        return 0
    fi

    if [[ -z "$OLD_MKE_VERSION" ]]; then
        echo "No cluster found and OLD_MKE_VERSION not set. Cannot proceed."
        exit 1
    fi

    echo "Installing cluster with MKE ${OLD_MKE_VERSION}..."

    # Clear SSH known_hosts
    rm -f "$HOME/.ssh/known_hosts"

    # Terraform apply with OLD versions
    local TF_ARGS=(-auto-approve -var "cluster_type=$CLUSTER_TYPE")
    if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
        TF_ARGS+=(-var "mke3_version=$OLD_MKE_VERSION")
    else
        TF_ARGS+=(-var "mke4_version=$OLD_MKE_VERSION")
    fi
    terraform -chdir="$REPO" init -input=false
    terraform -chdir="$REPO" apply "${TF_ARGS[@]}"

    # Clear known_hosts again
    rm -f "$HOME/.ssh/known_hosts"

    # Install MKE
    if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
        launchpad apply -c "$REPO/artifacts/configs/launchpad.yaml" --debug
        launchpad client-config -c "$REPO/artifacts/configs/launchpad.yaml"
    else
        MINOR=$(version_minor "$OLD_MKE_VERSION")
        BIN="$REPO/artifacts/bin/mkectl-v$OLD_MKE_VERSION"
        [ -f "$BIN" ] || "$REPO/artifacts/bin/download_mkectl.sh" "$OLD_MKE_VERSION"
        "$BIN" apply -f "$REPO/artifacts/configs/mke4-v$MINOR.yaml" --admin-password "$ADMIN_PASSWORD" -l debug
    fi

    # Refresh kubeconfig
    _refresh_kubeconfig

    # Install OLD MSR if specified
    if [[ -n "$OLD_MSR_VERSION" ]]; then
        _install_msr "$OLD_MSR_VERSION"
    fi

    echo "OLD version install complete."
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2: Upgrade MKE
# ══════════════════════════════════════════════════════════════════════════════
phase_upgrade_mke() {
    echo ""
    echo "=== Phase 2: Upgrade MKE ==="

    if [[ -z "$NEW_MKE_VERSION" ]]; then
        echo "NEW_MKE_VERSION not set — skipping MKE upgrade."
        return 0
    fi

    # Detect current MKE version from config
    local CURRENT_MKE=""
    if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
        CURRENT_MKE="$MKE3_VERSION"
    else
        CURRENT_MKE="$MKE4_VERSION"
    fi

    if [[ "$CURRENT_MKE" == "$NEW_MKE_VERSION" ]]; then
        echo "MKE already at version ${NEW_MKE_VERSION} — skipping."
        return 0
    fi

    local OLD_MAJOR=$(version_major "$NEW_MKE_VERSION")
    local OLD_MINOR=$(version_minor "${OLD_MKE_VERSION:-$CURRENT_MKE}")
    local NEW_MINOR=$(version_minor "$NEW_MKE_VERSION")

    echo "Upgrading MKE: ${CURRENT_MKE:-unknown} → ${NEW_MKE_VERSION}"
    echo "  Old major.minor: ${OLD_MINOR}"
    echo "  New major.minor: ${NEW_MINOR}"

    if [[ "$CLUSTER_TYPE" == "mke3" ]]; then
        # MKE3 → MKE4 major upgrade
        if [[ "$OLD_MAJOR" == "3" && $(version_major "$NEW_MKE_VERSION") == "4" ]]; then
            echo "Detected MKE3 → MKE4 major upgrade."
            _upgrade_mke3_to_mke4
        else
            echo "MKE3 minor upgrades are not supported via this tool."
            echo "Use Docker EE upgrade procedures for MKE3 → MKE3."
            return 0
        fi
    else
        # MKE4 → MKE4 (minor/patch)
        _upgrade_mke4 "$NEW_MKE_VERSION"
    fi

    _refresh_kubeconfig
    echo "MKE upgrade complete."
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3: Upgrade MSR
# ══════════════════════════════════════════════════════════════════════════════
phase_upgrade_msr() {
    echo ""
    echo "=== Phase 3: Upgrade MSR ==="

    if [[ -z "$NEW_MSR_VERSION" ]]; then
        echo "NEW_MSR_VERSION not set — skipping MSR upgrade."
        return 0
    fi

    local OLD_MAJOR=$(version_major "${OLD_MSR_VERSION:-0}")
    local NEW_MAJOR=$(version_major "$NEW_MSR_VERSION")

    echo "MSR upgrade: ${OLD_MSR_VERSION:-unknown} → ${NEW_MSR_VERSION}"
    echo "  Old major: ${OLD_MAJOR}"
    echo "  New major: ${NEW_MAJOR}"

    # Different major version → not an upgrade, just install
    if [[ "$OLD_MAJOR" != "$NEW_MAJOR" && "$OLD_MSR_VERSION" != "" ]]; then
        echo "Major version change detected (${OLD_MSR_VERSION} → ${NEW_MSR_VERSION})."
        echo "This is not an upgrade — installing MSR${NEW_MAJOR} fresh."

        # Remove old MSR if it exists
        _uninstall_msr

        # Install new MSR
        _install_msr "$NEW_MSR_VERSION"
        return 0
    fi

    # Same major version → upgrade
    echo "Upgrading MSR within same major version..."
    _upgrade_msr "$NEW_MSR_VERSION"
    echo "MSR upgrade complete."
}

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 4: Upgrade MCR (node-by-node)
# ══════════════════════════════════════════════════════════════════════════════
phase_upgrade_mcr() {
    echo ""
    echo "=== Phase 4: Upgrade MCR ==="

    if [[ "$OLD_MCR_VERSION" == "$NEW_MCR_VERSION" ]]; then
        echo "MCR already at version ${NEW_MCR_VERSION} — skipping."
        return 0
    fi

    echo "MCR upgrade: ${OLD_MCR_VERSION} → ${NEW_MCR_VERSION}"
    echo "NOTE: MCR upgrades require node-by-node maintenance."
    echo "Use the upgrade_mcr.sh script for node-by-node MCR upgrades."
    echo "Skipping automatic MCR upgrade."
}

# ══════════════════════════════════════════════════════════════════════════════
# Helper functions
# ══════════════════════════════════════════════════════════════════════════════

_refresh_kubeconfig() {
    echo "Refreshing kubeconfig..."
    local MANAGER_IP=$(terraform -chdir="$REPO" output -json all_hosts 2>/dev/null | jq -r '.[0].public_ip')
    local SSH_KEY=$(find "$REPO/artifacts/ssh" -name '*.pem' | head -1)
    local SSH_USER="ec2-user"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "${SSH_USER}@${MANAGER_IP}" \
        "sudo cat /var/lib/k0s/pki/admin.conf" > "$REPO/artifacts/configs/kubeconfig.yaml"
    sed -i "s|server: .*|server: https://${MANAGER_IP}:6443|" "$REPO/artifacts/configs/kubeconfig.yaml"
    export KUBECONFIG="$REPO/artifacts/configs/kubeconfig.yaml"
    echo "Kubeconfig refreshed from manager ${MANAGER_IP}"
}

_upgrade_mke3_to_mke4() {
    echo "Running MKE3 → MKE4 upgrade..."

    # Step 1: Run prereq (calico_kdd)
    echo "Running MKE3 upgrade prerequisite (calico_kdd)..."
    "$REPO/artifacts/scripts/mke3/mke3_upgrade_prereq.sh"

    # Step 2: Run mkectl upgrade
    echo "Running mkectl upgrade..."
    local ENV_FILE="$REPO/artifacts/configs/mkectl-upgrade.env"
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "ERROR: mkectl-upgrade.env not found. Run terraform apply first."
        exit 1
    fi

    set -a
    . "$ENV_FILE"
    set +a

    # Download mkectl if needed
    local BIN="$REPO/artifacts/bin/mkectl-v$NEW_MKE_VERSION"
    [ -f "$BIN" ] || "$REPO/artifacts/bin/download_mkectl.sh" "$NEW_MKE_VERSION"

    "$BIN" upgrade \
        --hosts-path "$MKCTL_UPGRADE_HOSTS_PATH" \
        --mke3-admin-username "$MKCTL_UPGRADE_ADMIN_USERNAME" \
        --mke3-admin-password "$MKCTL_UPGRADE_ADMIN_PASSWORD" \
        --mke3-external-address "$MKCTL_MKE3_EXTERNAL_ADDRESS" \
        --external-address "$MKCTL_UPGRADE_EXTERNAL_ADDRESS" \
        -l debug \
        --skip-cpu-cores-check \
        --skip-total-memory-check \
        --cni-check-port 81 \
        --gateway-http-node-port "$MKCTL_UPGRADE_GATEWAY_HTTP_NODE_PORT" \
        --gateway-https-node-port "$MKCTL_UPGRADE_GATEWAY_HTTPS_NODE_PORT" \
        --force

    # Update CLUSTER_TYPE and version in tfvars
    sed -i "s/cluster_type\s*=.*/cluster_type = \"mke4\"/" "$TF"
    sed -i "s/mke4_version\s*=.*/mke4_version = \"$NEW_MKE_VERSION\"/" "$TF"
}

_upgrade_mke4() {
    local target_version="$1"
    local MINOR=$(version_minor "$target_version")

    echo "Upgrading MKE4 to ${target_version}..."

    # Ensure mkectl is available
    local BIN="$REPO/artifacts/bin/mkectl-v$target_version"
    [ -f "$BIN" ] || "$REPO/artifacts/bin/download_mkectl.sh" "$target_version"

    # Update tfvars
    sed -i "s/mke4_version\s*=.*/mke4_version = \"$target_version\"/" "$TF"

    # Re-render config with new template
    terraform -chdir="$REPO" apply -auto-approve -var "cluster_type=mke4" -var "mke4_version=$target_version"

    # Apply with mkectl
    "$BIN" apply -f "$REPO/artifacts/configs/mke4-v$MINOR.yaml" --admin-password "$ADMIN_PASSWORD" -l debug
}

_install_nfs_clients() {
    echo "Installing NFS client packages on all worker nodes..."
    local SSH_KEY=$(find "$REPO/artifacts/ssh" -name '*.pem' | head -1)
    local SSH_USER="ec2-user"
    local ALL_HOSTS=$(terraform -chdir="$REPO" output -json all_hosts 2>/dev/null)

    for row in $(echo "$ALL_HOSTS" | jq -r '.[] | @base64'); do
        _jq() { echo "$row" | base64 -d | jq -r "$1"; }
        local HOST_IP=$(_jq '.public_ip')
        local HOST_NAME=$(_jq '.name')
        local ROLE=$(_jq '.role')
        [[ "$ROLE" == "manager" ]] && continue
        echo "  Installing NFS on ${HOST_NAME} (${HOST_IP})..."
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" "${SSH_USER}@${HOST_IP}" \
            'bash -s' < "$REPO/artifacts/scripts/common/nfs_setup.sh" -- "/msr4" client || \
            echo "  WARN: NFS install on ${HOST_NAME} had issues"
    done
    echo "NFS client packages installed."
}

_install_msr() {
    local version="$1"
    local domain="msr4.${ROOT_DOMAIN}"

    # Ensure NFS client packages are installed before MSR4 Helm install
    _install_nfs_clients

    echo "Installing MSR4 ${version}..."
    KUBECONFIG="$REPO/artifacts/configs/kubeconfig.yaml" \
        "$REPO/artifacts/scripts/msr4/install_msr4.sh" \
        --msr-version "$version" \
        --domain "$domain" \
        --yes
}

_uninstall_msr() {
    echo "Uninstalling existing MSR..."
    # Try MSR4 (Helm)
    if kubectl get namespace msr4 &>/dev/null 2>&1; then
        helm uninstall msr4 -n msr4 2>/dev/null || true
        kubectl delete namespace msr4 --timeout=120s 2>/dev/null || true
        echo "MSR4 uninstalled."
    fi
    # Try MSR2/3 (launchpad)
    if [[ -f "$REPO/artifacts/configs/launchpad.yaml" ]]; then
        local MSR_VER=$(grep -A2 'msr:' "$REPO/artifacts/configs/launchpad.yaml" | grep 'version:' | awk '{print $2}')
        if [[ -n "$MSR_VER" ]]; then
            echo "MSR found in launchpad config (version ${MSR_VER}). Use launchpad to remove MSR."
        fi
    fi
    if ! kubectl get namespace msr4 &>/dev/null 2>&1; then
        echo "No MSR found — nothing to uninstall."
    fi
}

_upgrade_msr() {
    local new_version="$1"
    local new_major=$(version_major "$new_version")
    local old_major=$(version_major "${OLD_MSR_VERSION:-0}")

    echo "Upgrading MSR${new_major} to ${new_version}..."

    if [[ "$new_major" == "4" ]]; then
        # MSR4: Helm upgrade
        local VALUES_FILE="$REPO/artifacts/configs/msr4/values/msr-values-${new_version}-single.yaml"
        if [[ ! -f "$VALUES_FILE" ]]; then
            echo "Generating Helm values for MSR ${new_version}..."
            "$REPO/artifacts/scripts/msr4/generate_msr_values.sh" "$new_version"
        fi

        helm upgrade msr4 harbor/helm/msr \
            --namespace msr4 \
            --version "$new_version" \
            -f "$VALUES_FILE" \
            -f "$REPO/artifacts/configs/msr4/values/msr4-overrides.yaml" \
            --wait --timeout 30m
    elif [[ "$new_major" == "2" ]]; then
        # MSR2.9.x → MSR2.9.y: Launchpad upgrade
        echo "Upgrading MSR2 via launchpad..."
        local LAUNCHPAD_YAML="$REPO/artifacts/configs/launchpad.yaml"
        if [[ ! -f "$LAUNCHPAD_YAML" ]]; then
            echo "ERROR: launchpad.yaml not found. Cannot upgrade MSR2."
            exit 1
        fi
        # Update MSR version in launchpad config
        sed -i "s|version: .*|version: ${new_version}|" "$LAUNCHPAD_YAML"
        launchpad apply -c "$LAUNCHPAD_YAML" --debug
        echo "MSR2 upgraded to ${new_version}"
    elif [[ "$new_major" == "3" ]]; then
        # MSR3: Launchpad upgrade (same as MSR2)
        echo "Upgrading MSR3 via launchpad..."
        local LAUNCHPAD_YAML="$REPO/artifacts/configs/launchpad.yaml"
        if [[ ! -f "$LAUNCHPAD_YAML" ]]; then
            echo "ERROR: launchpad.yaml not found. Cannot upgrade MSR3."
            exit 1
        fi
        sed -i "s|version: .*|version: ${new_version}|" "$LAUNCHPAD_YAML"
        launchpad apply -c "$LAUNCHPAD_YAML" --debug
        echo "MSR3 upgraded to ${new_version}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════════
phase_install_old
phase_upgrade_mke
phase_upgrade_msr
phase_upgrade_mcr

echo ""
echo "=== Upgrade Complete ==="
echo "  MKE: ${NEW_MKE_VERSION:-unchanged}"
echo "  MSR: ${NEW_MSR_VERSION:-unchanged}"
echo "  MCR: ${NEW_MCR_VERSION:-unchanged}"
echo ""
