resource "null_resource" "artifacts_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p \"${local.ssh_dir}\" \"${local.config_dir}\" \"${local.mke3_tls_dir}\" \"${local.mke4_tls_dir}\" \"${local.ingress_tls_dir}\" \"${local.msr_tls_dir}\""
  }

  triggers = {
    ssh_dir         = local.ssh_dir
    config_dir      = local.config_dir
    tls_dir_mke3    = local.mke3_tls_dir
    tls_dir_ingress = local.ingress_tls_dir
    tls_dir_msr     = local.msr_tls_dir
    tls_dir_mke4    = local.mke4_tls_dir
  }
}

data "external" "mke3_tls_existing" {
  count = local.mke3_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/scripts/tls_cert_status.sh"]

  query = {
    domain            = local.mke3_tls_common_name
    cert_file         = local.mke3_tls_cert_file
    key_file          = local.mke3_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "mke4_tls_existing" {
  count = local.mke4_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/scripts/tls_cert_status.sh"]

  query = {
    domain            = local.mke4_tls_common_name
    cert_file         = local.mke4_tls_cert_file
    key_file          = local.mke4_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "ingress_tls_existing" {
  count = local.ingress_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/scripts/tls_cert_status.sh"]

  query = {
    domain            = local.ingress_tls_common_name
    cert_file         = local.ingress_tls_cert_file
    key_file          = local.ingress_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "msr_tls_existing" {
  count = local.msr_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/scripts/tls_cert_status.sh"]

  query = {
    domain            = local.msr_tls_common_name
    cert_file         = local.msr_tls_cert_file
    key_file          = local.msr_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

resource "tls_private_key" "mke3_acme_account" {
  count = local.mke3_tls_use_acme ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "mke3" {
  count = local.mke3_tls_use_acme ? 1 : 0

  account_key_pem = tls_private_key.mke3_acme_account[0].private_key_pem
  email_address   = try(var.mke3_tls.email, null)
}

resource "acme_certificate" "mke3" {
  count = local.mke3_tls_use_acme ? 1 : 0

  account_key_pem               = acme_registration.mke3[0].account_key_pem
  common_name                   = local.mke3_tls_common_name
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"
    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

resource "null_resource" "mke3_tls_files" {
  count = local.mke3_tls_enabled && (
    local.mke3_tls_write_files
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.mke3_tls_ca_pem)
    cert_sha = sha256(local.mke3_tls_cert_pem)
    key_sha  = sha256(local.mke3_tls_key_pem)
    dir      = local.mke3_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.mke3_tls_dir
      TLS_CA_FILE   = local.mke3_tls_ca_file
      TLS_CERT_FILE = local.mke3_tls_cert_file
      TLS_KEY_FILE  = local.mke3_tls_key_file
      TLS_CA_PEM    = local.mke3_tls_ca_pem
      TLS_CERT_PEM  = local.mke3_tls_cert_pem
      TLS_KEY_PEM   = local.mke3_tls_key_pem
    }
  }
}

resource "tls_private_key" "mke4_acme_account" {
  count = local.mke4_tls_use_acme ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "mke4" {
  count = local.mke4_tls_use_acme ? 1 : 0

  account_key_pem = tls_private_key.mke4_acme_account[0].private_key_pem
  email_address   = try(var.mke4_tls.email, null)
}

resource "acme_certificate" "mke4" {
  count = local.mke4_tls_use_acme ? 1 : 0

  account_key_pem               = acme_registration.mke4[0].account_key_pem
  common_name                   = local.mke4_tls_common_name
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"

    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

resource "null_resource" "mke4_tls_files" {
  count = local.mke4_tls_enabled && (
    local.mke4_tls_write_files
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.mke4_tls_ca_pem)
    cert_sha = sha256(local.mke4_tls_cert_pem)
    key_sha  = sha256(local.mke4_tls_key_pem)
    dir      = local.mke4_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.mke4_tls_dir
      TLS_CA_FILE   = local.mke4_tls_ca_file
      TLS_CERT_FILE = local.mke4_tls_cert_file
      TLS_KEY_FILE  = local.mke4_tls_key_file
      TLS_CA_PEM    = local.mke4_tls_ca_pem
      TLS_CERT_PEM  = local.mke4_tls_cert_pem
      TLS_KEY_PEM   = local.mke4_tls_key_pem
    }
  }
}

resource "tls_private_key" "ingress_acme_account" {
  count = local.ingress_tls_use_acme ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "ingress" {
  count = local.ingress_tls_use_acme ? 1 : 0

  account_key_pem = tls_private_key.ingress_acme_account[0].private_key_pem
  email_address   = try(var.ingress_tls.email, null)
}

resource "acme_certificate" "ingress" {
  count = local.ingress_tls_use_acme ? 1 : 0

  account_key_pem               = acme_registration.ingress[0].account_key_pem
  common_name                   = local.ingress_tls_common_name
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"

    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

resource "null_resource" "ingress_tls_files" {
  count = local.ingress_tls_enabled && (
    local.ingress_tls_write_files
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.ingress_tls_ca_pem)
    cert_sha = sha256(local.ingress_tls_cert_pem)
    key_sha  = sha256(local.ingress_tls_key_pem)
    dir      = local.ingress_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.ingress_tls_dir
      TLS_CA_FILE   = local.ingress_tls_ca_file
      TLS_CERT_FILE = local.ingress_tls_cert_file
      TLS_KEY_FILE  = local.ingress_tls_key_file
      TLS_CA_PEM    = local.ingress_tls_ca_pem
      TLS_CERT_PEM  = local.ingress_tls_cert_pem
      TLS_KEY_PEM   = local.ingress_tls_key_pem
    }
  }
}

resource "tls_private_key" "msr_acme_account" {
  count = local.msr_tls_use_acme ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "msr" {
  count = local.msr_tls_use_acme ? 1 : 0

  account_key_pem = tls_private_key.msr_acme_account[0].private_key_pem
  email_address   = try(var.msr_tls.email, null)
}

resource "acme_certificate" "msr" {
  count = local.msr_tls_use_acme ? 1 : 0

  account_key_pem               = acme_registration.msr[0].account_key_pem
  common_name                   = local.msr_tls_common_name
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"

    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

resource "null_resource" "msr_tls_files" {
  count = local.msr_tls_enabled && (
    local.msr_tls_write_files
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.msr_tls_ca_pem)
    cert_sha = sha256(local.msr_tls_cert_pem)
    key_sha  = sha256(local.msr_tls_key_pem)
    dir      = local.msr_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.msr_tls_dir
      TLS_CA_FILE   = local.msr_tls_ca_file
      TLS_CERT_FILE = local.msr_tls_cert_file
      TLS_KEY_FILE  = local.msr_tls_key_file
      TLS_CA_PEM    = local.msr_tls_ca_pem
      TLS_CERT_PEM  = local.msr_tls_cert_pem
      TLS_KEY_PEM   = local.msr_tls_key_pem
    }
  }
}

module "aws" {
  count = local.aws_enabled ? 1 : 0

  source = "./modules/providers/aws"

  cluster_name            = local.aws_settings_map.cluster_name
  vpc_cidr                = local.aws_settings_map.vpc_cidr
  availability_zones      = local.aws_settings_map.availability_zones
  node_pools              = local.aws_settings_map.node_pools
  ssh_key_prefix          = local.aws_settings_map.ssh_key_prefix
  ssh_key_dir             = local.ssh_dir
  resource_prefix         = local.aws_settings_map.resource_prefix
  tags                    = local.aws_settings_map.tags
  mke4_ui_backend_port    = local.aws_settings_map.mke4_ui_backend_port
  root_volume_size        = local.aws_settings_map.root_volume_size
  profile                 = try(local.aws_settings_map.profile, null)
  shared_credentials_file = try(local.aws_settings_map.shared_credentials_file, null)

  depends_on = [null_resource.artifacts_dirs]
}

module "hetzner" {
  count = local.hetzner_enabled ? 1 : 0

  source = "./modules/providers/hetzner"

  cluster_name         = local.hetzner_settings_map.cluster_name
  location             = local.hetzner_settings_map.location
  node_pools           = local.hetzner_settings_map.node_pools
  ssh_key_prefix       = local.hetzner_settings_map.ssh_key_prefix
  ssh_key_dir          = local.ssh_dir
  labels               = local.hetzner_settings_map.labels
  network              = local.hetzner_settings_map.network
  create_network       = local.hetzner_settings_map.create_network
  network_cidr         = local.hetzner_settings_map.network_cidr
  subnet_cidr          = local.hetzner_settings_map.subnet_cidr
  network_zone         = local.hetzner_settings_map.network_zone
  dns_source_ips       = local.hetzner_settings_map.dns_source_ips
  mke4_ui_backend_port = local.hetzner_settings_map.mke4_ui_backend_port

  depends_on = [null_resource.artifacts_dirs]
}

data "cloudflare_zones" "lookup" {
  count = local.cloudflare_enabled && local.cloudflare_settings_map.zone_name != "" ? 1 : 0

  filter {
    name = local.cloudflare_settings_map.zone_name
  }
}

locals {
  aws_hosts             = try(module.aws[0].hosts, [])
  hetzner_hosts         = try(module.hetzner[0].hosts, [])
  azure_hosts           = []
  vsphere_hosts         = []
  aws_manager_lb_dns    = try(module.aws[0].manager_lb_dns, null)
  aws_ingress_lb_dns    = try(module.aws[0].ingress_lb_dns, null)
  aws_api_lb_dns        = try(module.aws[0].api_lb_dns, null)
  aws_mke4_ui_lb_dns    = try(module.aws[0].mke4_ui_lb_dns, null)
  aws_msr_lb_dns        = try(module.aws[0].msr_lb_dns, null)
  hetzner_manager_lb_ip = try(module.hetzner[0].manager_lb_ipv4, null)
  hetzner_ingress_lb_ip = try(module.hetzner[0].ingress_lb_ipv4, null)
  hetzner_api_lb_ip     = try(module.hetzner[0].api_lb_ipv4, null)
  hetzner_mke4_ui_lb_ip = try(module.hetzner[0].mke4_ui_lb_ipv4, null)
  hetzner_msr_lb_ip     = try(module.hetzner[0].msr_lb_ipv4, null)

  all_hosts = concat(local.aws_hosts, local.hetzner_hosts, local.azure_hosts, local.vsphere_hosts)

  managers = [for host in local.all_hosts : host if contains(host.roles, "manager")]
  workers  = [for host in local.all_hosts : host if contains(host.roles, "worker") && !contains(host.roles, "manager")]
  msrs     = [for host in local.all_hosts : host if contains(host.roles, "msr") || contains(host.roles, "registry")]

  san_override = (
    var.san_override != null && trimspace(var.san_override) != "" ?
    trimspace(var.san_override) :
    null
  )

  mke3_tls = var.mke3_tls

  mke3_tls_enabled = try(tobool(local.mke3_tls.enabled), false)

  mke3_tls_wants_acme = (
    local.mke3_tls_enabled &&
    try(tobool(local.mke3_tls.use_acme), false)
  )

  mke3_tls_common_name = local.mke3_tls_enabled ? coalesce(
    try(local.mke3_tls.common_name, null),
    local.cloudflare_record_name_manager
  ) : null

  mke3_tls_email = try(local.mke3_tls.email, null)

  mke3_tls_dir       = local.mke3_tls_enabled ? "${local.artifacts_dir}/tlscerts/mke3/${local.mke3_tls_common_name}" : "${local.artifacts_dir}/tlscerts/mke3"
  mke3_tls_ca_file   = local.mke3_tls_enabled ? "${local.mke3_tls_dir}/ca.pem" : null
  mke3_tls_cert_file = local.mke3_tls_enabled ? "${local.mke3_tls_dir}/server.pem" : null
  mke3_tls_key_file  = local.mke3_tls_enabled ? "${local.mke3_tls_dir}/key.pem" : null
  mke3_tls_ca_path   = local.mke3_tls_enabled ? "./artifacts/tlscerts/mke3/${local.mke3_tls_common_name}/ca.pem" : null
  mke3_tls_cert_path = local.mke3_tls_enabled ? "./artifacts/tlscerts/mke3/${local.mke3_tls_common_name}/server.pem" : null
  mke3_tls_key_path  = local.mke3_tls_enabled ? "./artifacts/tlscerts/mke3/${local.mke3_tls_common_name}/key.pem" : null

  mke3_tls_use_existing   = local.mke3_tls_wants_acme && try(data.external.mke3_tls_existing[0].result.valid == "true", false)
  mke3_tls_use_acme       = local.mke3_tls_wants_acme && !local.mke3_tls_use_existing
  mke3_tls_ca_input_pem   = try(local.mke3_tls.ca_pem != null ? local.mke3_tls.ca_pem : "", "")
  mke3_tls_cert_input_pem = try(local.mke3_tls.cert_pem != null ? local.mke3_tls.cert_pem : "", "")
  mke3_tls_key_input_pem  = try(local.mke3_tls.key_pem != null ? local.mke3_tls.key_pem : "", "")
  mke3_tls_ca_pem         = local.mke3_tls_use_existing ? (fileexists(local.mke3_tls_ca_file) ? file(local.mke3_tls_ca_file) : "") : local.mke3_tls_use_acme ? try(acme_certificate.mke3[0].issuer_pem, "") : local.mke3_tls_ca_input_pem
  mke3_tls_cert_pem       = local.mke3_tls_use_existing ? file(local.mke3_tls_cert_file) : local.mke3_tls_use_acme ? try(acme_certificate.mke3[0].certificate_pem, "") : local.mke3_tls_cert_input_pem
  mke3_tls_key_pem        = local.mke3_tls_use_existing ? file(local.mke3_tls_key_file) : local.mke3_tls_use_acme ? try(acme_certificate.mke3[0].private_key_pem, "") : local.mke3_tls_key_input_pem
  mke3_tls_write_files = (
    local.mke3_tls_use_acme ||
    (length(trimspace(local.mke3_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.mke3_tls_key_input_pem)) > 0)
  )

  mke4_tls = var.mke4_tls

  mke4_tls_enabled = try(tobool(local.mke4_tls.enabled), false)

  mke4_tls_wants_acme = (
    local.mke4_tls_enabled &&
    try(tobool(local.mke4_tls.use_acme), false)
  )

  mke4_tls_common_name = local.mke4_tls_enabled ? coalesce(
    try(local.mke4_tls.common_name, null),
    local.cloudflare_record_name_mke4_ui
  ) : null

  mke4_tls_dir       = local.mke4_tls_enabled ? "${local.artifacts_dir}/tlscerts/mke4/${local.mke4_tls_common_name}" : "${local.artifacts_dir}/tlscerts/mke4"
  mke4_tls_ca_file   = "${local.mke4_tls_dir}/ca.pem"
  mke4_tls_cert_file = "${local.mke4_tls_dir}/server.pem"
  mke4_tls_key_file  = "${local.mke4_tls_dir}/key.pem"

  mke4_tls_use_existing   = local.mke4_tls_wants_acme && try(data.external.mke4_tls_existing[0].result.valid == "true", false)
  mke4_tls_use_acme       = local.mke4_tls_wants_acme && !local.mke4_tls_use_existing
  mke4_tls_ca_input_pem   = try(local.mke4_tls.ca_pem != null ? local.mke4_tls.ca_pem : "", "")
  mke4_tls_cert_input_pem = try(local.mke4_tls.cert_pem != null ? local.mke4_tls.cert_pem : "", "")
  mke4_tls_key_input_pem  = try(local.mke4_tls.key_pem != null ? local.mke4_tls.key_pem : "", "")
  mke4_tls_ca_pem         = local.mke4_tls_use_existing ? (fileexists(local.mke4_tls_ca_file) ? file(local.mke4_tls_ca_file) : "") : local.mke4_tls_use_acme ? try(acme_certificate.mke4[0].issuer_pem, "") : local.mke4_tls_ca_input_pem
  mke4_tls_cert_pem       = local.mke4_tls_use_existing ? file(local.mke4_tls_cert_file) : local.mke4_tls_use_acme ? try(acme_certificate.mke4[0].certificate_pem, "") : local.mke4_tls_cert_input_pem
  mke4_tls_key_pem        = local.mke4_tls_use_existing ? file(local.mke4_tls_key_file) : local.mke4_tls_use_acme ? try(acme_certificate.mke4[0].private_key_pem, "") : local.mke4_tls_key_input_pem
  mke4_tls_present = local.mke4_tls_enabled && (
    local.mke4_tls_use_acme ||
    local.mke4_tls_use_existing ||
    (length(trimspace(local.mke4_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.mke4_tls_key_input_pem)) > 0)
  )
  mke4_tls_write_files = (
    local.mke4_tls_use_acme ||
    (length(trimspace(local.mke4_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.mke4_tls_key_input_pem)) > 0)
  )

  ingress_tls = var.ingress_tls

  ingress_tls_enabled = try(tobool(local.ingress_tls.enabled), false)

  ingress_tls_wants_acme = (
    local.ingress_tls_enabled &&
    try(tobool(local.ingress_tls.use_acme), false)
  )

  ingress_tls_common_name = local.ingress_tls_enabled ? coalesce(
    try(local.ingress_tls.common_name, null),
    local.cloudflare_record_name_ingress
  ) : null

  ingress_tls_dir       = local.ingress_tls_enabled ? "${local.artifacts_dir}/tlscerts/ingress/${local.ingress_tls_common_name}" : "${local.artifacts_dir}/tlscerts/ingress"
  ingress_tls_ca_file   = "${local.ingress_tls_dir}/ca.pem"
  ingress_tls_cert_file = "${local.ingress_tls_dir}/server.pem"
  ingress_tls_key_file  = "${local.ingress_tls_dir}/key.pem"

  ingress_tls_use_existing   = local.ingress_tls_wants_acme && try(data.external.ingress_tls_existing[0].result.valid == "true", false)
  ingress_tls_use_acme       = local.ingress_tls_wants_acme && !local.ingress_tls_use_existing
  ingress_tls_ca_input_pem   = try(local.ingress_tls.ca_pem != null ? local.ingress_tls.ca_pem : "", "")
  ingress_tls_cert_input_pem = try(local.ingress_tls.cert_pem != null ? local.ingress_tls.cert_pem : "", "")
  ingress_tls_key_input_pem  = try(local.ingress_tls.key_pem != null ? local.ingress_tls.key_pem : "", "")
  ingress_tls_ca_pem         = local.ingress_tls_use_existing ? (fileexists(local.ingress_tls_ca_file) ? file(local.ingress_tls_ca_file) : "") : local.ingress_tls_use_acme ? try(acme_certificate.ingress[0].issuer_pem, "") : local.ingress_tls_ca_input_pem
  ingress_tls_cert_pem       = local.ingress_tls_use_existing ? file(local.ingress_tls_cert_file) : local.ingress_tls_use_acme ? try(acme_certificate.ingress[0].certificate_pem, "") : local.ingress_tls_cert_input_pem
  ingress_tls_key_pem        = local.ingress_tls_use_existing ? file(local.ingress_tls_key_file) : local.ingress_tls_use_acme ? try(acme_certificate.ingress[0].private_key_pem, "") : local.ingress_tls_key_input_pem
  ingress_tls_write_files = (
    local.ingress_tls_use_acme ||
    (length(trimspace(local.ingress_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.ingress_tls_key_input_pem)) > 0)
  )

  msr_tls = var.msr_tls

  msr_tls_enabled = try(tobool(local.msr_tls.enabled), false)

  msr_tls_wants_acme = (
    local.msr_tls_enabled &&
    try(tobool(local.msr_tls.use_acme), false)
  )

  msr_tls_common_name = local.msr_tls_enabled ? coalesce(
    try(local.msr_tls.common_name, null),
    local.msr_domain
  ) : null

  msr_tls_dir       = local.msr_tls_enabled ? "${local.artifacts_dir}/tlscerts/msr/${local.msr_tls_common_name}" : "${local.artifacts_dir}/tlscerts/msr"
  msr_tls_ca_file   = "${local.msr_tls_dir}/ca.pem"
  msr_tls_cert_file = "${local.msr_tls_dir}/server.pem"
  msr_tls_key_file  = "${local.msr_tls_dir}/key.pem"

  msr_tls_use_existing   = local.msr_tls_wants_acme && try(data.external.msr_tls_existing[0].result.valid == "true", false)
  msr_tls_use_acme       = local.msr_tls_wants_acme && !local.msr_tls_use_existing
  msr_tls_ca_input_pem   = try(local.msr_tls.ca_pem != null ? local.msr_tls.ca_pem : "", "")
  msr_tls_cert_input_pem = try(local.msr_tls.cert_pem != null ? local.msr_tls.cert_pem : "", "")
  msr_tls_key_input_pem  = try(local.msr_tls.key_pem != null ? local.msr_tls.key_pem : "", "")
  msr_tls_ca_pem         = local.msr_tls_use_existing ? (fileexists(local.msr_tls_ca_file) ? file(local.msr_tls_ca_file) : "") : local.msr_tls_use_acme ? try(acme_certificate.msr[0].issuer_pem, "") : local.msr_tls_ca_input_pem
  msr_tls_cert_pem       = local.msr_tls_use_existing ? file(local.msr_tls_cert_file) : local.msr_tls_use_acme ? try(acme_certificate.msr[0].certificate_pem, "") : local.msr_tls_cert_input_pem
  msr_tls_key_pem        = local.msr_tls_use_existing ? file(local.msr_tls_key_file) : local.msr_tls_use_acme ? try(acme_certificate.msr[0].private_key_pem, "") : local.msr_tls_key_input_pem
  msr_tls_write_files = (
    local.msr_tls_use_acme ||
    (length(trimspace(local.msr_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.msr_tls_key_input_pem)) > 0)
  )

  primary_manager_address = local.san_override != null ? local.san_override : (
    local.aws_manager_lb_dns != null ? local.aws_manager_lb_dns :
    local.hetzner_manager_lb_ip != null ? local.hetzner_manager_lb_ip :
    try(local.managers[0].public_ip, null)
  )

  msr_endpoint = coalesce(
    local.aws_msr_lb_dns,
    local.hetzner_msr_lb_ip,
    try(local.msrs[0].public_ip, null),
    local.primary_manager_address
  )

  launchpad_context = {
    apiVersion           = "launchpad.mirantis.com/mke/v1.3"
    kind                 = local.launchpad_kind
    cluster_name         = local.cluster_name
    admin_username       = var.admin_username
    admin_password       = var.admin_password
    mke_version          = var.mke3_version
    msr_version          = var.msr_version
    mcr_version          = var.mcr_version
    enable_msr           = var.enable_msr
    orchestrator_flag    = "--default-node-orchestrator=kubernetes"
    san                  = local.primary_manager_address
    msr_external_url     = local.msr_endpoint
    mke_ca_cert_path     = local.mke3_tls_ca_path
    mke_cert_path        = local.mke3_tls_cert_path
    mke_key_path         = local.mke3_tls_key_path
    mke3_tls_common_name = local.mke3_tls_common_name
    managers = [for host in local.managers : {
      public_ip         = host.public_ip
      ssh_user          = host.ssh_user
      ssh_port          = host.ssh_port
      ssh_key_path      = host.ssh_key_path
      private_interface = host.private_interface
    }]
    msrs = [for host in local.msrs : {
      public_ip         = host.public_ip
      ssh_user          = host.ssh_user
      ssh_port          = host.ssh_port
      ssh_key_path      = host.ssh_key_path
      private_interface = host.private_interface
    }]
    workers = [for host in local.workers : {
      public_ip         = host.public_ip
      ssh_user          = host.ssh_user
      ssh_port          = host.ssh_port
      ssh_key_path      = host.ssh_key_path
      private_interface = host.private_interface
    }]
  }

  mkectl_hosts = [
    for host in local.all_hosts : {
      role = contains(host.roles, "manager") ? "controller+worker" : "worker"
      ssh = {
        address = host.public_ip
        user    = host.ssh_user
        port    = host.ssh_port
        keyPath = host.ssh_key_path
      }
      privateInterface = host.private_interface
      labels           = host.labels
      hostname         = host.name
      metadata         = host.metadata
      connection_type  = host.connection_type
    }
  ]

  mkectl_version = startswith(lower(var.mke4_version), "v") ? var.mke4_version : "v${var.mke4_version}"

  mkectl_cloud_provider    = try(local.all_hosts[0].provider, "aws")
  mkectl_network_cidr      = local.aws_enabled ? local.aws_settings_map.vpc_cidr : "192.168.0.0/16"
  mkectl_api_external_host = local.mke4_domain
  mkectl_upgrade_external_host = coalesce(
    local.aws_mke4_ui_lb_dns,
    local.hetzner_mke4_ui_lb_ip,
    local.mkectl_api_external_host
  )
  mkectl_sans = distinct(compact(concat(
    local.aws_manager_lb_dns != null ? [local.aws_manager_lb_dns] : [],
    local.aws_ingress_lb_dns != null ? [local.aws_ingress_lb_dns] : [],
    local.aws_api_lb_dns != null ? [local.aws_api_lb_dns] : [],
    local.aws_mke4_ui_lb_dns != null ? [local.aws_mke4_ui_lb_dns] : [],
    local.hetzner_manager_lb_ip != null ? [local.hetzner_manager_lb_ip] : [],
    local.hetzner_ingress_lb_ip != null ? [local.hetzner_ingress_lb_ip] : [],
    local.hetzner_api_lb_ip != null ? [local.hetzner_api_lb_ip] : [],
    local.hetzner_mke4_ui_lb_ip != null ? [local.hetzner_mke4_ui_lb_ip] : [],
    [for host in local.all_hosts : try(host.public_dns, null)],
    [for host in local.all_hosts : host.name],
    [for host in local.all_hosts : host.public_ip],
    [for host in local.all_hosts : host.private_ip]
  )))

  mkectl_context = {
    apiVersion     = "mke.mirantis.com/v1alpha1"
    kind           = "MkeConfig"
    cluster_name   = local.cluster_name
    namespace      = "mke"
    admin_username = var.admin_username
    admin_password = var.admin_password
    version        = local.mkectl_version
    hosts          = local.mkectl_hosts
    cloud_provider = local.mkectl_cloud_provider
    network_cidr   = local.mkectl_network_cidr
    api_server = {
      external_address = local.mke4_domain
      sans             = local.mkectl_sans
    }
    mke4_tls_present     = local.mke4_tls_present
    mke4_tls_common_name = local.mke4_tls_common_name
    mke4_tls_ca_pem      = local.mke4_tls_ca_pem
    mke4_tls_cert_pem    = local.mke4_tls_cert_pem
    mke4_tls_key_pem     = local.mke4_tls_key_pem
  }

  mkectl_upgrade_context = {
    hosts_path              = "${local.config_dir}/hosts.yaml"
    mke3_admin_username     = var.admin_username
    mke3_admin_password     = var.admin_password
    mke3_external_address   = local.primary_manager_address
    external_address        = local.mkectl_upgrade_external_host
    gateway_http_node_port  = var.mke4_gateway_http_node_port
    gateway_https_node_port = var.mke4_gateway_https_node_port
  }

  hosts_context = {
    hosts = [
      for host in local.all_hosts : {
        address = host.public_ip
        port    = host.ssh_port
        user    = host.ssh_user
        keyPath = host.ssh_key_path
      }
    ]
  }

  should_render = local.manager_pool_count > 0
}

resource "local_sensitive_file" "launchpad" {
  count = local.should_render ? 1 : 0

  filename             = "${local.config_dir}/launchpad.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = templatefile("${path.module}/templates/launchpad.yaml.tmpl", local.launchpad_context)

  depends_on = [null_resource.artifacts_dirs]
}

resource "local_sensitive_file" "mke4" {
  count = local.should_render ? 1 : 0

  filename             = "${local.config_dir}/mke4.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = templatefile("${path.module}/templates/mke4.yaml.tmpl", local.mkectl_context)

  depends_on = [null_resource.artifacts_dirs]
}

resource "local_sensitive_file" "hosts" {
  count = local.should_render ? 1 : 0

  filename             = "${local.config_dir}/hosts.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = templatefile("${path.module}/templates/hosts.yaml.tmpl", local.hosts_context)

  depends_on = [null_resource.artifacts_dirs]
}

resource "local_sensitive_file" "mkectl_upgrade_env" {
  count = local.should_render ? 1 : 0

  filename             = "${local.config_dir}/mkectl-upgrade.env"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = <<-EOT
MKCTL_UPGRADE_HOSTS_PATH='${local.mkectl_upgrade_context.hosts_path}'
MKCTL_UPGRADE_ADMIN_USERNAME='${local.mkectl_upgrade_context.mke3_admin_username}'
MKCTL_UPGRADE_ADMIN_PASSWORD='${local.mkectl_upgrade_context.mke3_admin_password}'
MKCTL_MKE3_EXTERNAL_ADDRESS='${local.mkectl_upgrade_context.mke3_external_address}'
MKCTL_UPGRADE_EXTERNAL_ADDRESS='${local.mkectl_upgrade_context.external_address}'
MKCTL_UPGRADE_GATEWAY_HTTP_NODE_PORT='${local.mkectl_upgrade_context.gateway_http_node_port}'
MKCTL_UPGRADE_GATEWAY_HTTPS_NODE_PORT='${local.mkectl_upgrade_context.gateway_https_node_port}'
  EOT

  depends_on = [null_resource.artifacts_dirs]
}

resource "cloudflare_record" "aws_manager" {
  count = (local.cloudflare_enabled && local.aws_enabled && local.cloudflare_record_name_manager != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_manager
  type            = "CNAME"
  content         = local.aws_manager_lb_dns
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "aws_ingress" {
  count = (local.cloudflare_enabled && local.aws_enabled && local.cloudflare_record_name_ingress != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_ingress
  type            = "CNAME"
  content         = local.aws_ingress_lb_dns
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "aws_mke4_ui" {
  count = (local.cloudflare_enabled && local.aws_enabled && local.cloudflare_record_name_mke4_ui != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_mke4_ui
  type            = "CNAME"
  content         = local.aws_mke4_ui_lb_dns
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "hetzner_default" {
  count = (local.cloudflare_enabled && local.hetzner_enabled && local.cloudflare_settings_map.record_name != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_settings_map.record_name
  type            = "A"
  content         = local.hetzner_ingress_lb_ip
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "hetzner_manager" {
  count = (local.cloudflare_enabled && local.hetzner_enabled && local.cloudflare_record_name_manager != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_manager
  type            = "A"
  content         = local.hetzner_manager_lb_ip
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "hetzner_ingress" {
  count = (local.cloudflare_enabled && local.hetzner_enabled && local.cloudflare_record_name_ingress != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_ingress
  type            = "A"
  content         = local.hetzner_ingress_lb_ip
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "hetzner_mke4_ui" {
  count = (local.cloudflare_enabled && local.hetzner_enabled && local.cloudflare_record_name_mke4_ui != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_mke4_ui
  type            = "A"
  content         = local.hetzner_mke4_ui_lb_ip
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "extra" {
  count = (local.cloudflare_enabled && try(length(trimspace(local.cloudflare_zone_id)) > 0, false) &&
  local.cloudflare_zone_id != "placeholder-zone-id") ? length(var.cloudflare_records) : 0

  zone_id         = local.cloudflare_zone_id
  name            = var.cloudflare_records[count.index].name
  type            = var.cloudflare_records[count.index].type
  content         = var.cloudflare_records[count.index].content
  ttl             = 300
  proxied         = coalesce(var.cloudflare_records[count.index].proxied, false)
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

check "cloudflare_zone_id_present" {
  assert {
    condition     = !local.cloudflare_enabled || try(length(trimspace(local.cloudflare_zone_id)) > 0, false)
    error_message = "Cloudflare is enabled but no zone_id or zone_name resolved to a Cloudflare zone."
  }
}
