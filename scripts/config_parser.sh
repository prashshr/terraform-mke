#!/usr/bin/env bash
# config_parser.sh — Load config file with env var overrides
# Usage: source this file, then call load_config
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_config() {
    local config_file="${1:-${SCRIPT_DIR}/../../config}"

    if [[ -f "$config_file" ]]; then
        # shellcheck disable=SC1090
        source "$config_file"
    fi

    # ── Defaults ────────────────────────────────────────────────────────────
    CLUSTER_NAME="${CLUSTER_NAME:-ps-mke}"
    CLUSTER_TYPE="${CLUSTER_TYPE:-mke4}"
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-mkepassword}"

    MKE3_VERSION="${MKE3_VERSION:-3.8.7}"
    MKE4_VERSION="${MKE4_VERSION:-4.2.0}"
    MSR_VERSION="${MSR_VERSION:-}"
    MCR_VERSION="${MCR_VERSION:-29.6.1}"

    MKE4_UI_BACKEND_PORT="${MKE4_UI_BACKEND_PORT:-34001}"
    MKE4_GATEWAY_HTTP_NODE_PORT="${MKE4_GATEWAY_HTTP_NODE_PORT:-34000}"
    MKE4_GATEWAY_HTTPS_NODE_PORT="${MKE4_GATEWAY_HTTPS_NODE_PORT:-34001}"

    AWS_ENABLED="${AWS_ENABLED:-true}"
    AWS_REGION="${AWS_REGION:-eu-west-1}"
    AWS_PROFILE="${AWS_PROFILE:-}"
    AWS_CREDENTIALS_FILE="${AWS_CREDENTIALS_FILE:-credentials/aws-profile}"
    AWS_ROOT_VOLUME_SIZE="${AWS_ROOT_VOLUME_SIZE:-120}"

    HETZNER_ENABLED="${HETZNER_ENABLED:-false}"
    HETZNER_LOCATION="${HETZNER_LOCATION:-fsn1}"
    HETZNER_CREDENTIALS_FILE="${HETZNER_CREDENTIALS_FILE:-credentials/hetzner.token}"
    HETZNER_CREATE_NETWORK="${HETZNER_CREATE_NETWORK:-true}"
    HETZNER_NETWORK_CIDR="${HETZNER_NETWORK_CIDR:-10.42.0.0/16}"
    HETZNER_SUBNET_CIDR="${HETZNER_SUBNET_CIDR:-10.42.0.0/24}"
    HETZNER_NETWORK_ZONE="${HETZNER_NETWORK_ZONE:-eu-central}"

    ROOT_DOMAIN="${ROOT_DOMAIN:-samkhya.cloud}"
    APP_DOMAIN_MKE3="${APP_DOMAIN_MKE3:-mke3test}"
    APP_DOMAIN_MKE4="${APP_DOMAIN_MKE4:-mke4test}"
    APP_DOMAIN_INGRESS="${APP_DOMAIN_INGRESS:-ingtest}"
    APP_DOMAIN_MSR="${APP_DOMAIN_MSR:-msrtest}"
    APP_DOMAIN_MSR4="${APP_DOMAIN_MSR4:-msr4}"

    TLS_EMAIL="${TLS_EMAIL:-ops@samkhya.cloud}"
    TLS_ACME_ENABLED="${TLS_ACME_ENABLED:-true}"
    MKE3_TLS_ENABLED="${MKE3_TLS_ENABLED:-true}"
    MKE4_TLS_ENABLED="${MKE4_TLS_ENABLED:-true}"
    INGRESS_TLS_ENABLED="${INGRESS_TLS_ENABLED:-true}"
    MSR_TLS_ENABLED="${MSR_TLS_ENABLED:-true}"
    MSR4_TLS_ENABLED="${MSR4_TLS_ENABLED:-true}"

    CLOUDFLARE_ENABLED="${CLOUDFLARE_ENABLED:-true}"
    CLOUDFLARE_ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-samkhya.cloud}"
    CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"

    NFS_ENABLED="${NFS_ENABLED:-false}"
    AIRGAP_ENABLED="${AIRGAP_ENABLED:-false}"
    KOF_ENABLED="${KOF_ENABLED:-false}"
    KOF_PROFILE="${KOF_PROFILE:-lean}"
    K0RDENT_UI_ENABLED="${K0RDENT_UI_ENABLED:-false}"
    MONITORING_ENABLED="${MONITORING_ENABLED:-false}"
    EXPIRY_DAYS="${EXPIRY_DAYS:-0}"

    MSR4_HA="${MSR4_HA:-false}"
    MSR4_VERSION="${MSR4_VERSION:-4.13.5}"
    MSR4_HTTP_NODE_PORT="${MSR4_HTTP_NODE_PORT:-34002}"
    MSR4_HTTPS_NODE_PORT="${MSR4_HTTPS_NODE_PORT:-34003}"
    MSR4_METRICS_NODE_PORT="${MSR4_METRICS_NODE_PORT:-34004}"

    ENABLE_MSR="${ENABLE_MSR:-true}"
    ARTIFACTS_DIR="${ARTIFACTS_DIR:-}"
    SAN_OVERRIDE="${SAN_OVERRIDE:-}"
}

# Show current config values
show_config() {
    local config_file="${1:-${SCRIPT_DIR}/../../config}"
    echo "=== Current Configuration ==="
    echo "  Config file: $config_file"
    echo ""
    if [[ -f "$config_file" ]]; then
        grep -v '^\s*#' "$config_file" | grep -v '^\s*$' | sort
    else
        echo "  No config file found. Using defaults."
    fi
}
