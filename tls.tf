# ── TLS: Artifact directories ────────────────────────────────────────────────
resource "null_resource" "artifacts_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p \"${local.ssh_dir}\" \"${local.config_dir}\" \"${local.mke3_config_dir}\" \"${local.mke4_config_dir}\" \"${local.msr4_config_dir}\" \"${local.mke3_tls_dir}\" \"${local.mke4_tls_dir}\" \"${local.ingress_tls_dir}\" \"${local.msr_tls_dir}\" \"${local.msr4_tls_dir}\" \"${local.wildcard_tls_dir}\""
  }

  triggers = {
    ssh_dir         = local.ssh_dir
    config_dir      = local.config_dir
    mke3_config_dir = local.mke3_config_dir
    mke4_config_dir = local.mke4_config_dir
    msr4_config_dir = local.msr4_config_dir
    tls_dir_mke3    = local.mke3_tls_dir
    tls_dir_ingress = local.ingress_tls_dir
    tls_dir_msr     = local.msr_tls_dir
    tls_dir_mke4    = local.mke4_tls_dir
    tls_dir_msr4    = local.msr4_tls_dir
    tls_dir_wildcard = local.wildcard_tls_dir
  }
}

# ── TLS: Check existing certificates ────────────────────────────────────────
data "external" "mke3_tls_existing" {
  count = local.mke3_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.mke3_tls_common_name
    cert_file         = local.mke3_tls_cert_file
    key_file          = local.mke3_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "mke4_tls_existing" {
  count = local.mke4_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.mke4_tls_common_name
    cert_file         = local.mke4_tls_cert_file
    key_file          = local.mke4_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "ingress_tls_existing" {
  count = local.ingress_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.ingress_tls_common_name
    cert_file         = local.ingress_tls_cert_file
    key_file          = local.ingress_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "msr_tls_existing" {
  count = local.msr_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.msr_tls_common_name
    cert_file         = local.msr_tls_cert_file
    key_file          = local.msr_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

data "external" "msr4_tls_existing" {
  count = local.msr4_tls_wants_acme ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.msr4_tls_common_name
    cert_file         = local.msr4_tls_cert_file
    key_file          = local.msr4_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

# ── TLS: Wildcard ACME (*.samkhya.cloud) ────────────────────────────────────
locals {
  wildcard_tls_enabled = try(tobool(var.wildcard_tls.enabled), false) && var.use_wildcard_cert
  wildcard_domain      = "*.${local.root_domain}"
  wildcard_tls_dir     = "${local.artifacts_dir}/tlscerts/wildcard"
  wildcard_tls_ca_file   = "${local.wildcard_tls_dir}/ca.pem"
  wildcard_tls_cert_file = "${local.wildcard_tls_dir}/server.pem"
  wildcard_tls_key_file  = "${local.wildcard_tls_dir}/key.pem"
  wildcard_tls_email     = try(var.wildcard_tls.email, null)
}

data "external" "wildcard_tls_existing" {
  count = local.wildcard_tls_enabled ? 1 : 0

  program = ["bash", "${path.module}/artifacts/scripts/common/tls_cert_status.sh"]

  query = {
    domain            = local.wildcard_domain
    cert_file         = local.wildcard_tls_cert_file
    key_file          = local.wildcard_tls_key_file
    min_valid_seconds = tostring(var.tls_reuse_min_validity_hours * 3600)
  }
}

resource "tls_private_key" "wildcard_acme_account" {
  count = local.wildcard_tls_enabled && local.wildcard_tls_email != null ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "wildcard" {
  count = local.wildcard_tls_enabled && local.wildcard_tls_email != null ? 1 : 0

  account_key_pem = tls_private_key.wildcard_acme_account[0].private_key_pem
  email_address   = local.wildcard_tls_email
}

resource "acme_certificate" "wildcard" {
  count = local.wildcard_tls_enabled && local.wildcard_tls_email != null ? 1 : 0

  account_key_pem               = acme_registration.wildcard[0].account_key_pem
  common_name                   = local.wildcard_domain
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"
    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

# Write wildcard cert files to disk
resource "null_resource" "wildcard_tls_files" {
  count = local.wildcard_tls_enabled && (
    try(data.external.wildcard_tls_existing[0].result.valid, "false") != "true" ||
    try(acme_certificate.wildcard[0].certificate_pem, null) != null
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.wildcard_tls_ca_pem)
    cert_sha = sha256(local.wildcard_tls_cert_pem)
    key_sha  = sha256(local.wildcard_tls_key_pem)
    dir      = local.wildcard_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.wildcard_tls_dir
      TLS_CA_FILE   = local.wildcard_tls_ca_file
      TLS_CERT_FILE = local.wildcard_tls_cert_file
      TLS_KEY_FILE  = local.wildcard_tls_key_file
      TLS_CA_PEM    = local.wildcard_tls_ca_pem
      TLS_CERT_PEM  = local.wildcard_tls_cert_pem
      TLS_KEY_PEM   = local.wildcard_tls_key_pem
    }
  }
}

# Wildcard cert locals (computed after ACME)
locals {
  wildcard_tls_use_existing = local.wildcard_tls_enabled && try(data.external.wildcard_tls_existing[0].result.valid == "true", false)
  wildcard_tls_use_acme     = local.wildcard_tls_enabled && !local.wildcard_tls_use_existing && local.wildcard_tls_email != null

  wildcard_tls_ca_pem = local.wildcard_tls_use_existing ? (
    fileexists(local.wildcard_tls_ca_file) ? file(local.wildcard_tls_ca_file) : ""
  ) : local.wildcard_tls_use_acme ? try(acme_certificate.wildcard[0].issuer_pem, "") : ""

  wildcard_tls_cert_pem = local.wildcard_tls_use_existing ? (
    fileexists(local.wildcard_tls_cert_file) ? file(local.wildcard_tls_cert_file) : ""
  ) : local.wildcard_tls_use_acme ? try(acme_certificate.wildcard[0].certificate_pem, "") : ""

  wildcard_tls_key_pem = local.wildcard_tls_use_existing ? (
    fileexists(local.wildcard_tls_key_file) ? file(local.wildcard_tls_key_file) : ""
  ) : local.wildcard_tls_use_acme ? try(acme_certificate.wildcard[0].private_key_pem, "") : ""
}

# ── TLS: MKE3 ACME ─────────────────────────────────────────────────────────
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
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
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

# ── TLS: MKE4 ACME ─────────────────────────────────────────────────────────
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
  subject_alternative_names     = distinct(compact([
    local.mke4_domain != local.mke4_tls_common_name ? local.mke4_domain : null,
    local.mke4_ui_domain != local.mke4_tls_common_name ? local.mke4_ui_domain : null,
    local.kof_domain != local.mke4_tls_common_name ? local.kof_domain : null,
    local.k0rdent_ui_domain != local.mke4_tls_common_name ? local.k0rdent_ui_domain : null,
    local.ingress_domain != local.mke4_tls_common_name ? local.ingress_domain : null,
  ]))
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
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
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

# ── TLS: Ingress ACME ──────────────────────────────────────────────────────
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
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
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

# ── TLS: MSR ACME ──────────────────────────────────────────────────────────
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
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
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

# ── TLS: MSR4 ACME ─────────────────────────────────────────────────────────
resource "tls_private_key" "msr4_acme_account" {
  count = local.msr4_tls_use_acme ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "msr4" {
  count = local.msr4_tls_use_acme ? 1 : 0

  account_key_pem = tls_private_key.msr4_acme_account[0].private_key_pem
  email_address   = try(var.msr4_tls.email, null)
}

resource "acme_certificate" "msr4" {
  count = local.msr4_tls_use_acme ? 1 : 0

  account_key_pem               = acme_registration.msr4[0].account_key_pem
  common_name                   = local.msr4_tls_common_name
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "cloudflare"

    config = {
      CLOUDFLARE_API_TOKEN = local.cloudflare_api_token
    }
  }
}

resource "null_resource" "msr4_tls_files" {
  count = local.msr4_tls_enabled && (
    local.msr4_tls_write_files
  ) ? 1 : 0

  triggers = {
    ca_sha   = sha256(local.msr4_tls_ca_pem)
    cert_sha = sha256(local.msr4_tls_cert_pem)
    key_sha  = sha256(local.msr4_tls_key_pem)
    dir      = local.msr4_tls_dir
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/artifacts/scripts/common/write_tls_cert.sh\""
    environment = {
      TLS_DIR       = local.msr4_tls_dir
      TLS_CA_FILE   = local.msr4_tls_ca_file
      TLS_CERT_FILE = local.msr4_tls_cert_file
      TLS_KEY_FILE  = local.msr4_tls_key_file
      TLS_CA_PEM    = local.msr4_tls_ca_pem
      TLS_CERT_PEM  = local.msr4_tls_cert_pem
      TLS_KEY_PEM   = local.msr4_tls_key_pem
    }
  }
}

# ── TLS: Computed locals ───────────────────────────────────────────────────
locals {
  # ── Wildcard selection: when use_wildcard_cert=true, all services use the wildcard cert ──
  # MKE3 paths (file-based for launchpad)
  mke3_effective_tls_ca_path = local.wildcard_tls_enabled ? (
    "${local.wildcard_tls_dir}/ca.pem"
  ) : local.mke3_tls_ca_path
  mke3_effective_tls_cert_path = local.wildcard_tls_enabled ? (
    "${local.wildcard_tls_dir}/server.pem"
  ) : local.mke3_tls_cert_path
  mke3_effective_tls_key_path = local.wildcard_tls_enabled ? (
    "${local.wildcard_tls_dir}/key.pem"
  ) : local.mke3_tls_key_path
  mke3_effective_tls_common_name = local.wildcard_tls_enabled ? (
    local.wildcard_domain
  ) : local.mke3_tls_common_name

  # MSR2 PEMs (inline in launchpad msr section)
  msr2_effective_ca_pem = local.wildcard_tls_enabled ? local.wildcard_tls_ca_pem : (
    local.msr_tls_enabled ? file(local.msr_tls_ca_file) : ""
  )
  msr2_effective_cert_pem = local.wildcard_tls_enabled ? local.wildcard_tls_cert_pem : (
    local.msr_tls_enabled ? file(local.msr_tls_cert_file) : ""
  )
  msr2_effective_key_pem = local.wildcard_tls_enabled ? local.wildcard_tls_key_pem : (
    local.msr_tls_enabled ? file(local.msr_tls_key_file) : ""
  )

  # MKE4 PEMs (inline in mkectl template)
  mke4_effective_tls_present = local.wildcard_tls_enabled || local.mke4_tls_present
  mke4_effective_tls_common_name = local.wildcard_tls_enabled ? (
    local.wildcard_domain
  ) : local.mke4_tls_common_name
  mke4_effective_tls_ca_pem = local.wildcard_tls_enabled ? local.wildcard_tls_ca_pem : local.mke4_tls_ca_pem
  mke4_effective_tls_cert_pem = local.wildcard_tls_enabled ? local.wildcard_tls_cert_pem : local.mke4_tls_cert_pem
  mke4_effective_tls_key_pem = local.wildcard_tls_enabled ? local.wildcard_tls_key_pem : local.mke4_tls_key_pem

  # MSR4 paths (file-based, checked by install_msr4.sh)
  msr4_effective_tls_dir = local.wildcard_tls_enabled ? local.wildcard_tls_dir : "${local.artifacts_dir}/tlscerts/msr4"

  # MKE3 TLS
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

  # MKE4 TLS
  mke4_tls = var.mke4_tls

  mke4_tls_enabled = try(tobool(local.mke4_tls.enabled), false)

  mke4_tls_wants_acme = (
    local.mke4_tls_enabled &&
    try(tobool(local.mke4_tls.use_acme), false)
  )

  mke4_tls_common_name = local.mke4_tls_enabled ? coalesce(
    try(local.mke4_tls.common_name, null),
    local.mke4_domain
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

  # Ingress TLS
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

  # MSR TLS
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

  # MSR4 TLS
  msr4_tls = var.msr4_tls

  msr4_tls_enabled = try(coalesce(tobool(local.msr4_tls.enabled), false), false)

  msr4_tls_wants_acme = (
    local.msr4_tls_enabled &&
    try(coalesce(tobool(local.msr4_tls.use_acme), false), false)
  )

  msr4_tls_common_name = local.msr4_tls_enabled ? coalesce(
    try(local.msr4_tls.common_name, null),
    local.cloudflare_record_name_msr4
  ) : null

  msr4_tls_dir       = local.msr4_tls_enabled ? "${local.artifacts_dir}/tlscerts/msr4/${local.msr4_tls_common_name}" : "${local.artifacts_dir}/tlscerts/msr4"
  msr4_tls_ca_file   = "${local.msr4_tls_dir}/ca.pem"
  msr4_tls_cert_file = "${local.msr4_tls_dir}/server.pem"
  msr4_tls_key_file  = "${local.msr4_tls_dir}/key.pem"

  msr4_tls_use_existing   = local.msr4_tls_wants_acme && try(data.external.msr4_tls_existing[0].result.valid == "true", false)
  msr4_tls_use_acme       = local.msr4_tls_wants_acme && !local.msr4_tls_use_existing
  msr4_tls_ca_input_pem   = try(local.msr4_tls.ca_pem != null ? local.msr4_tls.ca_pem : "", "")
  msr4_tls_cert_input_pem = try(local.msr4_tls.cert_pem != null ? local.msr4_tls.cert_pem : "", "")
  msr4_tls_key_input_pem  = try(local.msr4_tls.key_pem != null ? local.msr4_tls.key_pem : "", "")
  msr4_tls_ca_pem         = local.msr4_tls_use_existing ? (fileexists(local.msr4_tls_ca_file) ? file(local.msr4_tls_ca_file) : "") : local.msr4_tls_use_acme ? try(acme_certificate.msr4[0].issuer_pem, "") : local.msr4_tls_ca_input_pem
  msr4_tls_cert_pem       = local.msr4_tls_use_existing ? file(local.msr4_tls_cert_file) : local.msr4_tls_use_acme ? try(acme_certificate.msr4[0].certificate_pem, "") : local.msr4_tls_cert_input_pem
  msr4_tls_key_pem        = local.msr4_tls_use_existing ? file(local.msr4_tls_key_file) : local.msr4_tls_use_acme ? try(acme_certificate.msr4[0].private_key_pem, "") : local.msr4_tls_key_input_pem
  msr4_tls_write_files = (
    local.msr4_tls_use_acme ||
    (length(trimspace(local.msr4_tls_cert_input_pem)) > 0 &&
    length(trimspace(local.msr4_tls_key_input_pem)) > 0)
  )
}
