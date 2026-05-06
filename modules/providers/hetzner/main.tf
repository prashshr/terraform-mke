locals {
  ssh_private_key_path = "${var.ssh_key_dir}/${var.ssh_key_prefix}-hetzner.pem"

  image_map = {
    ubuntu2204 = {
      image       = "ubuntu-22.04"
      ssh_user    = "root"
      default_int = "eth0"
    }
    ubuntu2404 = {
      image       = "ubuntu-24.04"
      ssh_user    = "root"
      default_int = "eth0"
    }
    rocky9 = {
      image       = "rocky-9"
      ssh_user    = "root"
      default_int = "eth0"
    }
    rhel94 = {
      image       = "rocky-9"
      ssh_user    = "root"
      default_int = "eth0"
    }
    rhel96 = {
      image       = "rocky-9"
      ssh_user    = "root"
      default_int = "eth0"
    }
  }

  node_pools = [
    for pool in var.node_pools : merge(pool, {
      name              = pool.name
      count             = try(pool.count, 1)
      roles             = length(try(pool.roles, [])) > 0 ? [for role in pool.roles : lower(role)] : (try(pool.role, null) != null ? [lower(pool.role)] : [])
      os                = lower(try(pool.os, "ubuntu2204"))
      server_type       = try(pool.server_type, "cx23")
      private_interface = try(pool.private_interface, null)
      labels            = try(pool.labels, {})
      metadata          = try(pool.metadata, {})
    })
  ]

  instance_specs = flatten([
    for pool in local.node_pools : [
      for idx in range(pool.count) : {
        key               = "${pool.name}-${format("%02d", idx + 1)}"
        pool_name         = pool.name
        pool_display_name = pool.name
        roles             = pool.roles
        os                = pool.os
        server_type       = pool.server_type
        labels            = pool.labels
        metadata          = merge(pool.metadata, { server_type = pool.server_type })
        private_interface = coalesce(pool.private_interface, lookup(local.image_map[pool.os], "default_int", "eth0"))
        ssh_user          = lookup(local.image_map[pool.os], "ssh_user", "root")
        image             = lookup(local.image_map[pool.os], "image", "ubuntu-22.04")
        name              = "${var.cluster_name}-${pool.name}-${format("%02d", idx + 1)}"
      }
    ]
  ])

  instances = { for spec in local.instance_specs : spec.key => spec }

  manager_keys = [
    for key, spec in local.instances : key
    if contains(spec.roles, "manager")
  ]

  msr_keys = [
    for key, spec in local.instances : key
    if contains(spec.roles, "msr") || contains(spec.roles, "registry")
  ]

  create_network_enabled = var.create_network
  network_attached       = var.network != null || var.create_network
  network_id             = var.create_network ? hcloud_network.cluster[0].id : (var.network != null ? var.network : null)

  internal_source_ips = local.network_attached ? ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"] : ["0.0.0.0/0", "::/0"]
  dns_source_ips      = local.network_attached ? local.internal_source_ips : (length(var.dns_source_ips) > 0 ? var.dns_source_ips : ["0.0.0.0/0", "::/0"])

  common_labels = merge(var.labels, {
    cluster = var.cluster_name
  })
}

resource "null_resource" "ssh_dir" {
  provisioner "local-exec" {
    command = "mkdir -p \"${var.ssh_key_dir}\""
  }

  triggers = {
    ssh_key_dir = var.ssh_key_dir
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename             = local.ssh_private_key_path
  file_permission      = "0600"
  directory_permission = "0700"
  content              = tls_private_key.ssh.private_key_pem

  depends_on = [null_resource.ssh_dir]
}

resource "hcloud_ssh_key" "cluster" {
  name       = "${var.cluster_name}-${var.ssh_key_prefix}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "hcloud_network" "cluster" {
  count = local.create_network_enabled ? 1 : 0

  name     = "${var.cluster_name}-net"
  ip_range = var.network_cidr

  labels = merge(local.common_labels, {
    role = "network"
  })
}

resource "hcloud_network_subnet" "cluster" {
  count = local.create_network_enabled ? 1 : 0

  network_id   = hcloud_network.cluster[0].id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_cidr
}

resource "hcloud_firewall" "cluster" {
  name = "${var.cluster_name}-cluster"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "53"
    source_ips = local.dns_source_ips
  }

  dynamic "rule" {
    for_each = toset(concat([
      "179",
      "2376",
      "33001",
      "5473",
      "6444",
      "9055",
      "9099",
      "10248",
      "10250",
      "12376",
      "12378-12388",
      "12391",
      "12392",
    ], [tostring(var.mke4_ui_backend_port)]))

    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = local.internal_source_ips
    }
  }

  labels = merge(local.common_labels, {
    role = "firewall"
  })
}

resource "hcloud_server" "node" {
  for_each = local.instances

  name         = each.value.name
  image        = each.value.image
  server_type  = each.value.server_type
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.cluster.id]
  firewall_ids = [hcloud_firewall.cluster.id]

  dynamic "network" {
    for_each = local.network_id != null ? [local.network_id] : []

    content {
      network_id = network.value
    }
  }

  labels = merge(local.common_labels, each.value.labels, {
    pool = each.value.pool_name
  })
}

