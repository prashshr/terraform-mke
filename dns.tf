# ── DNS: Cloudflare zone lookup ─────────────────────────────────────────────
data "cloudflare_zones" "lookup" {
  count = local.cloudflare_enabled && local.cloudflare_settings_map.zone_name != "" ? 1 : 0

  filter {
    name = local.cloudflare_settings_map.zone_name
  }
}

# ── DNS: Cloudflare records ────────────────────────────────────────────────
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

resource "cloudflare_record" "aws_mke4" {
  count = (local.cloudflare_enabled && local.aws_enabled && local.cloudflare_record_name_mke4 != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_mke4
  type            = "CNAME"
  content         = local.aws_mke4_ui_lb_dns
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = false
  }
}

resource "cloudflare_record" "aws_msr4" {
  count = (local.cloudflare_enabled && local.aws_enabled && local.cloudflare_record_name_msr4 != null &&
  try(length(trimspace(local.cloudflare_zone_id)) > 0, false) && local.cloudflare_zone_id != "placeholder-zone-id") ? 1 : 0

  zone_id         = local.cloudflare_zone_id
  name            = local.cloudflare_record_name_msr4
  type            = "CNAME"
  content         = local.aws_msr4_lb_dns
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
