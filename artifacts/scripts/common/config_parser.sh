#!/usr/bin/env bash
# config_parser.sh — Load config file with env var overrides
# Usage: source this file, then call load_config
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_config() {
    local default_file="${SCRIPT_DIR}/../../../config.env"
    [[ ! -f "$default_file" && -f "${SCRIPT_DIR}/../../../config" ]] && default_file="${SCRIPT_DIR}/../../../config"
    local config_file="${1:-$default_file}"

    # ── Save environment overrides (env vars must take precedence over config file) ──
    local _saved=()
    local _known_vars=(CLUSTER_NAME CLUSTER_TYPE ADMIN_USERNAME ADMIN_PASSWORD \
        MKE3_VERSION MKE4_VERSION MSR4_VERSION MSR2_VERSION MCR_VERSION \
        ENABLE_MSR MSR_VERSION MSR4_ENABLED MSR2_ENABLED \
        FORCE_DESTROY MKECTL_TIMEOUT_MINS EXPIRY_DAYS \
        MKE4_UI_DOMAIN APP_DOMAIN_MKE4_UI MKE4_APP_DOMAIN MKE3_APP_DOMAIN \
        ROOT_DOMAIN TLS_EMAIL CLOUDFLARE_API_TOKEN)
    for _v in "${_known_vars[@]}"; do
        if [[ -n "${!_v:-}" ]]; then
            _saved+=("$_v=${!_v}")
        fi
    done

    if [[ -f "$config_file" ]]; then
        # shellcheck disable=SC1090
        source "$config_file"
    fi

    # ── Restore environment overrides (env vars beat config file) ────────────
    for _sv in "${_saved[@]}"; do
        export "${_sv%%=*}=${_sv#*=}"
    done

    # ── Cluster ─────────────────────────────────────────────────────────────
    CLUSTER_NAME="${CLUSTER_NAME:-ps-mke}"
    CLUSTER_TYPE="${CLUSTER_TYPE:-mke4}"
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-mkepassword}"

    # ── MKE4 ────────────────────────────────────────────────────────────────
    MKE4_VERSION="${MKE4_VERSION:-4.2.0}"
    MKE4_APP_DOMAIN="${MKE4_APP_DOMAIN:-${APP_DOMAIN_MKE4:-mke4test}}"
    APP_DOMAIN_MKE4="${MKE4_APP_DOMAIN}"
    MKE4_UI_DOMAIN="${MKE4_UI_DOMAIN:-${APP_DOMAIN_MKE4_UI:-mke4-ui}}"
    APP_DOMAIN_MKE4_UI="${MKE4_UI_DOMAIN}"
    MKE4_UI_BACKEND_PORT="${MKE4_UI_BACKEND_PORT:-34001}"
    MKE4_GATEWAY_HTTP_NODE_PORT="${MKE4_GATEWAY_HTTP_NODE_PORT:-34000}"
    MKE4_GATEWAY_HTTPS_NODE_PORT="${MKE4_GATEWAY_HTTPS_NODE_PORT:-34001}"
    MKE4_TLS_ENABLED="${MKE4_TLS_ENABLED:-true}"

    # ── MKE3 ────────────────────────────────────────────────────────────────
    MKE3_VERSION="${MKE3_VERSION:-3.8.11}"
    MKE3_MCR_VERSION="${MKE3_MCR_VERSION:-${MCR_VERSION:-25.0.13}}"
    MCR_VERSION="${MKE3_MCR_VERSION}"
    MKE3_APP_DOMAIN="${MKE3_APP_DOMAIN:-${APP_DOMAIN_MKE3:-mke3test}}"
    APP_DOMAIN_MKE3="${MKE3_APP_DOMAIN}"
    MKE3_TLS_ENABLED="${MKE3_TLS_ENABLED:-true}"

    # ── MSR4 ────────────────────────────────────────────────────────────────
    MSR4_ENABLED="${MSR4_ENABLED:-false}"
    MSR4_VERSION="${MSR4_VERSION:-4.13.5}"
    MSR4_HA="${MSR4_HA:-false}"
    MSR4_APP_DOMAIN="${MSR4_APP_DOMAIN:-${APP_DOMAIN_MSR4:-msr4}}"
    APP_DOMAIN_MSR4="${MSR4_APP_DOMAIN}"
    MSR4_TLS_ENABLED="${MSR4_TLS_ENABLED:-true}"
    MSR4_HTTP_NODE_PORT="${MSR4_HTTP_NODE_PORT:-34002}"
    MSR4_HTTPS_NODE_PORT="${MSR4_HTTPS_NODE_PORT:-34003}"
    MSR4_METRICS_NODE_PORT="${MSR4_METRICS_NODE_PORT:-34004}"

    # ── MSR2 ────────────────────────────────────────────────────────────────
    MSR2_ENABLED="${MSR2_ENABLED:-${ENABLE_MSR:-false}}"
    ENABLE_MSR="${MSR2_ENABLED}"
    MSR2_HA="${MSR2_HA:-false}"
    MSR2_VERSION="${MSR2_VERSION:-${MSR_VERSION:-2.9.11}}"
    MSR_VERSION="${MSR2_VERSION}"
    MSR2_APP_DOMAIN="${MSR2_APP_DOMAIN:-${APP_DOMAIN_MSR2:-${APP_DOMAIN_MSR:-msrtest}}}"
    APP_DOMAIN_MSR2="${MSR2_APP_DOMAIN}"
    APP_DOMAIN_MSR="${MSR2_APP_DOMAIN}"
    MSR2_TLS_ENABLED="${MSR2_TLS_ENABLED:-${MSR_TLS_ENABLED:-true}}"
    MSR_TLS_ENABLED="${MSR2_TLS_ENABLED}"

    # ── Common Domains & TLS ────────────────────────────────────────────────
    ROOT_DOMAIN="${ROOT_DOMAIN:-samkhya.cloud}"
    APP_DOMAIN_INGRESS="${APP_DOMAIN_INGRESS:-ingtest}"
    TLS_EMAIL="${TLS_EMAIL:-ops@samkhya.cloud}"
    TLS_ACME_ENABLED="${TLS_ACME_ENABLED:-true}"
    INGRESS_TLS_ENABLED="${INGRESS_TLS_ENABLED:-true}"

    # ── Cloudflare ──────────────────────────────────────────────────────────
    CLOUDFLARE_ENABLED="${CLOUDFLARE_ENABLED:-true}"
    CLOUDFLARE_ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-samkhya.cloud}"
    CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

    # ── Infrastructure: AWS ─────────────────────────────────────────────────
    AWS_ENABLED="${AWS_ENABLED:-true}"
    AWS_REGION="${AWS_REGION:-eu-west-1}"
    AWS_PROFILE="${AWS_PROFILE:-}"
    AWS_CREDENTIALS_FILE="${AWS_CREDENTIALS_FILE:-credentials/aws-profile}"
    AWS_ROOT_VOLUME_SIZE="${AWS_ROOT_VOLUME_SIZE:-120}"

    # ── Infrastructure: Hetzner ─────────────────────────────────────────────
    HETZNER_ENABLED="${HETZNER_ENABLED:-false}"
    HETZNER_LOCATION="${HETZNER_LOCATION:-fsn1}"
    HETZNER_CREDENTIALS_FILE="${HETZNER_CREDENTIALS_FILE:-credentials/hetzner.token}"
    HETZNER_CREATE_NETWORK="${HETZNER_CREATE_NETWORK:-true}"
    HETZNER_NETWORK_CIDR="${HETZNER_NETWORK_CIDR:-10.42.0.0/16}"
    HETZNER_SUBNET_CIDR="${HETZNER_SUBNET_CIDR:-10.42.0.0/24}"
    HETZNER_NETWORK_ZONE="${HETZNER_NETWORK_ZONE:-eu-central}"

    # ── Features ────────────────────────────────────────────────────────────
    NFS_ENABLED="${NFS_ENABLED:-true}"
    AIRGAP_ENABLED="${AIRGAP_ENABLED:-false}"
    KOF_ENABLED="${KOF_ENABLED:-true}"
    KOF_PROFILE="${KOF_PROFILE:-lean}"
    KOF_APP_DOMAIN="${KOF_APP_DOMAIN:-${APP_DOMAIN_KOF:-kof-mke}}"
    APP_DOMAIN_KOF="${KOF_APP_DOMAIN}"
    K0RDENT_UI_ENABLED="${K0RDENT_UI_ENABLED:-true}"
    K0RDENT_UI_APP_DOMAIN="${K0RDENT_UI_APP_DOMAIN:-${APP_DOMAIN_K0RDENT_UI:-k0rdent-ui}}"
    APP_DOMAIN_K0RDENT_UI="${K0RDENT_UI_APP_DOMAIN}"
    MONITORING_ENABLED="${MONITORING_ENABLED:-false}"
    EXPIRY_DAYS="${EXPIRY_DAYS:-0}"

    # ── Behaviour ───────────────────────────────────────────────────────────
    FORCE_DESTROY="${FORCE_DESTROY:-true}"
    MKECTL_TIMEOUT_MINS="${MKECTL_TIMEOUT_MINS:-60}"
    ARTIFACTS_DIR="${ARTIFACTS_DIR:-}"
    SAN_OVERRIDE="${SAN_OVERRIDE:-}"
}

# Show current config values
show_config() {
    local default_file="${SCRIPT_DIR}/../../../config.env"
    [[ ! -f "$default_file" && -f "${SCRIPT_DIR}/../../../config" ]] && default_file="${SCRIPT_DIR}/../../../config"
    local config_file="${1:-$default_file}"
    echo "=== Current Configuration ==="
    echo "  Config file: $config_file"
    echo ""
    if [[ -f "$config_file" ]]; then
        grep -v '^\s*#' "$config_file" | grep -v '^\s*$' | sort
    else
        echo "  No config file found. Using defaults."
    fi
}

# ── Timing helpers ───────────────────────────────────────────────────────────
declare -A _PHASE_START_TIMES

phase_start() {
  local name="$1"
  _PHASE_START_TIMES[$name]=$(date +%s)
  echo "=== $name started at $(date '+%H:%M:%S') ==="
}

phase_end() {
  local name="$1"
  local start=${_PHASE_START_TIMES[$name]:-0}
  local end=$(date +%s)
  local elapsed=$((end - start))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))
  echo "=== $name completed in ${mins}m ${secs}s ==="
}
