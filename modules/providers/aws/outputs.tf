output "hosts" {
  value = [
    for key, instance in aws_instance.node : {
      id                = local.instances[key].key
      name              = local.instances[key].name
      pool_name         = local.instances[key].pool_name
      pool_display_name = local.instances[key].pool_display_name
      provider          = "aws"
      connection_type   = "ssh"
      os                = local.instances[key].os
      roles             = local.instances[key].roles
      labels            = local.instances[key].labels
      metadata          = local.instances[key].metadata
      public_ip         = instance.public_ip
      private_ip        = instance.private_ip
      public_dns        = instance.public_dns
      ssh_user          = local.instances[key].ssh_user
      ssh_port          = 22
      ssh_key_path      = local.ssh_private_key_path
      private_interface = local.instances[key].private_interface
    }
  ]
}

output "manager_lb_dns" {
  value = try(aws_lb.manager[0].dns_name, null)
}

output "mke4_ingress_lb_dns" {
  value = try(aws_lb.ingress[0].dns_name, null)
}

output "ingress_lb_dns" {
  value = try(aws_lb.ingress[0].dns_name, null)
}

output "api_lb_dns" {
  value = try(aws_lb.api[0].dns_name, null)
}

output "mke4_ui_lb_dns" {
  value = try(aws_lb.mke4[0].dns_name, null)
}

output "msr_lb_dns" {
  value = try(aws_lb.msr[0].dns_name, null)
}
