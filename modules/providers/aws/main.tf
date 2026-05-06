locals {
  ssh_private_key_path = "${var.ssh_key_dir}/${var.ssh_key_prefix}-aws.pem"

  image_map = {
    ubuntu2204 = {
      owner       = "099720109477"
      name_filter = "ubuntu/images/hvm-ssd-gp3/ubuntu-jammy-22.04-amd64-server-*"
      ssh_user    = "ubuntu"
      default_int = "eth0"
    }
    ubuntu2404 = {
      owner       = "099720109477"
      name_filter = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      ssh_user    = "ubuntu"
      default_int = "eth0"
    }
    rocky9 = {
      owner       = "679593333241"
      name_filter = "Rocky-9-EC2-Base-9.*x86_64"
      ssh_user    = "rocky"
      default_int = "eth0"
    }
    rhel94 = {
      owner       = "309956199498"
      name_filter = "RHEL-9.4*x86_64*"
      ssh_user    = "ec2-user"
      default_int = "eth0"
    }
    rhel96 = {
      owner       = "309956199498"
      name_filter = "RHEL-9.6*x86_64*"
      ssh_user    = "ec2-user"
      default_int = "eth0"
    }
  }

  default_tags = merge(var.tags, {
    Cluster   = var.cluster_name
    pstesting = "true"
  })

  node_pools = [
    for pool in var.node_pools : merge(pool, {
      name              = pool.name
      count             = try(pool.count, 1)
      roles             = length(try(pool.roles, [])) > 0 ? [for role in pool.roles : lower(role)] : (try(pool.role, null) != null ? [lower(pool.role)] : [])
      os                = lower(try(pool.os, "rocky9"))
      instance_type     = try(pool.instance_type, "t3.large")
      root_volume_size  = try(pool.root_volume_size, 80)
      subnet_index      = try(pool.subnet_index, 0)
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
        instance_type     = pool.instance_type
        root_volume_size  = pool.root_volume_size
        labels            = pool.labels
        metadata          = merge(pool.metadata, { instance_type = pool.instance_type })
        private_interface = coalesce(pool.private_interface, lookup(local.image_map[pool.os], "default_int", "eth0"))
        ssh_user          = lookup(local.image_map[pool.os], "ssh_user", "ec2-user")
        subnet_index      = idx % max(length(var.availability_zones), 1)
        index             = idx + 1
        name              = "${var.resource_prefix}-${pool.name}-${format("%02d", idx + 1)}"
      }
    ]
  ])

  instances = { for spec in local.instance_specs : spec.key => spec }

  manager_instance_keys = [
    for key, spec in local.instances : key
    if contains(spec.roles, "manager")
  ]

  msr_instance_keys = [
    for key, spec in local.instances : key
    if contains(spec.roles, "msr") || contains(spec.roles, "registry")
  ]
}

# [Previous resources remain unchanged until the load balancer section...]

# MKE3 Load Balancer (replaces manager and api LBs)
resource "aws_lb" "mke3" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name               = "${substr(var.resource_prefix, 0, 17)}-mke3"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-mke3"
  })
}

# Target group for MKE3 UI (443)
resource "aws_lb_target_group" "mke3_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 17)}-mke3-443"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "443"
  }
}

# Target group for MKE3 API (6443)
resource "aws_lb_target_group" "mke3_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 17)}-mke3-6443"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "6443"
  }
}

# Ingress Load Balancer (unchanged)
resource "aws_lb" "ingress" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name               = "${substr(var.resource_prefix, 0, 14)}-ingress"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-ingress"
  })
}

# Ingress Target Group (unchanged)
resource "aws_lb_target_group" "ingress_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 17)}-ing33001"
  port        = 33001
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "33001"
  }
}

# MKE4 Load Balancer
resource "aws_lb" "mke4" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name               = "${substr(var.resource_prefix, 0, 17)}-mke4"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-mke4"
  })
}

# Target group for MKE4 UI (custom port)
resource "aws_lb_target_group" "mke4_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 12)}-m4ui${var.mke4_ui_backend_port}"
  port        = var.mke4_ui_backend_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = tostring(var.mke4_ui_backend_port)
  }
}

# Target group for MKE4 API (6443)
resource "aws_lb_target_group" "mke4_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 12)}-m4api6443"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "6443"
  }
}

# MSR Load Balancer (unchanged)
resource "aws_lb" "msr" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  name               = "${substr(var.resource_prefix, 0, 18)}-msr"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-msr"
  })
}

# MSR Target Group (unchanged)
resource "aws_lb_target_group" "msr_443" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 18)}-msr443"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "443"
  }
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "mke3_443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.mke3_443[0].arn
  target_id        = each.value
  port             = 443
}

resource "aws_lb_target_group_attachment" "mke3_6443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.mke3_6443[0].arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb_target_group_attachment" "ingress_443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.ingress_443[0].arn
  target_id        = each.value
  port             = 33001
}

resource "aws_lb_target_group_attachment" "mke4_443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.mke4_443[0].arn
  target_id        = each.value
  port             = var.mke4_ui_backend_port
}

resource "aws_lb_target_group_attachment" "mke4_6443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.mke4_6443[0].arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb_target_group_attachment" "msr_443" {
  for_each = length(local.msr_instance_keys) > 0 ? {
    for key in local.msr_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.msr_443[0].arn
  target_id        = each.value
  port             = 443
}

# Listeners
resource "aws_lb_listener" "mke3_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.mke3[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mke3_443[0].arn
  }
}

resource "aws_lb_listener" "mke3_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.mke3[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mke3_6443[0].arn
  }
}

resource "aws_lb_listener" "ingress_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.ingress[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_443[0].arn
  }
}

resource "aws_lb_listener" "mke4_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.mke4[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mke4_443[0].arn
  }
}

resource "aws_lb_listener" "mke4_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.mke4[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mke4_6443[0].arn
  }
}

resource "aws_lb_listener" "msr_443" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.msr[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.msr_443[0].arn
  }
}

