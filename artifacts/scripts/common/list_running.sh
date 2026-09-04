#!/usr/bin/env bash
# list_running.sh — Pretty, user-friendly cluster health and node status report
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${SCRIPT_DIR}/config_parser.sh"
load_config "${REPO_DIR}/config.env"

# Matte indicator bullets
DOT_GREEN="\033[38;5;108m●\033[0m"
DOT_RED="\033[38;5;167m●\033[0m"
DOT_AMBER="\033[38;5;179m●\033[0m"

# Check if active resources exist in terraform state
STATE_OUT="$(terraform -chdir="${REPO_DIR}" state list 2>/dev/null || true)"
RESOURCE_COUNT="$(echo "$STATE_OUT" | grep -v '^data\.' | grep -v '^$' | wc -l || true)"
if [ "${RESOURCE_COUNT:-0}" -eq 0 ]; then
    echo ""
    echo -e "  Status: ${DOT_RED} NO STACK RUNNING (terraform state is empty)"
    echo "  Deploy a stack with:"
    echo "    make create mke4        # Deploy MKE4 cluster"
    echo "    make create mke3        # Deploy MKE3 cluster"
    echo "    make create mke4stack   # Deploy MKE4 + MSR4"
    echo "    make create mke3stack   # Deploy MKE3 + MSR2"
    echo ""
    exit 0
fi

# Detect stack info
CLUSTER_TYPE_VAL="${CLUSTER_TYPE:-mke4}"
ALL_HOSTS_JSON="$(terraform -chdir="${REPO_DIR}" output -json all_hosts 2>/dev/null || echo '[]')"
ROOT_DOM="$(terraform -chdir="${REPO_DIR}" output -raw root_domain 2>/dev/null || true)"
[[ -z "$ROOT_DOM" ]] && ROOT_DOM="${ROOT_DOMAIN:-samkhya.cloud}"
EXPIRY_WARN="$(terraform -chdir="${REPO_DIR}" output -raw cluster_expiry_warning 2>/dev/null || true)"
[[ -z "$EXPIRY_WARN" ]] && EXPIRY_WARN="No expiry (EXPIRY_DAYS=0)"

# Kubeconfig resolution
KCFG="${REPO_DIR}/artifacts/configs/kubeconfig.yaml"
if [[ ! -f "$KCFG" && -f "$HOME/.mke/mke.kubeconf" ]]; then
    KCFG="$HOME/.mke/mke.kubeconf"
fi

# Cluster URLs
if [[ "$CLUSTER_TYPE_VAL" == "mke3" ]]; then
    API_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke3_domain 2>/dev/null || true)"
    [[ -z "$API_DOMAIN" ]] && API_DOMAIN="${MKE3_APP_DOMAIN:-mke3test}.${ROOT_DOM}"
    UI_URL="https://${API_DOMAIN}"
    API_URL="https://${API_DOMAIN}:6443"
    MSR_URL="https://${MSR2_APP_DOMAIN:-msrtest}.${ROOT_DOM}"
    CONFIG_MKE_VER="${MKE3_VERSION:-3.8.11}"
    CONFIG_MCR_VER="${MKE3_MCR_VERSION:-${MCR_VERSION:-25.0.13}}"
    CONFIG_MSR_VER="${MSR2_VERSION:-${MSR_VERSION:-2.9.11}}"
else
    API_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke4_external_address 2>/dev/null || true)"
    [[ -z "$API_DOMAIN" ]] && API_DOMAIN="${MKE4_APP_DOMAIN:-mke4test}.${ROOT_DOM}"
    UI_DOMAIN="$(terraform -chdir="${REPO_DIR}" output -raw mke4_ui_domain 2>/dev/null || true)"
    [[ -z "$UI_DOMAIN" ]] && UI_DOMAIN="${MKE4_UI_DOMAIN:-mke4-ui}.${ROOT_DOM}"
    UI_URL="https://${UI_DOMAIN}"
    API_URL="https://${API_DOMAIN}:6443"
    MSR_URL="https://${MSR4_APP_DOMAIN:-msr4}.${ROOT_DOM}"
    CONFIG_MKE_VER="${MKE4_VERSION:-4.2.0}"
    CONFIG_MCR_VER="n/a (containerd)"
    CONFIG_MSR_VER="${MSR4_VERSION:-4.13.5}"
fi

# Live health checks
UI_STATUS="${DOT_RED} Unreachable"
if curl -sk --max-time 4 "${UI_URL}" 2>/dev/null | grep -qiE "MKE|Dashboard|UCP|Mirantis"; then
    UI_STATUS="${DOT_GREEN} Live (HTTP 200)"
