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
              number: 3000
EOF
        echo "  [OK] Ingress created for ${K0RDENT_DOM} -> k0rdent/kcm-k0rdent-ui:3000"
    fi
fi

# 3. Register Redirect URIs in Dex OAuth Server
echo "  Synchronizing Dex OAuth redirectURIs for KOF and k0rdent-ui..."
if KUBECONFIG="$KCFG" kubectl get secret -n mke authentication-dex >/dev/null 2>&1; then
    python3 -c "
import yaml, base64, subprocess

kcfg = '${KCFG}'
raw = subprocess.check_output(['kubectl', '--kubeconfig', kcfg, 'get', 'secret', '-n', 'mke', 'authentication-dex', '-o', 'jsonpath={.data.config\\\\.yaml}'])
cfg_yaml = base64.b64decode(raw).decode('utf-8')
cfg = yaml.safe_load(cfg_yaml)

domains = [
    'https://${KOF_DOM}',
    'https://${KOF_DOM}/login/generic_oauth',
    'https://${KOF_DOM}/oauth/callback',
    'https://${K0RDENT_DOM}',
    'https://${K0RDENT_DOM}/oauth2/callback',
    'https://${K0RDENT_DOM}/callback'
]

needs_update = False
for client in cfg.get('staticClients', []):
    if client.get('id') == 'mke-dashboard':
        uris = client.setdefault('redirectURIs', [])
        for d in domains:
            if d not in uris:
                uris.append(d)
                needs_update = True

if needs_update:
    updated_yaml = yaml.dump(cfg)
    encoded = base64.b64encode(updated_yaml.encode('utf-8')).decode('utf-8')
    patch_json = f'{{\"data\":{{\"config.yaml\":\"{encoded}\"}}}}'
    subprocess.check_call(['kubectl', '--kubeconfig', kcfg, 'patch', 'secret', '-n', 'mke', 'authentication-dex', '--type=merge', '-p', patch_json])
    subprocess.check_call(['kubectl', '--kubeconfig', kcfg, 'rollout', 'restart', 'deployment/authentication-dex', '-n', 'mke'])
    print('  [OK] Dex OAuth redirectURIs updated and rollout triggered')
else:
    print('  [OK] Dex OAuth redirectURIs already up-to-date')
" 2>/dev/null || echo "  [WARN] Dex patch failed or not needed"
fi
