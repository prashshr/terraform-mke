provider "aws" {
  region = local.aws_settings_map.region

  profile = local.aws_enabled ? (
    local.aws_settings_map.profile != "" ? local.aws_settings_map.profile : null
  ) : null

  shared_credentials_files = local.aws_enabled && local.aws_settings_map.shared_credentials_file != "" ? [
    local.aws_settings_map.shared_credentials_file
  ] : []

  access_key = local.aws_enabled ? null : "DISABLED"
  secret_key = local.aws_enabled ? null : "DISABLED"

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
provider "local" {}
provider "null" {}
