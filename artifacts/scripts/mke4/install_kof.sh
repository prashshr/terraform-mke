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
KOF_KCM_NAMESPACE="k0rdent"
KOF_GRAFANA_IMAGE_TAG="11.0.0"
KOF_STORAGE_SIZE="10Gi"
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
echo "  Namespace:    kof (KCM: ${KOF_KCM_NAMESPACE})"
echo ""

# Preflight checks
for tool in yq jq helm kubectl; do
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
            echo "ERROR: No default StorageClass found. Deploy NFS storage first."
            exit 1
        fi
    fi
    echo "${sc}"
}

SC="$(resolve_storageclass)"
echo "  StorageClass: ${SC}"

# Exempt kof namespace from MKE ucpauthz admission policy
exempt_ucpauthz() {
    local ns_sa="system:serviceaccount:kof:opentelemetry-operator"
    local cfg
    cfg="$(mktemp "${TMPDIR:-/tmp}/kof-ucpauthz-XXXX.yaml")"
    if [ -f "$REPO/artifacts/bin/mkectl-v4.2.0" ]; then
        "$REPO/artifacts/bin/mkectl-v4.2.0" config get 2>/dev/null | sed -n '/^apiVersion:/,$p' > "${cfg}" || true
        if [ -s "${cfg}" ]; then
            if ! NS_SA="${ns_sa}" yq -e '
                ((.spec.apiServer.ucpauthz.exemptNamespaces // []) | contains(["kof"]))
                and ((.spec.apiServer.ucpauthz.exemptUsers // []) | contains([strenv(NS_SA)]))
            ' "${cfg}" >/dev/null 2>&1; then
                echo "  Exempting kof from MKE ucpauthz policy..."
                NS_SA="${ns_sa}" yq -i '
                    .spec.apiServer.ucpauthz.disabled = (.spec.apiServer.ucpauthz.disabled // false)
                  | .spec.apiServer.ucpauthz.exemptNamespaces = ((.spec.apiServer.ucpauthz.exemptNamespaces // []) + ["kof"] | unique)
                  | .spec.apiServer.ucpauthz.exemptUsers = ((.spec.apiServer.ucpauthz.exemptUsers // []) + [strenv(NS_SA)] | unique)
                ' "${cfg}"
                "$REPO/artifacts/bin/mkectl-v4.2.0" apply -f "${cfg}" --skip-helm-extensions-check --skip-cni-check --lease-adopt-stale >/dev/null 2>&1 || true
            fi
        fi
    fi
    rm -f "${cfg}"
}

exempt_ucpauthz

# Build values overlay
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/kof-XXXX")"
trap 'rm -rf "${WORKDIR}"' EXIT

cp "${KOF_DIR}/global-values.yaml" "${WORKDIR}/global-values.yaml"
cp "${KOF_DIR}/profiles/${KOF_PROFILE}.yaml" "${WORKDIR}/profile.yaml"
cd "${WORKDIR}"

# Shrink storage sizes
SIZE="${KOF_STORAGE_SIZE}" yq -i '
    .victoriametrics.vmcluster.spec.vmstorage.storage.volumeClaimTemplate.spec.resources.requests.storage = strenv(SIZE)
  | .victoria-logs-cluster.vlstorage.persistentVolume.size = strenv(SIZE)
  | .victoria-traces-cluster.vtstorage.persistentVolume.size = strenv(SIZE)
' global-values.yaml

# Generate components file
yq -n 'load("global-values.yaml") as $gv
  | "operators mothership regional child storage collectors" / " "
  | map({"key": ("kof-" + .), "value": {"values": $gv}})
  | $gv * from_entries' > global-components.yaml

yq -i 'load("global-values.yaml") as $gv
  | .kof-regional.values.operators = $gv
  | .kof-regional.values.storage *= $gv
  | .kof-regional.values.collectors = $gv
  | .kof-child.values.operators = $gv
  | .kof-child.values.collectors = $gv
  | .victoria-metrics-operator as $vmo
  | .global as $g
  | .victoria-metrics-operator.values = $vmo
  | .victoria-metrics-operator.values.global = $g' global-components.yaml

# Runtime substitutions
SC_VAL="${SC}" KCM_NS="${KOF_KCM_NAMESPACE}" yq -n '
    .global.helmRepo.namespace = strenv(KCM_NS)
  | .["kof-mothership"].values.global.storageClass = strenv(SC_VAL)
  | .["kof-mothership"].values.kcm.namespace = strenv(KCM_NS)
  | .["kof-mothership"].values["cert-manager-service-template"].namespace = strenv(KCM_NS)
  | .["kof-mothership"].values["ingress-nginx-service-template"].namespace = strenv(KCM_NS)
  | .["kof-mothership"].values["envoy-gateway-service-template"].namespace = strenv(KCM_NS)
  | .["kof-storage"].values.global.storageClass = strenv(SC_VAL)
  | .["kof-collectors"].values.kcm.namespace = strenv(KCM_NS)
  | .["kof-collectors"].values.global.clusterNamespace = strenv(KCM_NS)
  | .["kof-collectors"].values["opentelemetry-kube-stack"].defaultCRConfig.config.processors["resource/k8sclustername"].attributes = [
        {"action": "insert", "key": "k8s.cluster.name", "value": "mothership"},
        {"action": "insert", "key": "k8s.cluster.namespace", "value": strenv(KCM_NS)}
    ]
  | .["kof-collectors"].values["opentelemetry-kube-stack"].defaultCRConfig.config.exporters.prometheusremotewrite.external_labels.cluster = "mothership"
  | .["kof-collectors"].values["opentelemetry-kube-stack"].defaultCRConfig.config.exporters.prometheusremotewrite.external_labels.clusterNamespace = strenv(KCM_NS)
' > runtime.yaml

# Custom Alert Rules & Sensitivity
yq -i '
    .["kof-mothership"].values.customRules.KubeNodeNotReady.for = "5m"
  | .["kof-mothership"].values.customRules.KubeNodeNotReady.severity = "critical"
  | .["kof-mothership"].values.customRules.KubeNodeUnreachable.for = "5m"
  | .["kof-mothership"].values.customRules.KubeNodeUnreachable.severity = "critical"
  | .["kof-mothership"].values.customRules.Watchdog.severity = "informational"
' runtime.yaml

# Enable Grafana Operator
yq -i '
    .["kof-operators"].values["grafana-operator"].enabled = true
  | .["kof-mothership"].values.grafana.enabled = true
' runtime.yaml

# Reuse MKE monitoring and deduplicate collectors
yq -i '
    .["kof-collectors"].values["opentelemetry-kube-stack"].nodeExporter.enabled = false
  | .["kof-collectors"].values["opentelemetry-kube-stack"].kubeProxy.enabled = false
  | .["kof-collectors"].values["opentelemetry-kube-stack"].coreDns.enabled = false
  | .["kof-collectors"].values["opentelemetry-kube-stack"].kubeApiServer.enabled = false
  | .["kof-collectors"].values["opentelemetry-kube-stack"]["kube-state-metrics"].extraArgs = [
        "--custom-resource-state-config-file=/etc/config/crd-metrics-config.yaml",
        "--custom-resource-state-only"
    ]
' runtime.yaml

echo "  Installing KOF umbrella chart via Helm..."
helm upgrade -i --reset-values \
    --create-namespace -n kof kof \
    "oci://${KOF_REGISTRY}/charts/kof" \
    --version "${KOF_VERSION}" \
    -f global-components.yaml \
    -f profile.yaml \
    -f runtime.yaml

cd "${REPO}"

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
    folders="Istio,Opencost,Victoria Traces"
    names="kps-nodes-aix,kps-nodes-darwin"
    to_delete="$(kubectl get grafanadashboard -n kof -o json 2>/dev/null \
        | FOLDERS="${folders}" NAMES="${names}" jq -r '
            ($ENV.FOLDERS | split(",") | map(select(length > 0))) as $folders
          | ($ENV.NAMES   | split(",") | map(select(length > 0))) as $names
          | .items[]?
          | (.spec.folder // "") as $f
          | .metadata.name as $n
          | select(($folders | index($f)) != null or ($names | index($n)) != null)
          | $n' || true)"

    if [[ -n "${to_delete}" ]]; then
        while IFS= read -r d; do
            [[ -n "${d}" ]] && kubectl delete grafanadashboard -n kof "${d}" --ignore-not-found >/dev/null 2>&1 || true
        done <<< "${to_delete}"
    fi
fi

# Configure Gateway HTTPRoutes & Dex OAuth
"$REPO/artifacts/scripts/mke4/setup_mke4_httproutes.sh"

echo ""
echo "=== KOF Monitoring Ready ==="
echo "  UI URL:    https://${KOF_APP_DOMAIN:-kof-mke}.${ROOT_DOMAIN:-samkhya.cloud}"
