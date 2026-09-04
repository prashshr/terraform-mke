# ── Templates: Rendered configuration files ─────────────────────────────────
resource "local_sensitive_file" "launchpad" {
  count = local.render_mke3 ? 1 : 0

  filename             = "${local.config_dir}/launchpad.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = templatefile("${path.module}/templates/launchpad.yaml.tmpl", local.launchpad_context)

  depends_on = [null_resource.artifacts_dirs]
}

resource "local_sensitive_file" "mke4" {
  count = local.render_mke4 ? 1 : 0

  filename             = "${local.config_dir}/mke4-v${local.mke4_version_major_minor}.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = templatefile(local.mke4_template_path, local.mkectl_context)

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
