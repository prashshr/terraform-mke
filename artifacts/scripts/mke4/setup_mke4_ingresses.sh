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
MKE4_UI_DOM="${MKE4_UI_DOMAIN:-mke4-ui}.${ROOT_DOM}"

echo "=== Configuring MKE4 Ingress & Gateway Routes for KOF & k0rdent-ui ==="

# 1. Deploy / verify KOF (Grafana) in kof namespace
if [[ "${KOF_ENABLED:-true}" == "true" ]]; then
    echo "  Deploying/verifying KOF (Grafana) monitoring in namespace 'kof'..."
    if ! KUBECONFIG="$KCFG" helm status kof -n kof >/dev/null 2>&1; then
        KUBECONFIG="$KCFG" helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
        KUBECONFIG="$KCFG" helm repo update >/dev/null 2>&1 || true
        KUBECONFIG="$KCFG" helm upgrade --install kof grafana/grafana \
            --namespace kof \
            --create-namespace \
            --set adminPassword="mkepassword" \
            --set "datasources.datasources\\.yaml.apiVersion=1" \
            --set "datasources.datasources\\.yaml.datasources[0].name=Prometheus" \
            --set "datasources.datasources\\.yaml.datasources[0].type=prometheus" \
            --set "datasources.datasources\\.yaml.datasources[0].url=http://monitoring-kube-prometheus-prometheus.mke.svc.cluster.local:9090" \
            --set "datasources.datasources\\.yaml.datasources[0].access=proxy" \
            --set "datasources.datasources\\.yaml.datasources[0].isDefault=true" \
            --wait --timeout=5m || echo "  [WARN] Grafana Helm install had non-fatal warning"
    fi
fi

# 2. Configure ReferenceGrants for cross-namespace routing
KUBECONFIG="$KCFG" kubectl apply -f - <<EOF >/dev/null 2>&1 || true
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-mke-gateway-kof
  namespace: kof
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: mke
  to:
  - group: ""
    kind: Service
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-mke-gateway-k0rdent
  namespace: k0rdent
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: mke
  to:
  - group: ""
    kind: Service
EOF

# 3. Configure HTTPRoutes on Gateway mke-gateway-ingress-nodeport-https
echo "  Applying Gateway HTTPRoutes for KOF (${KOF_DOM}), k0rdent-ui (${K0RDENT_DOM}), and MKE Dashboard (${MKE4_UI_DOM})..."
KUBECONFIG="$KCFG" kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kof-grafana-httproute
  namespace: mke
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: mke-gateway-ingress-nodeport-https
  hostnames:
  - ${KOF_DOM}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - group: ""
      kind: Service
      name: kof-grafana
      namespace: kof
      port: 80
      weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: k0rdent-ui-httproute
  namespace: mke
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: mke-gateway-ingress-nodeport-https
  hostnames:
  - ${K0RDENT_DOM}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - group: ""
      kind: Service
      name: kcm-k0rdent-ui
      namespace: k0rdent
      port: 3000
      weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ui-mke-dashboard-httproute
  namespace: mke
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: mke-gateway-ingress-nodeport-https
  hostnames:
  - ${MKE4_UI_DOM}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - group: ""
      kind: Service
      name: ui-mke-dashboard-chart
      port: 5001
      weight: 1
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: dex-http-server-httproute
  namespace: mke
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: mke-gateway-ingress-nodeport-https
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /dex
    backendRefs:
    - group: ""
      kind: Service
      name: dex-http-server
      port: 80
      weight: 1
EOF

# 4. Register Redirect URIs in Dex OAuth Server
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

echo "=== MKE4 Gateway Ingress Routes configured ==="
