resource "null_resource" "artifacts_dirs" {
  provisioner "local-exec" {
    command = "mkdir -p \"${local.ssh_dir}\" \"${local.config_dir}\""
  }

  triggers = {
    ssh_dir    = local.ssh_dir
    config_dir = local.config_dir
  }
}

module "aws" {
  count = local.aws_enabled ? 1 : 0

  source = "./modules/providers/aws"

  cluster_name       = local.aws_settings_map.cluster_name
  vpc_cidr           = local.aws_settings_map.vpc_cidr
  availability_zones = local.aws_settings_map.availability_zones
  node_pools         = local.aws_settings_map.node_pools
  ssh_key_prefix     = local.aws_settings_map.ssh_key_prefix
  ssh_key_dir        = local.ssh_dir
  resource_prefix    = local.aws_settings_map.resource_prefix
  tags               = local.aws_settings_map.tags

  depends_on = [null_resource.artifacts_dirs]
}

module "hetzner" {
  count = local.hetzner_enabled ? 1 : 0

  source = "./modules/providers/hetzner"

  cluster_name   = local.hetzner_settings_map.cluster_name
  location       = local.hetzner_settings_map.location
  node_pools     = local.hetzner_settings_map.node_pools
  ssh_key_prefix = local.hetzner_settings_map.ssh_key_prefix
  ssh_key_dir    = local.ssh_dir
  labels         = local.hetzner_settings_map.labels
  network        = local.hetzner_settings_map.network
  create_network = local.hetzner_settings_map.create_network
  network_cidr   = local.hetzner_settings_map.network_cidr
  subnet_cidr    = local.hetzner_settings_map.subnet_cidr
  network_zone   = local.hetzner_settings_map.network_zone
  dns_source_ips = local.hetzner_settings_map.dns_source_ips

  depends_on = [null_resource.artifacts_dirs]
}

locals {
  aws_hosts             = try(module.aws[0].hosts, [])
  hetzner_hosts         = try(module.hetzner[0].hosts, [])
  azure_hosts           = []
  vsphere_hosts         = []
  aws_manager_lb_dns    = try(module.aws[0].manager_lb_dns, null)
  aws_msr_lb_dns        = try(module.aws[0].msr_lb_dns, null)
  aws_mke4_lb_dns       = try(module.aws[0].mke4_ingress_lb_dns, null)
  hetzner_manager_lb_ip = try(module.hetzner[0].manager_lb_ipv4, null)
  hetzner_msr_lb_ip     = try(module.hetzner[0].msr_lb_ipv4, null)
  hetzner_mke4_lb_ip    = try(module.hetzner[0].mke4_ingress_lb_ipv4, null)
  cloudflare_target_ip  = local.cloudflare_enabled ? try(coalesce(local.hetzner_mke4_lb_ip, local.hetzner_manager_lb_ip), null) : null

  all_hosts = concat(local.aws_hosts, local.hetzner_hosts, local.azure_hosts, local.vsphere_hosts)

  managers = [for host in local.all_hosts : host if contains(host.roles, "manager")]
  workers  = [for host in local.all_hosts : host if contains(host.roles, "worker") && !contains(host.roles, "manager")]
  msrs     = [for host in local.all_hosts : host if contains(host.roles, "msr") || contains(host.roles, "registry")]

  san_override = (
    var.san_override != null && trimspace(var.san_override) != "" ?
    trimspace(var.san_override) :
    null
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
    apiVersion        = "launchpad.mirantis.com/mke/v1.3"
    kind              = local.launchpad_kind
    cluster_name      = local.cluster_name
    admin_username    = var.admin_username
    admin_password    = var.admin_password
    mke_version       = var.mke3_version
    msr_version       = var.msr_version
    mcr_version       = var.mcr_version
    enable_msr        = var.enable_msr
    orchestrator_flag = "--default-node-orchestrator=kubernetes"
    san               = local.primary_manager_address
    msr_external_url  = local.msr_endpoint
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

  mkectl_cloud_provider = try(local.all_hosts[0].provider, "aws")
  mkectl_network_cidr   = local.aws_enabled ? local.aws_settings_map.vpc_cidr : "192.168.0.0/16"
  mkectl_external_host = coalesce(
    local.aws_mke4_lb_dns,
    local.hetzner_mke4_lb_ip,
    local.aws_manager_lb_dns,
    local.hetzner_manager_lb_ip,
    local.primary_manager_address
  )
  mkectl_sans = distinct(compact(concat(
    local.aws_mke4_lb_dns != null ? [local.aws_mke4_lb_dns] : [],
    local.aws_manager_lb_dns != null ? [local.aws_manager_lb_dns] : [],
    local.hetzner_mke4_lb_ip != null ? [local.hetzner_mke4_lb_ip] : [],
    local.hetzner_manager_lb_ip != null ? [local.hetzner_manager_lb_ip] : [],
    [for host in local.managers : try(host.public_dns, null)],
    [for host in local.managers : host.name],
    [for host in local.managers : host.public_ip],
    [for host in local.managers : host.private_ip]
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
      external_address = local.mkectl_external_host
      sans             = local.mkectl_sans
    }
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

resource "cloudflare_record" "hetzner_lb_a" {
  count = local.cloudflare_enabled ? 1 : 0

  zone_id         = local.cloudflare_settings_map.zone_id
  name            = local.cloudflare_settings_map.record_name
  type            = "A"
  content         = coalesce(local.cloudflare_target_ip, "0.0.0.0")
  ttl             = 300
  proxied         = false
  allow_overwrite = true

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [module.hetzner]
}

check "cloudflare_target_ip_present" {
  assert {
    condition     = !local.cloudflare_enabled || local.cloudflare_target_ip != null
    error_message = "Cloudflare DNS is enabled but no Hetzner load balancer IP was found."
  }
}
