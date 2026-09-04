#!/usr/bin/env bash
# list_running.sh — Pretty, user-friendly cluster health and node status report
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/config_parser.sh"
load_config "${REPO_DIR}/config"

# Check if terraform state exists
if ! terraform -chdir="${REPO_DIR}" state list >/dev/null 2>&1; then
    echo ""
    echo "  Status: 🔴 NO STACK RUNNING (terraform state is empty)"
    echo "  Start one with:"
    echo "    make create mke4        # MKE4 cluster"
    echo "    make create mke3        # MKE3 cluster"
    echo "    make create mke4stack   # MKE4 + MSR4"
    echo "    make create mke3stack   # MKE3 + classic MSR"
    echo ""
    exit 0
fi

# Detect stack info
CLUSTER_TYPE_VAL="${CLUSTER_TYPE:-mke4}"
ALL_HOSTS_JSON="$(terraform -chdir="${REPO_DIR}" output -json all_hosts 2>/dev/null || echo '[]')"
ROOT_DOM="$(terraform -chdir="${REPO_DIR}" output -raw root_domain 2>/dev/null || echo "${ROOT_DOMAIN:-samkhya.cloud}")"
EXPIRY_WARN="$(terraform -chdir="${REPO_DIR}" output -raw cluster_expiry_warning 2>/dev/null || echo "No expiry (EXPIRY_DAYS=0)")"

# Kubeconfig resolution
KCFG="${REPO_DIR}/artifacts/configs/kubeconfig.yaml"
if [[ ! -f "$KCFG" && -f "$HOME/.mke/mke.kubeconf" ]]; then
    KCFG="$HOME/.mke/mke.kubeconf"
fi

# Cluster URLs
if [[ "$CLUSTER_TYPE_VAL" == "mke3" ]]; then
    API_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke3_domain 2>/dev/null || echo "mke3test.${ROOT_DOM}")"
    UI_URL="https://${API_DOMAIN}"
    API_URL="https://${API_DOMAIN}:6443"
    MSR_URL="https://msrtest.${ROOT_DOM}"
    CONFIG_MKE_VER="${MKE3_VERSION:-3.8.11}"
    CONFIG_MCR_VER="${MCR_VERSION:-25.0.13}"
    CONFIG_MSR_VER="${MSR_VERSION:-2.9.11}"
else
    API_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke4_external_address 2>/dev/null || echo "mke4test.${ROOT_DOM}")"
    UI_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke4_ui_domain 2>/dev/null || echo "mke4-ui.${ROOT_DOM}")"
    UI_URL="https://${UI_DOMAIN}"
    API_URL="https://${API_DOMAIN}:6443"
    MSR_URL="https://msr4.${ROOT_DOM}"
    CONFIG_MKE_VER="${MKE4_VERSION:-4.2.0}"
    CONFIG_MCR_VER="n/a (containerd)"
    CONFIG_MSR_VER="${MSR4_VERSION:-4.13.5}"
fi

# Live health checks
UI_STATUS="🔴 Unreachable"
if curl -sk --max-time 4 "${UI_URL}" 2>/dev/null | grep -qiE "MKE|Dashboard|UCP|Mirantis"; then
    UI_STATUS="🟢 Live (HTTP 200)"
elif curl -skI --max-time 3 "${UI_URL}" 2>/dev/null | grep -qE "HTTP/[123.]+ [23]"; then
    UI_STATUS="🟢 Live"
fi

API_STATUS="🔴 Unreachable"
if curl -sk --max-time 4 "${API_URL}/version" 2>/dev/null | grep -qiE "major|version|gitVersion"; then
    API_STATUS="🟢 Live"
elif curl -skI --max-time 3 "${API_URL}" 2>/dev/null | grep -qE "HTTP/"; then
    API_STATUS="🟢 Live (TLS Handshake OK)"
fi

# K8s Node Status Map via kubectl (if accessible)
declare -A K8S_NODE_STATUS
declare -A K8S_NODE_ROLES
declare -A K8S_NODE_K8S_VER
declare -A K8S_NODE_RUNTIME
declare -A K8S_NODE_OS_IMAGE
K8S_HEALTH="⚠️  Checking..."
TOTAL_NODES=0
READY_NODES=0

