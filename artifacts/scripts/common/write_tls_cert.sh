#!/usr/bin/env bash
set -euo pipefail

install -d -m 0700 "$TLS_DIR"

if [[ -n "${TLS_CA_PEM:-}" ]]; then
  printf '%s' "$TLS_CA_PEM" > "$TLS_CA_FILE"
  chmod 0600 "$TLS_CA_FILE"
fi

if [[ -n "${TLS_CERT_PEM:-}" ]]; then
  # Write cert exactly as provided — do NOT bundle CA into server.pem.
  # Mutating cert content here makes disk != plan-time local.wildcard_tls_cert_pem
  # (which reads the file via file()), causing perpetual plan drift on
  # null_resource.wildcard_tls_files and local_sensitive_file.launchpad.
  # Consumers that need a full chain build fullchain.pem separately
  # (e.g. install_msr4.sh: cat server.pem ca.pem > fullchain.pem).
  printf '%s' "$TLS_CERT_PEM" > "$TLS_CERT_FILE"
  chmod 0600 "$TLS_CERT_FILE"
fi

if [[ -n "${TLS_KEY_PEM:-}" ]]; then
  printf '%s' "$TLS_KEY_PEM" > "$TLS_KEY_FILE"
  chmod 0600 "$TLS_KEY_FILE"
fi
