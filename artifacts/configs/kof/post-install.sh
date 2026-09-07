#!/usr/bin/env bash
# post-install.sh — Configure telemetry transforms, deduplications, and dashboard pruning
# Exactly aligned with macpromethe/mke4k-lab architecture
set -euo pipefail

echo "=== 1. Applying Node-Label Transform & Pushgateway Dedup ==="
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

echo "=== 2. Applying Kubelet Deduplication ==="
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

echo "=== 3. Pruning Non-Applicable Dashboards (Lean Mode) ==="
kubectl get grafanadashboard -n kof -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.folder}{"\n"}{end}' 2>/dev/null \
  | grep -E "Istio|Opencost|Victoria Traces|kps-nodes-aix|kps-nodes-darwin" \
  | awk '{print $1}' \
  | xargs -r kubectl delete grafanadashboard -n kof >/dev/null 2>&1 || true

echo "=== 4. Waiting for grafana-admin-credentials secret ==="
for i in {1..30}; do
    if kubectl get secret -n kof grafana-admin-credentials >/dev/null 2>&1; then
        echo "  Secret grafana-admin-credentials is ready."
        break
    fi
    sleep 2
done

echo ""
echo "=== Telemetry transforms, deduplication, and dashboard cleanup applied successfully! ==="