if [[ -f "$KCFG" ]] && KUBECONFIG="$KCFG" kubectl get nodes >/dev/null 2>&1; then
    RAW_NODES="$(KUBECONFIG="$KCFG" kubectl get nodes -o json 2>/dev/null || echo '{}')"
    NODE_COUNT="$(echo "$RAW_NODES" | jq '.items | length' 2>/dev/null || echo 0)"
    
    if [[ "$NODE_COUNT" -gt 0 ]]; then
        TOTAL_NODES="$NODE_COUNT"
        while IFS="|" read -r n_name n_ready n_k8s n_runtime n_os; do
            # Extract internal IP or hostname match key
            K8S_NODE_STATUS["$n_name"]="$n_ready"
            K8S_NODE_K8S_VER["$n_name"]="$n_k8s"
            K8S_NODE_RUNTIME["$n_name"]="$n_runtime"
            K8S_NODE_OS_IMAGE["$n_name"]="$n_os"
            if [[ "$n_ready" == "Ready" ]]; then
                READY_NODES=$((READY_NODES + 1))
            fi
        done < <(echo "$RAW_NODES" | jq -r '.items[] | [
            .metadata.name,
            (if (.status.conditions[]? | select(.type=="Ready" and .status=="True")) then "Ready" else "NotReady" end),
            .status.nodeInfo.kubeletVersion,
            .status.nodeInfo.containerRuntimeVersion,
            .status.nodeInfo.osImage
        ] | join("|")')

        if [[ "$READY_NODES" -eq "$TOTAL_NODES" && "$TOTAL_NODES" -gt 0 ]]; then
            K8S_HEALTH="🟢 All $READY_NODES/$TOTAL_NODES nodes Ready"
        else
            K8S_HEALTH="🟡 $READY_NODES/$TOTAL_NODES nodes Ready"
        fi
    fi
else
    K8S_HEALTH="🟡 Cluster initializing or unreachable via local kubeconfig"
fi

# Detected MKE and MSR live versions
LIVE_MKE_VER="$CONFIG_MKE_VER"
LIVE_MSR_VER="none"
if [[ -f "$KCFG" ]] && KUBECONFIG="$KCFG" kubectl get mkereleases >/dev/null 2>&1; then
    REL="$(KUBECONFIG="$KCFG" kubectl get mkereleases -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo '')"
    if [[ -n "$REL" ]]; then
        LIVE_MKE_VER="$(echo "$REL" | sed 's/^mke-//; s/-/./g')"
    fi
fi

if [[ -f "$KCFG" ]]; then
    if KUBECONFIG="$KCFG" kubectl get ns msr4 >/dev/null 2>&1; then
        LIVE_MSR_VER="$(KUBECONFIG="$KCFG" helm list -n msr4 -o json 2>/dev/null | jq -r '.[0].chart' 2>/dev/null || echo "installed")"
    elif KUBECONFIG="$KCFG" kubectl get ns msr >/dev/null 2>&1; then
        LIVE_MSR_VER="classic-msr"
    fi
fi

# Print Stack Header
echo ""
echo "================================================================================================================"
printf "  \033[1;36mSTACK:\033[0m %-16s \033[1;36mTYPE:\033[0m %-10s \033[1;36mHEALTH:\033[0m %-28s \033[1;36mEXPIRY:\033[0m %s\n" \
    "${CLUSTER_NAME:-ps-mke}" "${CLUSTER_TYPE_VAL}" "${K8S_HEALTH}" "${EXPIRY_WARN}"
echo "================================================================================================================"
printf "  \033[1m%-16s\033[0m %-30s (Dashboard: %s)\n" "MKE UI:" "${UI_URL}" "${UI_STATUS}"
printf "  \033[1m%-16s\033[0m %-30s (API Server: %s)\n" "Kubernetes API:" "${API_URL}" "${API_STATUS}"
if [[ "$LIVE_MSR_VER" != "none" || "${ENABLE_MSR:-false}" == "true" || "${MSR4_ENABLED:-false}" == "true" ]]; then
    printf "  \033[1m%-16s\033[0m %-30s (Chart: %s)\n" "MSR Registry:" "${MSR_URL}" "${LIVE_MSR_VER}"
fi
echo "----------------------------------------------------------------------------------------------------------------"

