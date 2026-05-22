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
    error_message = "Set cloudflare_settings.api_token, CF_API_TOKEN, or CLOUDFLARE_API_TOKEN before enabling Cloudflare."
  }
}

check "provider_enabled" {
  assert {
    condition     = local.aws_enabled || local.hetzner_enabled || local.azure_enabled || local.vsphere_enabled
    error_message = "Enable at least one provider (aws, hetzner, azure, or vsphere) with node pools to provision infrastructure."
  }
}

check "mke3_tls_acme_email" {
  assert {
    condition     = !local.mke3_tls_use_acme || try(length(trimspace(local.mke3_tls_email)), 0) > 0
    error_message = "mke3_tls has use_acme = true but no email address configured. Set mke3_tls.email."
  }
}

check "mke4_tls_acme_email" {
  assert {
    condition     = !local.mke4_tls_use_acme || try(length(trimspace(try(var.mke4_tls.email, null))), 0) > 0
    error_message = "mke4_tls has use_acme = true but no email address configured. Set mke4_tls.email."
  }
}

check "ingress_tls_acme_email" {
  assert {
    condition     = !local.ingress_tls_use_acme || try(length(trimspace(try(var.ingress_tls.email, null))), 0) > 0
    error_message = "ingress_tls has use_acme = true but no email address configured. Set ingress_tls.email."
  }
}

check "msr_tls_acme_email" {
  assert {
    condition     = !local.msr_tls_use_acme || try(length(trimspace(try(var.msr_tls.email, null))), 0) > 0
    error_message = "msr_tls has use_acme = true but no email address configured. Set msr_tls.email."
  }
}
