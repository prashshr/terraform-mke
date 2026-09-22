#!/usr/bin/env bash
set -euo pipefail

install -d -m 0700 "$TLS_DIR"

if [[ -n "${TLS_CA_PEM:-}" ]]; then
  printf '%s' "$TLS_CA_PEM" > "$TLS_CA_FILE"
  chmod 0600 "$TLS_CA_FILE"
fi

if [[ -n "${TLS_CERT_PEM:-}" ]]; then
  # Bundle the CA chain into the cert file so the server serves the full chain.
  # Idempotent: if cert_pem already contains the CA (e.g. read back from a
  # previously bundled server.pem via use_existing), do not append again.
  if [[ -n "${TLS_CA_PEM:-}" ]]; then
    ca_head=$(printf '%s\n' "$TLS_CA_PEM" | head -1)
    if printf '%s' "$TLS_CERT_PEM" | grep -qF "$ca_head"; then
      printf '%s' "$TLS_CERT_PEM" > "$TLS_CERT_FILE"
    else
      printf '%s\n%s' "$TLS_CERT_PEM" "$TLS_CA_PEM" > "$TLS_CERT_FILE"
    fi
  else
    printf '%s' "$TLS_CERT_PEM" > "$TLS_CERT_FILE"
  fi
  chmod 0600 "$TLS_CERT_FILE"
fi

if [[ -n "${TLS_KEY_PEM:-}" ]]; then
  printf '%s' "$TLS_KEY_PEM" > "$TLS_KEY_FILE"
  chmod 0600 "$TLS_KEY_FILE"
fi
