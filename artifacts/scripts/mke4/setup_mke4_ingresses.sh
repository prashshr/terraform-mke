#!/usr/bin/env bash
# setup_mke4_ingresses.sh — Configure HTTP routes / ingresses for KOF and k0rdent-ui
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_DIR}/artifacts/scripts/common/config_parser.sh"
load_config "${REPO_DIR}/config.env"

KCFG="${REPO_DIR}/artifacts/configs/kubeconfig.yaml"
[[ ! -f "$KCFG" && -f "$HOME/.mke/mke.kubeconf" ]] && KCFG="$HOME/.mke/mke.kubeconf"

if [[ ! -f "$KCFG" ]]; then
    echo "Kubeconfig not found. Skipping ingress setup."
    exit 0
fi

ROOT_DOM="${ROOT_DOMAIN:-samkhya.cloud}"
KOF_DOM="${KOF_APP_DOMAIN:-kof-mke}.${ROOT_DOM}"
K0RDENT_DOM="${K0RDENT_UI_APP_DOMAIN:-k0rdent-ui}.${ROOT_DOM}"

echo "=== Configuring MKE4 Ingress Routes for KOF & k0rdent-ui ==="

# 1. KOF / Grafana Ingress
if [[ "${KOF_ENABLED:-true}" == "true" ]]; then
    echo "  Configuring route for KOF / Grafana (${KOF_DOM})..."
    # Check if monitoring-grafana exists in mke namespace
    if KUBECONFIG="$KCFG" kubectl get svc -n mke monitoring-grafana >/dev/null 2>&1; then
        KUBECONFIG="$KCFG" kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kof-grafana-ingress
  namespace: mke
spec:
  rules:
  - host: ${KOF_DOM}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: monitoring-grafana
            port:
              number: 80
EOF
        echo "  [OK] Ingress created for ${KOF_DOM} -> mke/monitoring-grafana:80"
    fi
fi

# 2. k0rdent-ui Ingress
if [[ "${K0RDENT_UI_ENABLED:-true}" == "true" ]]; then
    echo "  Configuring route for k0rdent-ui (${K0RDENT_DOM})..."
    # Check if kcm-k0rdent-ui exists in k0rdent namespace
    if KUBECONFIG="$KCFG" kubectl get svc -n k0rdent kcm-k0rdent-ui >/dev/null 2>&1; then
        KUBECONFIG="$KCFG" kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: k0rdent-ui-ingress
  namespace: k0rdent
spec:
  rules:
  - host: ${K0RDENT_DOM}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kcm-k0rdent-ui
            port:
              number: 8080
EOF
        echo "  [OK] Ingress created for ${K0RDENT_DOM} -> k0rdent/kcm-k0rdent-ui:8080"
    fi
fi
