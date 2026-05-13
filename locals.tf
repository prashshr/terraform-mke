locals {
  cluster_name = var.cluster_name

  provider_defaults = {
    aws = {
      enabled                 = false
      region                  = "eu-west-1"
      profile                 = ""
      shared_credentials_file = "credentials/aws-profile"
      resource_prefix         = var.cluster_name
      cluster_name            = var.cluster_name
      vpc_cidr                = "10.40.0.0/16"
      availability_zones      = ["eu-west-1a", "eu-west-1b"]
      ssh_key_prefix          = var.cluster_name
      node_pools              = []
      tags                    = {}
      mke4_ui_backend_port    = var.mke4_ui_backend_port
    }
    hetzner = {
      enabled              = false
      location             = "hel1"
      network              = null
      create_network       = false
      network_cidr         = "10.42.0.0/16"
      subnet_cidr          = "10.42.0.0/24"
      network_zone         = "eu-central"
      dns_source_ips       = []
      cluster_name         = var.cluster_name
      ssh_key_prefix       = var.cluster_name
      node_pools           = []
      labels               = {}
      token                = null
      credentials_file     = null
      mke4_ui_backend_port = var.mke4_ui_backend_port
    }
    cloudflare = {
      enabled     = false
      zone_id     = ""
      record_name = var.cluster_name
      api_token   = null
    }
    azure = {
      enabled            = false
      location           = "westeurope"
      subscription_id    = ""
      tenant_id          = ""
      client_id          = ""
      client_secret      = ""
      environment        = "AzurePublicCloud"
      credentials_file   = ""
      resource_group     = "${var.cluster_name}-rg"
      vnet_cidr          = "10.60.0.0/16"
      subnet_cidr        = "10.60.10.0/24"
      ssh_key_prefix     = var.cluster_name
      node_pools         = []
      availability_zones = []
      tags               = {}
    }
    vsphere = {
      enabled        = false
      server         = ""
      user           = ""
      password       = ""
      password_file  = ""
      datacenter     = ""
      datastore      = ""
      cluster        = ""
      network        = ""
      folder         = "/${var.cluster_name}"
      ssh_key_prefix = var.cluster_name
      template_map   = {}
      node_pools     = []
    }
  }

  aws_settings_override = {
    for k, v in var.aws_settings : k => v if v != null
  }
  hetzner_settings_override = {
    for k, v in var.hetzner_settings : k => v if v != null
  }
  cloudflare_settings_override = {
    for k, v in var.cloudflare_settings : k => v if v != null
  }
  azure_settings_override = {
    for k, v in var.azure_settings : k => v if v != null
  }
  vsphere_settings_override = {
    for k, v in var.vsphere_settings : k => v if v != null
  }

  aws_settings_map        = merge(local.provider_defaults.aws, local.aws_settings_override)
  hetzner_settings_map    = merge(local.provider_defaults.hetzner, local.hetzner_settings_override)
  cloudflare_settings_map = merge(local.provider_defaults.cloudflare, local.cloudflare_settings_override)
  azure_settings_map      = merge(local.provider_defaults.azure, local.azure_settings_override)
  vsphere_settings_map    = merge(local.provider_defaults.vsphere, local.vsphere_settings_override)

  root_domain = coalesce(
    try(var.root_domain, null),
    try(local.cloudflare_settings_map.zone_name, null),
    "samkhya.cloud"
  )

  app_domain_mke3    = coalesce(try(var.app_domain_mke3, null), "mke3")
  app_domain_mke4    = coalesce(try(var.app_domain_mke4, null), "mke4")
  app_domain_ingress = coalesce(try(var.app_domain_ingress, null), "ingress")
  app_domain_msr     = coalesce(try(var.app_domain_msr, null), "msr")

  mke3_domain    = "${local.app_domain_mke3}.${local.root_domain}"
  mke4_domain    = "${local.app_domain_mke4}.${local.root_domain}"
  ingress_domain = "${local.app_domain_ingress}.${local.root_domain}"
  msr_domain     = "${local.app_domain_msr}.${local.root_domain}"

  cloudflare_record_name_manager = coalesce(
    try(local.cloudflare_settings_map.record_name_manager, null),
    local.mke3_domain
  )
  cloudflare_record_name_ingress = coalesce(
    try(local.cloudflare_settings_map.record_name_ingress, null),
    local.ingress_domain
  )
  cloudflare_record_name_mke4_ui = coalesce(
    try(local.cloudflare_settings_map.record_name_mke4_ui, null),
    local.mke4_domain
  )

  aws_enabled     = try(local.aws_settings_map.enabled, false) && length(try(local.aws_settings_map.node_pools, [])) > 0
  hetzner_enabled = try(local.hetzner_settings_map.enabled, false) && length(try(local.hetzner_settings_map.node_pools, [])) > 0
  azure_enabled   = try(local.azure_settings_map.enabled, false) && length(try(local.azure_settings_map.node_pools, [])) > 0
  vsphere_enabled = try(local.vsphere_settings_map.enabled, false) && length(try(local.vsphere_settings_map.node_pools, [])) > 0
  cloudflare_enabled = try(local.cloudflare_settings_map.enabled, false) && (
    try(length(trimspace(local.cloudflare_settings_map.zone_id)) > 0, false) ||
    try(length(trimspace(local.cloudflare_settings_map.zone_name)) > 0, false)
  )

  cloudflare_zone_id = local.cloudflare_enabled ? (
    local.cloudflare_settings_map.zone_id != "" ? local.cloudflare_settings_map.zone_id :
    local.cloudflare_settings_map.zone_name != "" ? try(data.cloudflare_zones.lookup[0].zones[0].id, "placeholder-zone-id") :
    null
  ) : null

  hetzner_env_token = local.hetzner_settings_map.enabled && fileexists("/proc/self/environ") ? (
    try(element([
      for entry in split("\u0000", file("/proc/self/environ")) :
      trimprefix(entry, "HCLOUD_TOKEN=")
      if startswith(entry, "HCLOUD_TOKEN=")
    ], 0), null)
  ) : null

  hetzner_file_token = (
    local.hetzner_settings_map.credentials_file != null &&
    local.hetzner_settings_map.credentials_file != "" &&
    can(file(local.hetzner_settings_map.credentials_file)) &&
    try(length(trimspace(chomp(file(local.hetzner_settings_map.credentials_file)))), 0) > 0
  ) ? trimspace(chomp(file(local.hetzner_settings_map.credentials_file))) : null

  hetzner_token = local.hetzner_settings_map.enabled ? try(coalesce(
    try(trimspace(local.hetzner_env_token), null),
    try(trimspace(local.hetzner_settings_map.token), null),
    local.hetzner_file_token
  ), null) : null

  cloudflare_env_token = local.cloudflare_enabled && fileexists("/proc/self/environ") ? (
    try(element([
      for entry in split("\u0000", file("/proc/self/environ")) :
      trimprefix(entry, "CF_API_TOKEN=")
      if startswith(entry, "CF_API_TOKEN=")
    ], 0), null)
  ) : null

  cloudflare_env_token_alt = local.cloudflare_enabled && fileexists("/proc/self/environ") ? (
    try(element([
      for entry in split("\u0000", file("/proc/self/environ")) :
      trimprefix(entry, "CLOUDFLARE_API_TOKEN=")
      if startswith(entry, "CLOUDFLARE_API_TOKEN=")
    ], 0), null)
  ) : null

  cloudflare_api_token = local.cloudflare_enabled ? coalesce(
    try(trimspace(local.cloudflare_env_token), null),
    try(trimspace(local.cloudflare_env_token_alt), null),
    try(trimspace(local.cloudflare_settings_map.api_token), null)
  ) : null

  aws_cloudflare_records = local.aws_enabled ? [
    for rec in [
      local.cloudflare_record_name_manager != null && local.aws_manager_lb_dns != null ? {
        name    = local.cloudflare_record_name_manager
        type    = "CNAME"
        content = local.aws_manager_lb_dns
        proxied = false
      } : null,
      local.cloudflare_record_name_ingress != null && local.aws_ingress_lb_dns != null ? {
        name    = local.cloudflare_record_name_ingress
        type    = "CNAME"
        content = local.aws_ingress_lb_dns
        proxied = false
      } : null,
      local.cloudflare_record_name_mke4_ui != null && local.aws_mke4_ui_lb_dns != null ? {
        name    = local.cloudflare_record_name_mke4_ui
        type    = "CNAME"
        content = local.aws_mke4_ui_lb_dns
        proxied = false
      } : null
    ] : rec if rec != null
  ] : []

  hetzner_cloudflare_records = local.hetzner_enabled ? [
    for rec in [
      local.cloudflare_settings_map.record_name != null && local.hetzner_ingress_lb_ip != null ? {
        name    = local.cloudflare_settings_map.record_name
        type    = "A"
        content = local.hetzner_ingress_lb_ip
        proxied = false
      } : null,
      local.cloudflare_record_name_manager != null && local.hetzner_manager_lb_ip != null ? {
        name    = local.cloudflare_record_name_manager
        type    = "A"
        content = local.hetzner_manager_lb_ip
        proxied = false
      } : null,
      local.cloudflare_record_name_ingress != null && local.hetzner_ingress_lb_ip != null ? {
        name    = local.cloudflare_record_name_ingress
        type    = "A"
        content = local.hetzner_ingress_lb_ip
        proxied = false
      } : null,
      local.cloudflare_record_name_mke4_ui != null && local.hetzner_mke4_ui_lb_ip != null ? {
        name    = local.cloudflare_record_name_mke4_ui
        type    = "A"
        content = local.hetzner_mke4_ui_lb_ip
        proxied = false
      } : null
    ] : rec if rec != null
  ] : []

  cloudflare_dns_records = concat(
    local.hetzner_cloudflare_records,
    local.aws_cloudflare_records,
    var.cloudflare_records
  )

  configured_node_pools = concat(
    local.aws_enabled ? local.aws_settings_map.node_pools : [],
    local.hetzner_enabled ? local.hetzner_settings_map.node_pools : [],
    local.azure_enabled ? local.azure_settings_map.node_pools : [],
    local.vsphere_enabled ? local.vsphere_settings_map.node_pools : []
  )

  manager_pool_count = length([
    for pool in local.configured_node_pools : 1
    if length([
      for role in(
        length(try(pool.roles, [])) > 0 ?
        [for r in pool.roles : lower(r)] :
        (try(pool.role, null) != null ? [lower(pool.role)] : [])
      ) : role
      if role == "manager"
    ]) > 0
  ])

  artifacts_dir = abspath(coalesce(var.artifacts_dir, "${path.root}/artifacts"))
  ssh_dir       = "${local.artifacts_dir}/ssh"
  config_dir    = "${local.artifacts_dir}/configs"

  launchpad_kind = var.enable_msr ? "mke+msr" : "mke"
}