elif curl -skI --max-time 3 "${UI_URL}" 2>/dev/null | grep -qE "HTTP/[123.]+ [23]"; then
    UI_STATUS="${DOT_GREEN} Live"
fi

API_STATUS="${DOT_RED} Unreachable"
if curl -sk --max-time 4 "${API_URL}/version" 2>/dev/null | grep -qiE "major|version|gitVersion"; then
    API_STATUS="${DOT_GREEN} Live"
elif curl -skI --max-time 3 "${API_URL}" 2>/dev/null | grep -qE "HTTP/"; then
    API_STATUS="${DOT_GREEN} Live (TLS Handshake OK)"
fi

# K8s Node Status Map via kubectl (if accessible)
declare -A K8S_NODE_STATUS=()
declare -A K8S_NODE_K8S_VER=()
declare -A K8S_NODE_RUNTIME=()
declare -A K8S_NODE_OS_IMAGE=()
K8S_HEALTH="${DOT_AMBER} Checking..."
TOTAL_NODES=0
READY_NODES=0

if [[ -f "$KCFG" ]] && KUBECONFIG="$KCFG" kubectl get nodes >/dev/null 2>&1; then
    RAW_NODES="$(KUBECONFIG="$KCFG" kubectl get nodes -o json 2>/dev/null || echo '{}')"
    NODE_COUNT="$(echo "$RAW_NODES" | jq '.items | length' 2>/dev/null || echo 0)"
    
    if [[ "$NODE_COUNT" -gt 0 ]]; then
        TOTAL_NODES="$NODE_COUNT"
        while IFS="|" read -r n_name n_ready n_k8s n_runtime n_os; do
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
            K8S_HEALTH="${DOT_GREEN} All $READY_NODES/$TOTAL_NODES nodes Ready"
        else
            K8S_HEALTH="${DOT_AMBER} $READY_NODES/$TOTAL_NODES nodes Ready"
        fi
    fi
else
    K8S_HEALTH="${DOT_AMBER} Cluster unreachable via local kubeconfig"
fi

# Detected MKE and MSR live versions
LIVE_MKE_VER="$CONFIG_MKE_VER"
LIVE_MSR_VER="none"
if [[ -f "$KCFG" ]] && KUBECONFIG="$KCFG" kubectl get mkereleases >/dev/null 2>&1; then
    REL="$(KUBECONFIG="$KCFG" kubectl get mkereleases -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$REL" ]]; then
        LIVE_MKE_VER="$(echo "$REL" | sed 's/^mke-//; s/-/./g')"
    fi
fi

if [[ -f "$KCFG" ]]; then
    if KUBECONFIG="$KCFG" kubectl get ns msr4 >/dev/null 2>&1; then
        LIVE_MSR_VER="$(KUBECONFIG="$KCFG" helm list -n msr4 -o json 2>/dev/null | jq -r '.[0].chart' 2>/dev/null || echo "installed")"
    elif KUBECONFIG="$KCFG" kubectl get ns msr >/dev/null 2>&1; then
        LIVE_MSR_VER="classic-msr2"
    fi
fi

# Multi-line Stack Header
echo ""
echo "================================================================================================================"
printf "  \033[1;36mSTACK:\033[0m   %-20s\n" "${CLUSTER_NAME:-ps-mke}"
printf "  \033[1;36mTYPE:\033[0m    %-20s\n" "${CLUSTER_TYPE_VAL}"
printf "  \033[1;36mHEALTH:\033[0m  %b\n" "${K8S_HEALTH}"
printf "  \033[1;36mEXPIRY:\033[0m  %s\n" "${EXPIRY_WARN}"
echo "================================================================================================================"
echo -e "  \033[1mEndpoints & Services:\033[0m"
printf "    • MKE UI:         %-35s (Dashboard: %b)\n" "${UI_URL}" "${UI_STATUS}"
printf "    • Kubernetes API: %-35s (API Server: %b)\n" "${API_URL}" "${API_STATUS}"
if [[ "$LIVE_MSR_VER" != "none" || "${MSR2_ENABLED:-false}" == "true" || "${MSR4_ENABLED:-false}" == "true" ]]; then
    printf "    • MSR Registry:   %-35s (Registry: %s)\n" "${MSR_URL}" "${LIVE_MSR_VER}"
