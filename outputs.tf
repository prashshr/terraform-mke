output "root_domain" {
  description = "Primary DNS domain from variables."
  value       = local.root_domain
}

output "all_hosts" {
  description = "Normalized host inventory across every provider."
  value       = local.all_hosts
}

output "launchpad_config_path" {
  description = "Path to the rendered launchpad.yaml file."
  value       = local.render_mke3 ? local_sensitive_file.launchpad[0].filename : null
}

output "mke4_config_path" {
  description = "Path to the rendered mkectl config (version-specific)."
  value       = local.render_mke4 ? local_sensitive_file.mke4[0].filename : null
}

output "hosts_config_path" {
  description = "Path to the rendered hosts.yaml file."
  value       = local.should_render ? local_sensitive_file.hosts[0].filename : null
}

output "mke4_upgrade_env_path" {
  description = "Path to the rendered mkectl upgrade env file."
  value       = local.should_render ? local_sensitive_file.mkectl_upgrade_env[0].filename : null
}

output "mke4_external_address" {
  description = "External address for MKE4 API server."
  value       = local.mkectl_api_external_host
}

output "mke4_ui_domain" {
  description = "FQDN for MKE4 UI."
  value       = local.mke4_ui_domain
}

output "mke4_version" {
  description = "Current MKE4 version configured."
  value       = var.mke4_version
}

output "artifacts_directory" {
  description = "Absolute path to the artifacts directory."
  value       = local.artifacts_dir
}

output "wildcard_cert_enabled" {
  description = "Whether the wildcard *.root_domain certificate is enabled."
  value       = local.wildcard_tls_enabled
}

output "wildcard_cert_paths" {
  description = "Paths to the wildcard certificate files (if enabled)."
  value = local.wildcard_tls_enabled ? {
    ca   = local.wildcard_tls_ca_file
    cert = local.wildcard_tls_cert_file
    key  = local.wildcard_tls_key_file
  } : null
}
