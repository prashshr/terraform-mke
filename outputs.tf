output "all_hosts" {
  description = "Normalized host inventory across every provider."
  value       = local.all_hosts
}

output "launchpad_config_path" {
  description = "Path to the rendered launchpad.yaml file."
  value       = local.should_render ? local_sensitive_file.launchpad[0].filename : null
}

output "mke4_config_path" {
  description = "Path to the rendered mkectl config."
  value       = local.should_render ? local_sensitive_file.mke4[0].filename : null
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
  description = "External address to use for mkectl upgrade."
  value       = local.mkectl_upgrade_external_host
}

output "artifacts_directory" {
  description = "Absolute path to the artifacts directory."
  value       = local.artifacts_dir
}
