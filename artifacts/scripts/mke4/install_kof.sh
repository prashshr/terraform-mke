#!/usr/bin/env bash
# install_kof.sh — Install KOF (KubeOnFlux) Helm chart for MKE4 monitoring
# Only supported for MKE4 clusters.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.. && pwd)"
source "$REPO/scripts/config_parser.sh"
load_config "$REPO/config"

# ── Args ──────────────────────────────────────────────────────────────────
KOF_PROFILE="${KOF_PROFILE:-lean}"
KUBECONFIG="${KUBECONFIG:-$REPO/artifacts/configs/kubeconfig.yaml}"
YES="${YES:-}"

# ── Validate MKE4 only ───────────────────────────────────────────────────
if [[ "$CLUSTER_TYPE" != "mke4" ]]; then
    echo "ERROR: KOF is only supported for MKE4 clusters."
    exit 1
fi

if [[ ! "$KOF_ENABLED" == "true" ]]; then
    echo "KOF not enabled in config (KOF_ENABLED=false). Skipping."
    exit 0
fi

echo ""
echo "=== Installing KOF (KubeOnFlux) ==="
echo "  Profile: $KOF_PROFILE"
echo ""

# ── Helm repo ─────────────────────────────────────────────────────────────
helm repo add kof https://mke4-lab.github.io/kof 2>/dev/null || true
helm repo update

# ── Install ───────────────────────────────────────────────────────────────
case "$KOF_PROFILE" in
    lean)
        helm upgrade --install kof kof/kof \
            --namespace kof \
            --create-namespace \
            --set prometheus.enabled=false \
            --set grafana.enabled=true \
            --set loki.enabled=false \
            --wait --timeout 5m
        ;;
    full)
        helm upgrade --install kof kof/kof \
            --namespace kof \
            --create-namespace \
            --set prometheus.enabled=true \
            --set grafana.enabled=true \
            --set loki.enabled=true \
            --wait --timeout 10m
        ;;
    *)
        echo "ERROR: Unknown KOF profile: $KOF_PROFILE (use: lean, full)"
        exit 1
        ;;
esac

echo ""
echo "=== KOF installed ==="
echo "  Access Grafana: kubectl port-forward -n kof svc/kof-grafana 3000:80"