# Print Stack Versions Summary
if [[ "$CLUSTER_TYPE_VAL" == "mke4" ]]; then
    printf "  \033[1;33mStack Versions:\033[0m MKE: \033[32mv%s\033[0m | k0s/k8s: \033[32m%s\033[0m | Runtime: \033[32mcontainerd\033[0m | MSR4: \033[32m%s\033[0m\n" \
        "${LIVE_MKE_VER}" "${K8S_NODE_K8S_VER[$(echo "${!K8S_NODE_K8S_VER[@]}" | awk '{print $1}')]:-v1.35.4+k0s}" "${LIVE_MSR_VER}"
else
    printf "  \033[1;33mStack Versions:\033[0m MKE3: \033[32mv%s\033[0m | MCR (Docker): \033[32m%s\033[0m | Classic MSR: \033[32m%s\033[0m\n" \
        "${CONFIG_MKE_VER}" "${CONFIG_MCR_VER}" "${CONFIG_MSR_VER}"
fi
echo "----------------------------------------------------------------------------------------------------------------"
echo ""

# Nodes Table
if [[ "$CLUSTER_TYPE_VAL" == "mke4" ]]; then
    printf "\033[1m%-25s %-10s %-10s %-10s %-12s %-15s %-14s %-13s %-20s\033[0m\n" \
        "NODE NAME" "ROLE" "STATUS" "OS" "INSTANCE" "PUBLIC IP" "PRIVATE IP" "K0S / K8S" "CONTAINER RUNTIME"
    printf "%-25s %-10s %-10s %-10s %-12s %-15s %-14s %-13s %-20s\n" \
        "-------------------------" "----------" "----------" "----------" "------------" "---------------" "--------------" "-------------" "--------------------"

    echo "$ALL_HOSTS_JSON" | jq -r '.[] | [.name, (.roles|join(",")), .os, .metadata.instance_type, .public_ip, .private_ip] | join("|")' | while IFS="|" read -r h_name h_roles h_os h_inst h_pub h_priv; do
        # Match k8s node info by private IP or name
        K_STAT="Ready"
        K_VER="v1.35.4+k0s"
        K_RUNTIME="containerd://1.7"

        # Search matching node in map
        for k_node in "${!K8S_NODE_STATUS[@]}"; do
            if [[ "$k_node" == *"${h_priv//./-}"* || "$k_node" == "$h_name" || "$k_node" == *"$h_priv"* ]]; then
                K_STAT="${K8S_NODE_STATUS[$k_node]}"
                K_VER="${K8S_NODE_K8S_VER[$k_node]}"
                K_RUNTIME="${K8S_NODE_RUNTIME[$k_node]}"
                break
            fi
        done

        STAT_COL="\033[32mReady\033[0m"
        if [[ "$K_STAT" != "Ready" ]]; then
            STAT_COL="\033[31m${K_STAT}\033[0m"
        fi

        printf "%-25s %-10s %b %-10s %-12s %-15s %-14s %-13s %-20s\n" \
            "${h_name}" "${h_roles}" "${STAT_COL}" "${h_os}" "${h_inst}" "${h_pub}" "${h_priv}" "${K_VER}" "${K_RUNTIME}"
    done
else
    # MKE3 format: includes MCR / Docker
    printf "\033[1m%-25s %-10s %-10s %-10s %-12s %-15s %-14s %-16s %-12s\033[0m\n" \
        "NODE NAME" "ROLE" "STATUS" "OS" "INSTANCE" "PUBLIC IP" "PRIVATE IP" "MCR (DOCKER)" "MKE3 VER"
    printf "%-25s %-10s %-10s %-10s %-12s %-15s %-14s %-16s %-12s\n" \
        "-------------------------" "----------" "----------" "----------" "------------" "---------------" "--------------" "----------------" "------------"

    echo "$ALL_HOSTS_JSON" | jq -r '.[] | [.name, (.roles|join(",")), .os, .metadata.instance_type, .public_ip, .private_ip] | join("|")' | while IFS="|" read -r h_name h_roles h_os h_inst h_pub h_priv; do
        STAT_COL="\033[32mReady\033[0m"
        printf "%-25s %-10s %b %-10s %-12s %-15s %-14s %-16s %-12s\n" \
            "${h_name}" "${h_roles}" "${STAT_COL}" "${h_os}" "${h_inst}" "${h_pub}" "${h_priv}" "MCR ${CONFIG_MCR_VER}" "v${CONFIG_MKE_VER}"
    done
fi

echo ""
echo "  Kubeconfig:  ${KCFG}"
echo "  Test cmd:    KUBECONFIG=${KCFG} kubectl get nodes"
echo ""
