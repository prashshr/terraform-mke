#!/usr/bin/env bash
set -euo pipefail

query="$(cat)"

domain="$(printf '%s' "$query" | jq -r '.domain // empty')"
cert_file="$(printf '%s' "$query" | jq -r '.cert_file // empty')"
key_file="$(printf '%s' "$query" | jq -r '.key_file // empty')"
min_valid_seconds="$(printf '%s' "$query" | jq -r '.min_valid_seconds // "604800"')"

valid=false
reason="missing"

if [[ -n "$domain" && -s "$cert_file" && -s "$key_file" ]]; then
  if openssl x509 -in "$cert_file" -noout -checkend "$min_valid_seconds" >/dev/null 2>&1; then
    names="$(openssl x509 -in "$cert_file" -noout -subject -ext subjectAltName 2>/dev/null || true)"
    if printf '%s\n' "$names" | grep -Eq "(DNS:|CN[ =])${domain//./\\.}([,[:space:]]|$)"; then
      valid=true
      reason="valid"
    else
      reason="domain_mismatch"
    fi
  else
    reason="expired_or_expiring"
  fi
fi

jq -n \
  --arg valid "$valid" \
  --arg reason "$reason" \
  '{ valid: $valid, reason: $reason }'
