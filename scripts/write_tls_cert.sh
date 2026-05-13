#!/usr/bin/env bash
set -euo pipefail

install -d -m 0700 "$TLS_DIR"

if [[ -n "${TLS_CA_PEM:-}" ]]; then
  printf '%s' "$TLS_CA_PEM" > "$TLS_CA_FILE"
  chmod 0600 "$TLS_CA_FILE"
fi

if [[ -n "${TLS_CERT_PEM:-}" ]]; then
  printf '%s' "$TLS_CERT_PEM" > "$TLS_CERT_FILE"
  chmod 0600 "$TLS_CERT_FILE"
fi

if [[ -n "${TLS_KEY_PEM:-}" ]]; then
  printf '%s' "$TLS_KEY_PEM" > "$TLS_KEY_FILE"
  chmod 0600 "$TLS_KEY_FILE"
fi
