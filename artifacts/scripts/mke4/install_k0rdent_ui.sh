#!/usr/bin/env bash
# install_k0rdent_ui.sh — Install k0rdent-ui for cluster management UI
# Only supported for MKE4 clusters.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../.. && pwd)"
source "$REPO/scripts/config_parser.sh"
load_config "$REPO/config"

# ── Args ──────────────────────────────────────────────────────────────────
KUBECONFIG="${KUBECONFIG:-$REPO/artifacts/configs/kubeconfig.yaml}"
YES="${YES:-}"

# ── Validate MKE4 only ───────────────────────────────────────────────────
if [[ "$CLUSTER_TYPE" != "mke4" ]]; then
    echo "ERROR: k0rdent-ui is only supported for MKE4 clusters."
    exit 1
fi

if [[ ! "$K0RDENT_UI_ENABLED" == "true" ]]; then
    echo "k0rdent-ui not enabled in config (K0RDENT_UI_ENABLED=false). Skipping."
    exit 0
fi

echo ""
echo "=== Installing k0rdent-ui ==="
echo ""

# ── Helm repo ─────────────────────────────────────────────────────────────
helm repo add k0rdent https://k0rdent.github.io/k0rdent 2>/dev/null || true
helm repo update

# ── Install ───────────────────────────────────────────────────────────────
helm upgrade --install k0rdent-ui k0rdent/k0rdent-ui \
    --namespace k0rdent-ui \
    --create-namespace \
    --wait --timeout 5m

echo ""
echo "=== k0rdent-ui installed ==="
echo "  Access UI: kubectl port-forward -n k0rdent-ui svc/k0rdent-ui 8445:443"
