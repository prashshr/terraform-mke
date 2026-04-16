output "hosts" {
  value = [
    for key, server in hcloud_server.node : {
      id                = local.instances[key].key
      name              = local.instances[key].name
      pool_name         = local.instances[key].pool_name
      pool_display_name = local.instances[key].pool_display_name
      provider          = "hetzner"
      connection_type   = "ssh"
      os                = local.instances[key].os
      roles             = local.instances[key].roles
      labels            = local.instances[key].labels
      metadata          = local.instances[key].metadata
      public_ip         = server.ipv4_address
      private_ip        = local.network_attached ? try(server.network[0].ip, server.ipv4_address) : server.ipv4_address
      public_dns        = null
      ssh_user          = local.instances[key].ssh_user
      ssh_port          = 22
      ssh_key_path      = local.ssh_private_key_path
      private_interface = local.instances[key].private_interface
    }
  ]
}

output "manager_lb_ipv4" {
  value = try(hcloud_load_balancer.manager[0].ipv4, null)
}

output "mke4_ingress_lb_ipv4" {
  value = try(hcloud_load_balancer.mke4[0].ipv4, null)
}

output "msr_lb_ipv4" {
  value = try(hcloud_load_balancer.msr[0].ipv4, null)
}
