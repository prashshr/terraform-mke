#!/usr/bin/env bash
# install_kof.sh — Install KOF (Grafana / Prometheus monitoring) for MKE4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "$REPO/artifacts/scripts/common/config_parser.sh"
load_config "$REPO/config.env"

KOF_PROFILE="${KOF_PROFILE:-lean}"
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
echo "=== Installing KOF (Grafana Monitoring) ==="
echo "  Profile: $KOF_PROFILE"
echo "  Datasource: Prometheus (http://monitoring-kube-prometheus-prometheus.mke:9090)"
echo ""

# Helm repo for Grafana
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update grafana >/dev/null 2>&1 || true

# Deploy Grafana with Prometheus datasource and dashboard sidecar
helm upgrade --install kof grafana/grafana \
    --namespace kof \
    --create-namespace \
    --set adminUser="${ADMIN_USERNAME:-admin}" \
    --set adminPassword="${ADMIN_PASSWORD:-mkepassword}" \
    --set "datasources.datasources\\.yaml.apiVersion=1" \
    --set "datasources.datasources\\.yaml.datasources[0].name=Prometheus" \
    --set "datasources.datasources\\.yaml.datasources[0].type=prometheus" \
    --set "datasources.datasources\\.yaml.datasources[0].url=http://monitoring-kube-prometheus-prometheus.mke.svc.cluster.local:9090" \
    --set "datasources.datasources\\.yaml.datasources[0].access=proxy" \
    --set "datasources.datasources\\.yaml.datasources[0].isDefault=true" \
    --set "sidecar.dashboards.enabled=true" \
    --set "sidecar.dashboards.searchNamespace=ALL" \
    --set "sidecar.datasources.enabled=true" \
    --set "dashboardProviders.dashboardproviders\\.yaml.apiVersion=1" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].name=default" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].orgId=1" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].folder=" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].type=file" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].disableDeletion=false" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].editable=true" \
    --set "dashboardProviders.dashboardproviders\\.yaml.providers[0].options.path=/var/lib/grafana/dashboards/default" \
    --wait --timeout=5m

# Configure Gateway routing
"$REPO/artifacts/scripts/mke4/setup_mke4_ingresses.sh"

echo ""
echo "=== KOF Monitoring Ready ==="
echo "  UI URL:    https://${KOF_APP_DOMAIN:-kof-mke}.${ROOT_DOMAIN:-samkhya.cloud}"
echo "  Username:  ${ADMIN_USERNAME:-admin}"
echo "  Password:  ${ADMIN_PASSWORD:-mkepassword}"
