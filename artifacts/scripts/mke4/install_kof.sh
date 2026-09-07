#!/usr/bin/env bash
# install_kof.sh — Install KOF (KubeOnFlux) for MKE4 exactly matching mke4k-lab architecture
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "$REPO/artifacts/scripts/common/config_parser.sh"
load_config "$REPO/config.env"

KOF_DIR="${REPO}/artifacts/configs/kof"
KOF_PROFILE="${KOF_PROFILE:-lean}"
KOF_VERSION="1.8.1"
KOF_REGISTRY="registry.mirantis.com/k0rdent-enterprise"
KUBECONFIG="${KUBECONFIG:-$REPO/artifacts/configs/kubeconfig.yaml}"
[[ ! -f "$KUBECONFIG" && -f "$HOME/.mke/mke.kubeconf" ]] && KUBECONFIG="$HOME/.mke/mke.kubeconf"
export KUBECONFIG

if [[ "$CLUSTER_TYPE" != "mke4" ]]; then
    echo "ERROR: KOF is only supported for MKE4 clusters."
    exit 1
fi

if [[ ! "$KOF_ENABLED" == "true" ]]; then
    echo "KOF not enabled in config (KOF_ENABLED=false). Skipping."
    exit 0
fi

echo ""
echo "=== Installing KOF (KubeOnFlux ${KOF_VERSION}) ==="
echo "  Profile:      ${KOF_PROFILE}"
echo "  Registry:     ${KOF_REGISTRY}"
echo "  Namespace:    kof"
echo ""

# Preflight checks
for tool in helm kubectl; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: KOF requires '${tool}' in PATH."; exit 1; }
done

kubectl get nodes >/dev/null 2>&1 || { echo "ERROR: Cluster not reachable. Deploy cluster first."; exit 1; }

# Resolve StorageClass
resolve_storageclass() {
    local jp='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}'
    local sc
    sc="$(kubectl get sc -o jsonpath="${jp}" 2>/dev/null | head -n1 || true)"
    if [[ -z "${sc}" ]]; then
        if kubectl get sc nfs-storage >/dev/null 2>&1; then
            sc="nfs-storage"
        elif kubectl get sc nfs-client >/dev/null 2>&1; then
            sc="nfs-client"
        else
            sc="nfs-storage"
        fi
    fi
    echo "${sc}"
}

SC="$(resolve_storageclass)"
echo "  StorageClass: ${SC}"

# Exempt kof namespace from MKE ucpauthz admission policy
echo "  Exempting kof from MKE ucpauthz admission policy..."
kubectl patch mkeconfig mke -n mke --type=merge \
    -p '{"spec":{"apiServer":{"ucpauthz":{"exemptNamespaces":["kof"],"exemptUsers":["system:serviceaccount:kof:opentelemetry-operator"]}}}}' >/dev/null 2>&1 || true

# Select pre-rendered values file
VALUES_FILE="${KOF_DIR}/values-${KOF_PROFILE}.yaml"
if [[ ! -f "$VALUES_FILE" ]]; then
    VALUES_FILE="${KOF_DIR}/values-lean.yaml"
fi

# Install official Mirantis KOF Umbrella Chart
echo "  Installing KOF umbrella chart via Helm ($(basename "$VALUES_FILE"))..."
helm upgrade -i --reset-values \
    --create-namespace -n kof kof \
    "oci://${KOF_REGISTRY}/charts/kof" \
    --version "${KOF_VERSION}" \
    -f "${VALUES_FILE}" \
    --set "kof-mothership.values.global.storageClass=${SC}" \
    --set "kof-storage.values.global.storageClass=${SC}"

# Wait for Grafana CRDs and apply Grafana instance
echo "  Applying Grafana instance CR..."
kubectl wait --for=condition=Established crd/grafanas.grafana.integreatly.org --timeout=5m 2>/dev/null || true
kubectl apply -f "${KOF_DIR}/grafana.yaml" -n kof

# Add MKE Prometheus Datasource
kubectl wait --for=condition=Established crd/grafanadatasources.grafana.integreatly.org --timeout=5m 2>/dev/null || true
kubectl apply -f "${KOF_DIR}/mke-prometheus-datasource.yaml" -n kof

# Prune non-applicable dashboards in lean mode
if [[ "${KOF_PROFILE}" == "lean" ]]; then
    echo "  Pruning non-applicable dashboards for lean profile..."
    kubectl get grafanadashboard -n kof -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.folder}{"\n"}{end}' 2>/dev/null \
      | grep -E "Istio|Opencost|Victoria Traces|kps-nodes-aix|kps-nodes-darwin" \
      | awk '{print $1}' \
      | xargs -r kubectl delete grafanadashboard -n kof >/dev/null 2>&1 || true
fi

# Configure Gateway HTTPRoutes & Dex OAuth
"$REPO/artifacts/scripts/mke4/setup_mke4_httproutes.sh"

echo ""
echo "=== KOF Monitoring Ready ==="
echo "  UI URL:    https://${KOF_APP_DOMAIN:-kof-mke}.${ROOT_DOMAIN:-samkhya.cloud}"
