#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ENV_FILE="${ROOT_DIR}/artifacts/configs/mkectl-upgrade.env"
CONFIG_FILE="${ROOT_DIR}/artifacts/configs/mke3/mke3-config.toml"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE}; run make apply first" >&2
  exit 1
fi

. "${ENV_FILE}"

if [[ -z "${MKCTL_UPGRADE_ADMIN_USERNAME:-}" ]]; then
  echo "missing MKCTL_UPGRADE_ADMIN_USERNAME in ${ENV_FILE}" >&2
  exit 1
fi

if [[ -z "${MKCTL_UPGRADE_ADMIN_PASSWORD:-}" ]]; then
  echo "missing MKCTL_UPGRADE_ADMIN_PASSWORD in ${ENV_FILE}" >&2
  exit 1
fi

if [[ -z "${MKCTL_MKE3_EXTERNAL_ADDRESS:-}" ]]; then
  echo "missing MKCTL_MKE3_EXTERNAL_ADDRESS in ${ENV_FILE}" >&2
  exit 1
fi

echo "Fetching MKE3 auth token from ${MKCTL_MKE3_EXTERNAL_ADDRESS}"

AUTHTOKEN="$(
  curl --silent --show-error --insecure \
    --data "{\"username\":\"${MKCTL_UPGRADE_ADMIN_USERNAME}\",\"password\":\"${MKCTL_UPGRADE_ADMIN_PASSWORD}\"}" \
    "https://${MKCTL_MKE3_EXTERNAL_ADDRESS}/auth/login" \
  | jq -r '.auth_token'
)"

if [[ -z "${AUTHTOKEN}" || "${AUTHTOKEN}" == "null" ]]; then
  echo "failed to get auth token from ${MKCTL_MKE3_EXTERNAL_ADDRESS}" >&2
  exit 1
fi

echo "Downloading current MKE3 config to ${CONFIG_FILE}"

curl --silent --show-error --insecure \
  -H "accept: application/toml" \
  -H "Authorization: Bearer ${AUTHTOKEN}" \
  "https://${MKCTL_MKE3_EXTERNAL_ADDRESS}/api/ucp/config-toml" \
  > "${CONFIG_FILE}"

BEFORE_VALUE="$(grep -E '^[[:space:]]*calico_kdd[[:space:]]*=' "${CONFIG_FILE}" || true)"
echo "Before: ${BEFORE_VALUE}"

UPDATED=false

if grep -Eq '^[[:space:]]*calico_kdd[[:space:]]*=[[:space:]]*false' "${CONFIG_FILE}"; then
  sed -i -E \
    's/^([[:space:]]*calico_kdd[[:space:]]*=[[:space:]]*)false/\1true/' \
    "${CONFIG_FILE}"

  UPDATED=true
fi

AFTER_VALUE="$(grep -E '^[[:space:]]*calico_kdd[[:space:]]*=' "${CONFIG_FILE}" || true)"
echo "After:  ${AFTER_VALUE}"

if [[ "${UPDATED}" == "true" ]]; then
  echo "Uploading updated MKE3 config"

  curl --silent --show-error --insecure \
    -X PUT \
    -H "accept: application/toml" \
    -H "Authorization: Bearer ${AUTHTOKEN}" \
    --upload-file "${CONFIG_FILE}" \
    "https://${MKCTL_MKE3_EXTERNAL_ADDRESS}/api/ucp/config-toml" \
    > /dev/null

  echo "Done: set calico_kdd = true on ${MKCTL_MKE3_EXTERNAL_ADDRESS}"
else
  echo "No change required; calico_kdd already true"
fi
