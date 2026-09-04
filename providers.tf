provider "aws" {
  region = local.aws_settings_map.region

  # Credential chain: profile → shared_credentials → env vars (AWS_ACCESS_KEY_ID etc.)
  profile = local.aws_enabled && local.aws_settings_map.profile != "" ? local.aws_settings_map.profile : null

  shared_credentials_files = local.aws_enabled && local.aws_settings_map.shared_credentials_file != "" ? [
    local.aws_settings_map.shared_credentials_file
  ] : []

  skip_credentials_validation = !local.aws_settings_map.enabled
  skip_region_validation      = !local.aws_settings_map.enabled
  skip_metadata_api_check     = !local.aws_settings_map.enabled
  skip_requesting_account_id  = !local.aws_settings_map.enabled
}

provider "hcloud" {
  token = local.hetzner_enabled ? (
    try(length(trimspace(local.hetzner_token)) > 0, false) ? local.hetzner_token : null
  ) : "0000000000000000000000000000000000000000000000000000000000000000"
}

provider "cloudflare" {
  api_token = coalesce(local.cloudflare_api_token, "0000000000000000000000000000000000000000")
}

provider "tls" {}
provider "acme" {
  server_url = coalesce(
    try(var.mke3_tls.acme_directory_url, null),
    try(var.mke4_tls.acme_directory_url, null),
    try(var.ingress_tls.acme_directory_url, null),
    try(var.msr_tls.acme_directory_url, null),
    "https://acme-v02.api.letsencrypt.org/directory"
  )
}
provider "local" {}
provider "null" {}
provider "external" {}
provider "time" {}