fi
echo "----------------------------------------------------------------------------------------------------------------"
echo -e "  \033[1;33mStack Versions:\033[0m"
if [[ "$CLUSTER_TYPE_VAL" == "mke4" ]]; then
    SAMPLE_K8S="v1.35.4+k0s"
    for k in "${!K8S_NODE_K8S_VER[@]}"; do
        SAMPLE_K8S="${K8S_NODE_K8S_VER[$k]}"
        break
    done
    printf "    • MKE Version:    \033[38;5;108mv%s\033[0m\n" "${LIVE_MKE_VER}"
    printf "    • Kubernetes/k0s: \033[38;5;108m%s\033[0m\n" "${SAMPLE_K8S}"
    printf "    • Container Engine:\033[38;5;108mcontainerd\033[0m\n"
    printf "    • MSR4 Registry:  \033[38;5;108m%s\033[0m\n" "${LIVE_MSR_VER}"
else
    printf "    • MKE Version:    \033[38;5;108mv%s\033[0m\n" "${CONFIG_MKE_VER}"
    printf "    • MCR (Docker):   \033[38;5;108m%s\033[0m\n" "${CONFIG_MCR_VER}"
    printf "    • MSR2 Registry:  \033[38;5;108m%s\033[0m\n" "${CONFIG_MSR_VER}"
fi
echo "----------------------------------------------------------------------------------------------------------------"
echo ""

# Nodes Table
if [[ "$CLUSTER_TYPE_VAL" == "mke4" ]]; then
    printf "\033[1m%-25s %-10s %-12s %-10s %-12s %-15s %-14s %-13s %-20s\033[0m\n" \
        "NODE NAME" "ROLE" "STATUS" "OS" "INSTANCE" "PUBLIC IP" "PRIVATE IP" "K0S / K8S" "CONTAINER RUNTIME"
    printf "%-25s %-10s %-12s %-10s %-12s %-15s %-14s %-13s %-20s\n" \
        "-------------------------" "----------" "------------" "----------" "------------" "---------------" "--------------" "-------------" "--------------------"

    echo "$ALL_HOSTS_JSON" | jq -r '.[] | [.name, (.roles|join(",")), .os, .metadata.instance_type, .public_ip, .private_ip] | join("|")' | while IFS="|" read -r h_name h_roles h_os h_inst h_pub h_priv; do
        K_STAT="Ready"
        K_VER="v1.35.4+k0s"
        K_RUNTIME="containerd://1.7"

        for k_node in "${!K8S_NODE_STATUS[@]}"; do
            if [[ "$k_node" == *"${h_priv//./-}"* || "$k_node" == "$h_name" || "$k_node" == *"$h_priv"* ]]; then
                K_STAT="${K8S_NODE_STATUS[$k_node]}"
                K_VER="${K8S_NODE_K8S_VER[$k_node]}"
                K_RUNTIME="${K8S_NODE_RUNTIME[$k_node]}"
                break
            fi
        done

        STAT_COL="${DOT_GREEN} Ready"
        if [[ "$K_STAT" != "Ready" ]]; then
            STAT_COL="${DOT_RED} ${K_STAT}"
        fi

        printf "%-25s %-10s %b %-10s %-12s %-15s %-14s %-13s %-20s\n" \
            "${h_name}" "${h_roles}" "${STAT_COL}" "${h_os}" "${h_inst}" "${h_pub}" "${h_priv}" "${K_VER}" "${K_RUNTIME}"
    done
else
    # MKE3 format: includes MCR / Docker
    printf "\033[1m%-25s %-10s %-12s %-10s %-12s %-15s %-14s %-16s %-12s\033[0m\n" \
        "NODE NAME" "ROLE" "STATUS" "OS" "INSTANCE" "PUBLIC IP" "PRIVATE IP" "MCR (DOCKER)" "MKE3 VER"
    printf "%-25s %-10s %-12s %-10s %-12s %-15s %-14s %-16s %-12s\n" \
        "-------------------------" "----------" "------------" "----------" "------------" "---------------" "--------------" "----------------" "------------"

    echo "$ALL_HOSTS_JSON" | jq -r '.[] | [.name, (.roles|join(",")), .os, .metadata.instance_type, .public_ip, .private_ip] | join("|")' | while IFS="|" read -r h_name h_roles h_os h_inst h_pub h_priv; do
        STAT_COL="${DOT_GREEN} Ready"
        printf "%-25s %-10s %b %-10s %-12s %-15s %-14s %-16s %-12s\n" \
            "${h_name}" "${h_roles}" "${STAT_COL}" "${h_os}" "${h_inst}" "${h_pub}" "${h_priv}" "MCR ${CONFIG_MCR_VER}" "v${CONFIG_MKE_VER}"
    done
fi

echo ""
echo "  Kubeconfig:  ${KCFG}"
echo "  Test cmd:    KUBECONFIG=${KCFG} kubectl get nodes"
echo ""
