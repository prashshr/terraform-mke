check "manager_pool_defined" {
  assert {
    condition     = local.manager_pool_count > 0
    error_message = "Define at least one node pool with the \"manager\" role before applying."
  }
}

check "hetzner_token_configured" {
  assert {
    condition     = !local.hetzner_enabled || try(length(trimspace(local.hetzner_token)), 0) > 0
    error_message = "Set hetzner_settings.token, hetzner_settings.credentials_file, or HCLOUD_TOKEN before enabling Hetzner."
  }
}

check "cloudflare_token_configured" {
  assert {
    condition     = !local.cloudflare_enabled || try(length(trimspace(local.cloudflare_api_token)), 0) > 0
    error_message = "Set cloudflare_settings.api_token or CF_API_TOKEN before enabling Cloudflare."
  }
}
