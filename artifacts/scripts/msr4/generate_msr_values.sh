#!/bin/bash
# Helper script to fetch MSR Helm chart values from Mirantis registry.
#
# Usage: ./generate_msr_values.sh [version]
#
# Examples:
#   ./generate_msr_values.sh              # fetches 4.13.5 (default)
#   ./generate_msr_values.sh 4.13.4       # fetches 4.13.4
#
# Requires: helm, access to registry.mirantis.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALUES_DIR="${PROJECT_ROOT}/artifacts/configs/msr4/values"
DEFAULT_VERSION="4.13.5"

VERSION="${1:-${DEFAULT_VERSION}}"

echo "=== Generating MSR values for version ${VERSION} ==="

# Check prerequisites
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm is required but not found"
  exit 1
fi

# Ensure values directory exists
mkdir -p "${VALUES_DIR}"

# Fetch upstream values
OUTPUT_FILE="${VALUES_DIR}/msr-values-${VERSION}-single.yaml"
if [ -f "${OUTPUT_FILE}" ]; then
  echo "File ${OUTPUT_FILE} already exists. Overwriting..."
fi

echo "Fetching MSR ${VERSION} values from upstream..."
if helm show values "oci://registry.mirantis.com/harbor/helm/msr" --version "${VERSION}" > "${OUTPUT_FILE}"; then
  echo "✓ Saved: ${OUTPUT_FILE}"
  echo ""
  echo "Next steps:"
  echo "  1. Review and edit ${OUTPUT_FILE} for your deployment"
  echo "  2. For HA mode: apply the overrides from msr-ha-overrides.yaml"
  echo "  3. Run ./artifacts/scripts/msr4/install_msr4.sh to deploy"
else
  echo "ERROR: Failed to fetch values. Ensure you are logged in to registry.mirantis.com:"
  echo "  helm registry login registry.mirantis.com --username <user> --password <pass>"
  exit 1
fi