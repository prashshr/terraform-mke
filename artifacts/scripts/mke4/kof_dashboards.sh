#!/usr/bin/env bash
# kof_dashboards.sh — Load production Kubernetes & Node dashboards and alert rules into Grafana & Alertmanager
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$REPO/artifacts/configs/kubeconfig.yaml}"
[[ ! -f "$KUBECONFIG" && -f "$HOME/.mke/mke.kubeconf" ]] && KUBECONFIG="$HOME/.mke/mke.kubeconf"
export KUBECONFIG

echo "=== Deploying Prebuilt Grafana Dashboards & Prometheus Alerts ==="

# 1. Cluster Overview Dashboard ConfigMap
kubectl apply -n kof -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-k8s-cluster
  namespace: kof
  labels:
    grafana_dashboard: "1"
data:
  k8s-cluster.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 0,
      "id": null,
      "links": [],
      "liveNow": false,
      "templating": {
        "list": [
          {
            "current": { "selected": true, "text": "Prometheus", "value": "prometheus" },
            "hide": 2,
            "includeAll": false,
            "name": "DS_PROMETHEUS",
            "options": [],
            "query": "prometheus",
            "refresh": 1,
            "type": "datasource"
          }
        ]
      },
      "panels": [
        {
          "collapsed": false,
          "gridPos": { "h": 1, "w": 24, "x": 0, "y": 0 },
          "id": 100,
          "title": "Cluster Health & Overview",
          "type": "row"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": {
              "color": { "mode": "thresholds" },
              "mappings": [],
              "thresholds": { "mode": "absolute", "steps": [{ "color": "green", "value": null }] }
            }
          },
          "gridPos": { "h": 4, "w": 6, "x": 0, "y": 1 },
          "id": 1,
          "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
          "pluginVersion": "10.0.0",
          "targets": [{ "expr": "sum(kube_node_status_condition{condition=\"Ready\",status=\"true\"})", "refId": "A" }],
          "title": "Ready Nodes",
          "type": "stat"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": {
              "color": { "mode": "thresholds" },
              "mappings": [],
              "thresholds": { "mode": "absolute", "steps": [{ "color": "blue", "value": null }] }
            }
          },
          "gridPos": { "h": 4, "w": 6, "x": 6, "y": 1 },
          "id": 2,
          "options": { "reduceOptions": { "calcs": ["lastNotNull"], "fields": "", "values": false } },
          "targets": [{ "expr": "count(kube_pod_info)", "refId": "A" }],
          "title": "Total Pods",
          "type": "stat"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": {
              "color": { "mode": "thresholds" },
              "unit": "percentunit",
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  { "color": "green", "value": null },
                  { "color": "yellow", "value": 0.75 },
                  { "color": "red", "value": 0.9 }
                ]
              }
            }
          },
          "gridPos": { "h": 4, "w": 6, "x": 12, "y": 1 },
          "id": 3,
          "options": { "reduceOptions": { "calcs": ["lastNotNull"] } },
          "targets": [{ "expr": "1 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))", "refId": "A" }],
          "title": "Cluster CPU Utilization",
          "type": "gauge"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": {
            "defaults": {
              "color": { "mode": "thresholds" },
              "unit": "percentunit",
              "thresholds": {
                "mode": "absolute",
                "steps": [
                  { "color": "green", "value": null },
                  { "color": "yellow", "value": 0.75 },
                  { "color": "red", "value": 0.9 }
                ]
              }
            }
          },
          "gridPos": { "h": 4, "w": 6, "x": 18, "y": 1 },
          "id": 4,
          "options": { "reduceOptions": { "calcs": ["lastNotNull"] } },
          "targets": [{ "expr": "1 - (sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))", "refId": "A" }],
          "title": "Cluster Memory Utilization",
          "type": "gauge"
        },
        {
          "collapsed": false,
          "gridPos": { "h": 1, "w": 24, "x": 0, "y": 5 },
          "id": 101,
          "title": "Node Resource Metrics",
          "type": "row"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "percentunit" } },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 6 },
          "id": 5,
          "targets": [{ "expr": "1 - (rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))", "legendFormat": "{{instance}}", "refId": "A" }],
          "title": "CPU Usage per Node",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "bytes" } },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 6 },
          "id": 6,
          "targets": [{ "expr": "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes", "legendFormat": "{{instance}}", "refId": "A" }],
          "title": "Memory Used per Node",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["kubernetes", "kof", "overview"],
      "time": { "from": "now-1h", "to": "now" },
      "timepicker": { "refresh_intervals": ["5s", "10s", "30s", "1m"] },
      "timezone": "browser",
      "title": "Kubernetes / Cluster Overview",
      "uid": "k8s-cluster-overview",
      "version": 1
    }
EOF

# 2. Node Exporter Full Dashboard ConfigMap
kubectl apply -n kof -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-node-exporter
  namespace: kof
  labels:
    grafana_dashboard: "1"
