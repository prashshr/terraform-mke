#!/usr/bin/env bash
# tunnel.sh — SSH tunnel management for airgap clusters
# Usage: tunnel.sh {open|close|status} [--service NAME]
#
# Binds ports on localhost and forwards through bastion to cluster services.
# Uses the SSH key from artifacts/ssh/.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/scripts/config_parser.sh"
load_config "$REPO/config"

# ── Tunnel definitions ──────────────────────────────────────────────────────
# Format: SERVICE_NAME:LOCAL_PORT:REMOTE_IP:REMOTE_PORT
declare -A TUNNELS=(
  [dashboard]="34000:${MANAGER_IP}:34000"
  [mke3]="34000:${MANAGER_IP}:34000"
  [grafana]="8443:${MANAGER_IP}:8443"
  [msr4]="8444:${MANAGER_IP}:8444"
  [k0rdent-ui]="8445:${MANAGER_IP}:8445"
  [kubectl]="6443:${MANAGER_IP}:6443"
  [harbor]="443:${BASTION_IP}:443"
  [dns]="53:${BASTION_IP}:53"
)

# ── Resolve IPs ────────────────────────────────────────────────────────────
MANAGER_IP="${MANAGER_IP:-}"
BASTION_IP="${BASTION_IP:-}"
SSH_KEY="${REPO}/artifacts/ssh/${CLUSTER_NAME}.pem"
SSH_USER="ec2-user"

resolve_ips() {
  if [[ -z "$MANAGER_IP" || -z "$BASTION_IP" ]]; then
    echo "Resolving IPs from Terraform state..."
    MANAGER_IP=$(terraform -chdir="$REPO" output -json all_hosts 2>/dev/null | jq -r '.[0].public_ip')
    BASTION_IP=$(terraform -chdir="$REPO" output -raw airgap_bastion_public_ip 2>/dev/null || echo "")
    if [[ -z "$BASTION_IP" ]]; then
      echo "No bastion found (airgap disabled?). Using manager as bastion."
      BASTION_IP="$MANAGER_IP"
    fi
  fi
  echo "  Manager: $MANAGER_IP"
  echo "  Bastion: $BASTION_IP"
}

# ── Open tunnels ───────────────────────────────────────────────────────────
open_tunnels() {
  local service="${1:-}"
  resolve_ips

  echo ""
  echo "Opening SSH tunnels..."

  for svc in "${!TUNNELS[@]}"; do
    # Skip if specific service requested and doesn't match
    [[ -n "$service" && "$svc" != "$service" ]] && continue

    IFS=':' read -r _ local_port remote_ip remote_port <<< "${TUNNELS[$svc]}"
    [[ -z "$remote_ip" ]] && continue

    echo "  $svc: localhost:$local_port -> $remote_ip:$remote_port"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        -f -N -L "${local_port}:${remote_ip}:${remote_port}" \
        -i "$SSH_KEY" "${SSH_USER}@${BASTION_IP}" \
        2>/dev/null || echo "    WARN: tunnel for $svc failed"
  done

  echo ""
  echo "Tunnels open. Access URLs:"
  echo "  Dashboard:  http://localhost:34000"
  echo "  Grafana:    https://localhost:8443"
  echo "  MSR4:       https://localhost:8444"
  echo "  k0rdent-ui: https://localhost:8445"
  echo "  kubectl:    https://localhost:6443"
  echo "  Harbor:     https://localhost:443"
  echo ""
  echo "Stop with: tunnel.sh close"
}

# ── Close tunnels ──────────────────────────────────────────────────────────
close_tunnels() {
  echo "Closing SSH tunnels..."
  pkill -f "ssh -f -N -L" 2>/dev/null || true
  echo "All tunnels closed."
}

# ── Status ─────────────────────────────────────────────────────────────────
tunnel_status() {
  echo "SSH tunnel status:"
  pgrep -fa "ssh -f -N -L" 2>/dev/null || echo "  No active tunnels."
}

# ── Main ───────────────────────────────────────────────────────────────────
case "${1:-status}" in
  open)
    open_tunnels "${2:-}"
    ;;
  close)
    close_tunnels
    ;;
  status)
    tunnel_status
    ;;
  *)
    echo "Usage: tunnel.sh {open|close|status} [--service NAME]"
    exit 1
    ;;
esac