resource "hcloud_load_balancer" "manager" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  name               = "${var.cluster_name}-manager"
  load_balancer_type = "lb11"
  location           = var.location

  labels = merge(local.common_labels, {
    role = "manager-lb"
  })
}

resource "hcloud_load_balancer_service" "manager_443" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  load_balancer_id = hcloud_load_balancer.manager[0].id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer" "ingress" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  name               = "${var.cluster_name}-ingress"
  load_balancer_type = "lb11"
  location           = var.location

  labels = merge(local.common_labels, {
    role = "ingress-lb"
  })
}

resource "hcloud_load_balancer_service" "ingress_443" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  load_balancer_id = hcloud_load_balancer.ingress[0].id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 33001

  health_check {
    protocol = "tcp"
    port     = 33001
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_network" "ingress" {
  count = length(local.manager_keys) > 0 && local.network_attached ? 1 : 0

  load_balancer_id = hcloud_load_balancer.ingress[0].id
  network_id       = local.network_id
}

resource "hcloud_load_balancer_target" "ingress_nodes" {
  for_each = length(local.manager_keys) > 0 ? {
    for key in local.manager_keys : key => hcloud_server.node[key].id
  } : {}

  type             = "server"
  load_balancer_id = hcloud_load_balancer.ingress[0].id
  server_id        = each.value
  use_private_ip   = local.network_attached

  depends_on = [hcloud_load_balancer_network.ingress]
}

resource "hcloud_load_balancer" "api" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  name               = "${var.cluster_name}-api"
  load_balancer_type = "lb11"
  location           = var.location

  labels = merge(local.common_labels, {
    role = "api-lb"
  })
}

resource "hcloud_load_balancer_service" "api_6443" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  load_balancer_id = hcloud_load_balancer.api[0].id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_network" "api" {
  count = length(local.manager_keys) > 0 && local.network_attached ? 1 : 0

  load_balancer_id = hcloud_load_balancer.api[0].id
  network_id       = local.network_id
}

resource "hcloud_load_balancer_target" "api_nodes" {
  for_each = length(local.manager_keys) > 0 ? {
    for key in local.manager_keys : key => hcloud_server.node[key].id
  } : {}

  type             = "server"
  load_balancer_id = hcloud_load_balancer.api[0].id
  server_id        = each.value
  use_private_ip   = local.network_attached

  depends_on = [hcloud_load_balancer_network.api]
}

resource "hcloud_load_balancer" "mke4" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  name               = "${var.cluster_name}-mke4"
  load_balancer_type = "lb11"
  location           = var.location

  labels = merge(local.common_labels, {
    role = "mke4-lb"
  })
}

resource "hcloud_load_balancer_service" "mke4_443" {
  count = length(local.manager_keys) > 0 ? 1 : 0

  load_balancer_id = hcloud_load_balancer.mke4[0].id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = var.mke4_ui_backend_port

  health_check {
    protocol = "tcp"
    port     = var.mke4_ui_backend_port
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_network" "mke4" {
  count = length(local.manager_keys) > 0 && local.network_attached ? 1 : 0

  load_balancer_id = hcloud_load_balancer.mke4[0].id
  network_id       = local.network_id
}

resource "hcloud_load_balancer_target" "mke4_nodes" {
  for_each = length(local.manager_keys) > 0 ? {
    for key in local.manager_keys : key => hcloud_server.node[key].id
  } : {}

  type             = "server"
  load_balancer_id = hcloud_load_balancer.mke4[0].id
  server_id        = each.value
  use_private_ip   = local.network_attached

  depends_on = [hcloud_load_balancer_network.mke4]
}

resource "hcloud_load_balancer" "msr" {
  count = length(local.msr_keys) > 0 ? 1 : 0

  name               = "${var.cluster_name}-msr"
  load_balancer_type = "lb11"
  location           = var.location

  labels = merge(local.common_labels, {
    role = "msr-lb"
  })
}

resource "hcloud_load_balancer_service" "msr_443" {
  count = length(local.msr_keys) > 0 ? 1 : 0

  load_balancer_id = hcloud_load_balancer.msr[0].id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

resource "hcloud_load_balancer_network" "msr" {
  count = length(local.msr_keys) > 0 && local.network_attached ? 1 : 0

  load_balancer_id = hcloud_load_balancer.msr[0].id
  network_id       = local.network_id
}

resource "hcloud_load_balancer_target" "msr_nodes" {
  for_each = length(local.msr_keys) > 0 ? {
    for key in local.msr_keys : key => hcloud_server.node[key].id
  } : {}

  type             = "server"
  load_balancer_id = hcloud_load_balancer.msr[0].id
  server_id        = each.value
  use_private_ip   = local.network_attached

  depends_on = [hcloud_load_balancer_network.msr]
}
