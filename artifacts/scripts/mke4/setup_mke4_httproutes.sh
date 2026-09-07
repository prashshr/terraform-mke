#!/usr/bin/env bash
# setup_mke4_httproutes.sh — Configure Gateway API HTTPRoutes for KOF, k0rdent-ui & MSR4
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_DIR}/artifacts/scripts/common/config_parser.sh"
load_config "${REPO_DIR}/config.env"

KCFG="${REPO_DIR}/artifacts/configs/kubeconfig.yaml"
[[ ! -f "$KCFG" && -f "$HOME/.mke/mke.kubeconf" ]] && KCFG="$HOME/.mke/mke.kubeconf"

if [[ ! -f "$KCFG" ]]; then
    echo "Kubeconfig not found. Skipping HTTPRoute setup."
    exit 0
fi

ROOT_DOM="${ROOT_DOMAIN:-samkhya.cloud}"
export KOF_DOM="${KOF_APP_DOMAIN:-kof-mke}.${ROOT_DOM}"
export K0RDENT_DOM="${K0RDENT_UI_APP_DOMAIN:-k0rdent-ui}.${ROOT_DOM}"
export MSR4_DOM="${MSR4_APP_DOMAIN:-msr4}.${ROOT_DOM}"
export MKE4_UI_DOM="${MKE4_UI_DOMAIN:-mke4-ui}.${ROOT_DOM}"

echo "=== Configuring MKE4 Gateway HTTPRoutes for KOF, k0rdent-ui & MSR4 ==="

# 1. Clean up any conflicting custom UI routes (let MKE manage its dashboard natively)
KUBECONFIG="$KCFG" kubectl delete httproute ui-mke-dashboard-httproute dex-http-server-httproute -n mke >/dev/null 2>&1 || true

# 2. Configure KOF (Grafana) HTTPRoutes if enabled
if [[ "${KOF_ENABLED:-true}" == "true" ]]; then
    if [ -f "${REPO_DIR}/artifacts/configs/kof/manifests/kof-routes.yaml" ]; then
        echo "  Applying Gateway HTTPRoute for KOF (${KOF_DOM})..."
        envsubst < "${REPO_DIR}/artifacts/configs/kof/manifests/kof-routes.yaml" | KUBECONFIG="$KCFG" kubectl apply -f -
    fi
fi

# 3. Configure k0rdent-ui HTTPRoutes if enabled
if [[ "${K0RDENT_UI_ENABLED:-true}" == "true" ]]; then
    if [ -f "${REPO_DIR}/artifacts/configs/k0rdent-ui/manifests/k0rdent-ui-routes.yaml" ]; then
        echo "  Applying Gateway HTTPRoute for k0rdent-ui (${K0RDENT_DOM})..."
        envsubst < "${REPO_DIR}/artifacts/configs/k0rdent-ui/manifests/k0rdent-ui-routes.yaml" | KUBECONFIG="$KCFG" kubectl apply -f -
    fi
fi

# 4. If MSR4 is deployed, configure MSR4 HTTPRoute
if KUBECONFIG="$KCFG" kubectl get ns msr4 >/dev/null 2>&1; then
    MSR4_SVC="msr4-harbor-nginx"
    if ! KUBECONFIG="$KCFG" kubectl get svc -n msr4 "$MSR4_SVC" >/dev/null 2>&1; then
        MSR4_SVC="harbor"
    fi
    if KUBECONFIG="$KCFG" kubectl get svc -n msr4 "$MSR4_SVC" >/dev/null 2>&1; then
        echo "  Applying Gateway HTTPRoute for MSR4 (${MSR4_DOM}) -> msr4/${MSR4_SVC}..."
        KUBECONFIG="$KCFG" kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-mke-gateway-msr4
  namespace: msr4
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: mke
  to:
  - group: ""
    kind: Service
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: msr4-httproute
  namespace: mke
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: mke-gateway-ingress-nodeport-https
  hostnames:
  - ${MSR4_DOM}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - group: ""
      kind: Service
      name: ${MSR4_SVC}
      namespace: msr4
      port: 80
      weight: 1
EOF
    fi
fi

# 5. Register Redirect URIs in Dex OAuth Server
echo "  Synchronizing Dex OAuth redirectURIs for KOF, k0rdent-ui & MSR4..."
if KUBECONFIG="$KCFG" kubectl get secret -n mke authentication-dex >/dev/null 2>&1; then
    python3 -c "
import yaml, base64, subprocess

kcfg = '${KCFG}'
raw = subprocess.check_output(['kubectl', '--kubeconfig', kcfg, 'get', 'secret', '-n', 'mke', 'authentication-dex', '-o', 'jsonpath={.data.config\\\\.yaml}'])
cfg_yaml = base64.b64decode(raw).decode('utf-8')
cfg = yaml.safe_load(cfg_yaml)

domains = [
    'https://${KOF_DOM}',
    'https://${KOF_DOM}/',
    'https://${KOF_DOM}:34001',
    'https://${KOF_DOM}:34001/',
    'https://${KOF_DOM}/login',
    'https://${KOF_DOM}/login/generic_oauth',
    'https://${KOF_DOM}/oauth/callback',
    'https://${K0RDENT_DOM}',
    'https://${K0RDENT_DOM}/',
    'https://${K0RDENT_DOM}:34001',
    'https://${K0RDENT_DOM}:34001/',
    'https://${K0RDENT_DOM}/login',
    'https://${K0RDENT_DOM}/login?from=%2Flogin',
    'https://${K0RDENT_DOM}/api/auth/callback/credentials',
    'https://${K0RDENT_DOM}/api/auth/callback/oidc',
    'https://${K0RDENT_DOM}/oauth2/callback',
    'https://${K0RDENT_DOM}/callback',
    'https://${MSR4_DOM}',
    'https://${MSR4_DOM}/',
    'https://${MSR4_DOM}:34001',
    'https://${MSR4_DOM}/c/login',
    'https://${MSR4_DOM}/oauth/callback'
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

echo "=== MKE4 Gateway HTTPRoutes configured ==="