data:
  node-exporter.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 1,
      "id": null,
      "links": [],
      "liveNow": false,
      "templating": {
        "list": [
          {
            "current": { "selected": true, "text": "Prometheus", "value": "prometheus" },
            "hide": 2,
            "includeAll": false,
            "name": "DS_PROMETHEUS",
            "options": [],
            "query": "prometheus",
            "refresh": 1,
            "type": "datasource"
          }
        ]
      },
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "percent" } },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "targets": [{ "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)", "legendFormat": "{{instance}}", "refId": "A" }],
          "title": "CPU Busy %",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "percent" } },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [{ "expr": "((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) * 100", "legendFormat": "{{instance}}", "refId": "A" }],
          "title": "RAM Used %",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "Bps" } },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
          "id": 3,
          "targets": [
            { "expr": "rate(node_network_receive_bytes_total{device!~\"lo|veth.*|cali.*\"}[5m])", "legendFormat": "{{instance}} (rx)", "refId": "A" },
            { "expr": "rate(node_network_transmit_bytes_total{device!~\"lo|veth.*|cali.*\"}[5m])", "legendFormat": "{{instance}} (tx)", "refId": "B" }
          ],
          "title": "Network Traffic (I/O)",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "percent" } },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
          "id": 4,
          "targets": [{ "expr": "100 - ((node_filesystem_avail_bytes{mountpoint=\"/\"} * 100) / node_filesystem_size_bytes{mountpoint=\"/\"})", "legendFormat": "{{instance}} (/)", "refId": "A" }],
          "title": "Disk Space Used % (/)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["nodes", "hardware", "kof"],
      "time": { "from": "now-1h", "to": "now" },
      "timezone": "browser",
      "title": "Node Exporter / Full System",
      "uid": "node-exporter-full",
      "version": 1
    }
EOF

# 3. Pods & Workloads Dashboard ConfigMap
kubectl apply -n kof -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-k8s-workloads
  namespace: kof
  labels:
    grafana_dashboard: "1"
data:
  k8s-workloads.json: |
    {
      "annotations": { "list": [] },
      "editable": true,
      "fiscalYearStartMonth": 0,
      "graphTooltip": 1,
      "id": null,
      "links": [],
      "liveNow": false,
      "templating": {
        "list": [
          {
            "current": { "selected": true, "text": "Prometheus", "value": "prometheus" },
            "hide": 2,
            "includeAll": false,
            "name": "DS_PROMETHEUS",
            "options": [],
            "query": "prometheus",
            "refresh": 1,
            "type": "datasource"
          }
        ]
      },
      "panels": [
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "short" } },
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "id": 1,
          "targets": [{ "expr": "topk(10, sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])))", "legendFormat": "{{namespace}}/{{pod}}", "refId": "A" }],
          "title": "Top 10 Pods by CPU Usage (cores)",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "bytes" } },
          "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
          "id": 2,
          "targets": [{ "expr": "topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=\"\"}))", "legendFormat": "{{namespace}}/{{pod}}", "refId": "A" }],
          "title": "Top 10 Pods by Memory Working Set",
          "type": "timeseries"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": { "unit": "short" } },
          "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
          "id": 3,
          "targets": [{ "expr": "sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[1h])) > 0", "legendFormat": "{{namespace}}/{{pod}}", "refId": "A" }],
          "title": "Pod Container Restarts (Last 1h)",
          "type": "timeseries"
        }
      ],
      "refresh": "10s",
      "schemaVersion": 38,
      "style": "dark",
      "tags": ["workloads", "pods", "kof"],
      "time": { "from": "now-1h", "to": "now" },
      "timezone": "browser",
      "title": "Kubernetes / Pods & Workloads",
      "uid": "k8s-workloads",
      "version": 1
    }
EOF

# 4. Production PrometheusRules for Alertmanager (Cluster, Nodes, Workloads, Storage)
kubectl apply -n mke -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: mke4-cluster-alerts
  namespace: mke
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
  - name: mke4-core-alerts
    rules:
    - alert: KubeNodeNotReady
      expr: kube_node_status_condition{condition="Ready",status="true"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Node {{ $labels.node }} is NotReady"
        description: "Node {{ $labels.node }} has been unready for more than 2 minutes."

    - alert: NodeHighCpuUsage
      expr: (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.instance }}"
        description: "Node CPU utilization is exceeding 85% for 5 minutes."

    - alert: NodeHighMemoryUsage
      expr: ((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory utilization on {{ $labels.instance }}"
        description: "Node RAM utilization is exceeding 85%."

    - alert: NodeDiskSpaceLow
      expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.15
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Low disk space on {{ $labels.instance }}"
        description: "Root partition free space is below 15%."

    - alert: PodCrashLooping
      expr: rate(kube_pod_container_status_restarts_total[5m]) * 60 > 2
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is restarting frequently"
        description: "Container {{ $labels.container }} restarted more than 2 times in 5 minutes."

    - alert: DeploymentReplicasMismatch
      expr: kube_deployment_status_replicas_available{namespace!~"kube-system|calico-system"} != kube_deployment_spec_replicas{namespace!~"kube-system|calico-system"}
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has replica mismatch"
        description: "Available replicas do not match desired count for more than 10 minutes."
EOF

echo "=== Prebuilt Dashboards & Alerts Deployed ==="
