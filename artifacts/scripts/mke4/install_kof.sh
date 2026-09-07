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
for tool in helm kubectl jq; do
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

# Wait for VMCluster CRD and patch with control-plane tolerations & lean resources
echo "  Applying VMCluster tolerations and sizing..."
kubectl wait --for=condition=Established crd/vmclusters.operator.victoriametrics.com --timeout=5m 2>/dev/null || true
kubectl patch vmcluster cluster -n kof --type=merge -p '{
  "spec": {
    "vmstorage": {
      "resources": {
        "requests": {"cpu": "100m", "memory": "256Mi"},
        "limits": {"cpu": "1000m", "memory": "2Gi"}
      },
      "tolerations": [
        {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
        {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}
      ]
    },
    "vmselect": {
      "resources": {
        "requests": {"cpu": "100m", "memory": "256Mi"},
        "limits": {"cpu": "1000m", "memory": "1Gi"}
      },
      "tolerations": [
        {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
        {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}
      ]
    },
    "vminsert": {
      "resources": {
        "requests": {"cpu": "100m", "memory": "256Mi"},
        "limits": {"cpu": "1000m", "memory": "1Gi"}
      },
      "tolerations": [
        {"key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule"},
        {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}
      ]
    }
  }
}' 2>/dev/null || true

# Wait for Grafana CRDs and apply Grafana instance
echo "  Applying Grafana instance CR..."
kubectl wait --for=condition=Established crd/grafanas.grafana.integreatly.org --timeout=5m 2>/dev/null || true
kubectl apply -f "${KOF_DIR}/grafana.yaml" -n kof

# Add MKE Prometheus Datasource
kubectl wait --for=condition=Established crd/grafanadatasources.grafana.integreatly.org --timeout=5m 2>/dev/null || true
kubectl apply -f "${KOF_DIR}/mke-prometheus-datasource.yaml" -n kof

# Apply node-label transform & dedup filters to OpenTelemetry Collector
echo "  Configuring telemetry transforms (node-label, pushgateway drop, kubelet dedup)..."
cr="kof-collectors-ta-daemon"
ds="kof-collectors-ta-daemon-collector"
stmt_node='set(datapoint.attributes["node"], "${env:OTEL_K8S_NODE_NAME}") where IsMatch(metric.name, "^(node_|machine_|container_|kubelet_)") and datapoint.attributes["node"] == nil'
stmt_nodename='set(datapoint.attributes["nodename"], "${env:OTEL_K8S_NODE_NAME}") where IsMatch(metric.name, "^(node_|machine_|container_|kubelet_)") and datapoint.attributes["nodename"] == nil'

cur_json="$(kubectl -n kof get opentelemetrycollector "${cr}" -o json 2>/dev/null | jq -c '.spec.config.service.pipelines.metrics.processors // []' || echo "[]")"
if [[ -n "${cur_json}" && "${cur_json}" != "[]" ]]; then
    new_json="$(jq -c '
        if index("transform/setnode") then .
        elif index("batch") then index("batch") as $b | .[0:$b] + ["transform/setnode"] + .[$b:]
        else . + ["transform/setnode"] end
      | if index("filter/drop_k0s_pushgateway") then .
        elif index("batch") then index("batch") as $b | .[0:$b] + ["filter/drop_k0s_pushgateway"] + .[$b:]
        else . + ["filter/drop_k0s_pushgateway"] end' <<<"${cur_json}")"

    patch_file="$(mktemp "${TMPDIR:-/tmp}/kof-otel-patch-XXXX.json")"
    jq -n --arg s1 "${stmt_node}" --arg s2 "${stmt_nodename}" --argjson procs "${new_json}" '
        {spec:{config:{
            processors:{
                "transform/setnode":{metric_statements:[{context:"datapoint",statements:[$s1,$s2]}]},
                "filter/drop_k0s_pushgateway":{
                    error_mode:"ignore",
                    metrics:{datapoint:[
                        "attributes[\"exported_job\"] == \"kube-scheduler\"",
                        "attributes[\"exported_job\"] == \"kube-controller-manager\"",
                        "attributes[\"exported_job\"] == \"etcd\""
                    ]}
                }
            },
            service:{pipelines:{metrics:{processors:$procs}}}
        }}}' > "${patch_file}"
    kubectl patch opentelemetrycollector "${cr}" -n kof --type=merge --patch-file "${patch_file}" >/dev/null 2>&1 || true
    rm -f "${patch_file}"
    kubectl -n kof rollout restart ds/${ds} >/dev/null 2>&1 || true
fi

# Kubelet dedup on daemon collectors
for dcr in kof-collectors-daemon kof-collectors-controller-k0s-daemon; do
    if kubectl get opentelemetrycollector "${dcr}" -n kof >/dev/null 2>&1; then
        pf="$(mktemp "${TMPDIR:-/tmp}/kof-nokubelet-XXXX.json")"
        kubectl -n kof get opentelemetrycollector "${dcr}" -o json \
            | jq '.spec.config.receivers.prometheus.config.scrape_configs
                  |= map(select(.job_name | startswith("kubelet") | not))
                | {spec:{config:{receivers:{prometheus:{config:{scrape_configs:
                    .spec.config.receivers.prometheus.config.scrape_configs}}}}}}' > "${pf}"
        kubectl patch opentelemetrycollector "${dcr}" -n kof --type=merge --patch-file "${pf}" >/dev/null 2>&1 || true
        rm -f "${pf}"
        kubectl -n kof rollout restart ds/${dcr}-collector 2>/dev/null || true
    fi
done

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
