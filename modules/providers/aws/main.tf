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
      root_volume_size  = try(pool.root_volume_size, var.root_volume_size)
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

resource "aws_key_pair" "cluster" {
  key_name   = "${var.resource_prefix}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-key"
  })
}

resource "aws_vpc" "cluster" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "cluster" {
  vpc_id = aws_vpc.cluster.id

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = {
    for idx, az in var.availability_zones : idx => az
  }

  vpc_id                  = aws_vpc.cluster.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.key)
  map_public_ip_on_launch = true

  tags = merge(local.default_tags, {
    Name                                        = "${var.resource_prefix}-public-${each.value}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster.id
  }

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-public"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "cluster" {
  name        = "${var.resource_prefix}-cluster"
  description = "Cluster-wide security group"
  vpc_id      = aws_vpc.cluster.id

  ingress {
    description = "Allow all intra-cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MKE ingress HTTPS NodePort"
    from_port   = 33001
    to_port     = 33001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MKE4 UI backend NodePort"
    from_port   = var.mke4_ui_backend_port
    to_port     = var.mke4_ui_backend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-cluster"
  })
}

resource "aws_security_group" "managers" {
  name        = "${var.resource_prefix}-managers"
  description = "Manager-specific security group"
  vpc_id      = aws_vpc.cluster.id

  ingress {
    description = "Etcd peer traffic"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-managers"
  })
}

data "aws_ami" "pool" {
  for_each = {
    for pool in local.node_pools : pool.name => pool
  }

  most_recent = true
  owners      = [lookup(local.image_map[each.value.os], "owner", "679593333241")]

  filter {
    name   = "name"
    values = [lookup(local.image_map[each.value.os], "name_filter", "Rocky-9-EC2-Base-9.*x86_64")]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "node" {
  for_each = {
    for pool in local.node_pools : pool.name => pool
  }

  name_prefix = "${var.resource_prefix}-${each.value.name}-"

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = each.value.root_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    root_volume_gb = each.value.root_volume_size
  }))
}

resource "aws_instance" "node" {
  for_each = local.instances

  ami                         = data.aws_ami.pool[each.value.pool_name].id
  instance_type               = each.value.instance_type
  subnet_id                   = aws_subnet.public[tostring(each.value.subnet_index)].id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.cluster.key_name

  vpc_security_group_ids = compact(concat(
    [aws_security_group.cluster.id],
    contains(each.value.roles, "manager") ? [aws_security_group.managers.id] : []
  ))

  launch_template {
    id      = aws_launch_template.node[each.value.pool_name].id
    version = "$Latest"
  }

  tags = merge(local.default_tags, {
    Name                                        = each.value.name
    Pool                                        = each.value.pool_name
    Role                                        = length(each.value.roles) > 0 ? each.value.roles[0] : "worker"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }, each.value.labels)
}

data "aws_region" "current" {}

resource "null_resource" "resize_root_volume" {
  for_each = local.instances

  triggers = {
    instance_id  = aws_instance.node[each.key].id
    desired_size = coalesce(each.value.root_volume_size, var.root_volume_size, 120)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      ${var.profile != null ? "export AWS_PROFILE=\"${var.profile}\"" : ""}
      ${var.shared_credentials_file != null ? "export AWS_SHARED_CREDENTIALS_FILE=\"${abspath(var.shared_credentials_file)}\"" : ""}
      INSTANCE_ID="${aws_instance.node[each.key].id}"
      VOLUME_SIZE=${coalesce(each.value.root_volume_size, var.root_volume_size, 120)}
      REGION="${data.aws_region.current.name}"
      SSH_USER="${each.value.ssh_user}"
      SSH_KEY="${local.ssh_private_key_path}"
      VOLUME_ID=$(aws ec2 describe-instances \
        --instance-ids "$${INSTANCE_ID}" \
        --region "$${REGION}" \
        --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
        --output text)
      CURRENT_SIZE=$(aws ec2 describe-volumes \
        --volume-ids "$${VOLUME_ID}" \
        --region "$${REGION}" \
        --query 'Volumes[0].Size' \
        --output text)
      if [ "$${CURRENT_SIZE}" -lt "$${VOLUME_SIZE}" ]; then
        echo "Resizing volume $${VOLUME_ID} from $${CURRENT_SIZE}G to $${VOLUME_SIZE}G"
        aws ec2 modify-volume \
          --volume-id "$${VOLUME_ID}" \
          --size "$${VOLUME_SIZE}" \
          --region "$${REGION}"
      else
        echo "Volume $${VOLUME_ID} already at $${CURRENT_SIZE}G, skipping"
      fi
      PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$${INSTANCE_ID}" \
        --region "$${REGION}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
      if [ -n "$${PUBLIC_IP}" ] && [ -f "$${SSH_KEY}" ]; then
        echo "Checking and expanding partition on $${PUBLIC_IP}..."
        ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
          -i "$${SSH_KEY}" "$${SSH_USER}@$${PUBLIC_IP}" <<'REMOTESHELL' 2>&1 || echo "WARNING: remote expansion failed, check logs above"
          set -e
          ROOT_DEV=$(df / --output=source | tail -1)
          echo "Root device: $ROOT_DEV"

          # ---- non-LVM root (direct partition) ----
          if echo "$ROOT_DEV" | grep -qE '^/dev/(nvme|xd|sd)'; then
            BASE_DEV=$(echo "$ROOT_DEV" | sed 's/[0-9]*$//')
            PART_NUM=$(echo "$ROOT_DEV" | grep -oP '\d+$' || echo "")
            if [ -n "$PART_NUM" ]; then
              echo "Growing partition $PART_NUM on $BASE_DEV"
              growpart "$BASE_DEV" "$PART_NUM" || echo "growpart failed (non-fatal)"
            fi
            FS_TYPE=$(blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null)
            case "$FS_TYPE" in
              xfs)  echo "Growing XFS"; xfs_growfs / || true ;;
              ext4) echo "Resizing ext4"; resize2fs "$ROOT_DEV" || true ;;
            esac
          fi

          # ---- LVM root (e.g. /dev/mapper/rl-root) ----
          if echo "$ROOT_DEV" | grep -q '^/dev/mapper/'; then
            echo "Detected LVM root"
            PV_NAME=$(pvdisplay -C -o "PV Name" --noheadings 2>/dev/null | head -1 | xargs)
            if [ -n "$PV_NAME" ]; then
              echo "Resizing PV: $PV_NAME"
              pvresize "$PV_NAME" || true
            fi
            echo "Extending LV $ROOT_DEV to 100% FREE"
            lvextend -l +100%FREE "$ROOT_DEV" || true
            FS_TYPE=$(blkid -o value -s TYPE "$ROOT_DEV" 2>/dev/null)
            case "$FS_TYPE" in
              xfs)  echo "Growing XFS"; xfs_growfs / || true ;;
              ext4) echo "Resizing ext4"; resize2fs "$ROOT_DEV" || true ;;
            esac
          fi

          echo "Done: $(df -h / | tail -1)"
REMOTESHELL
      fi
    EOT
  }

  depends_on = [aws_instance.node]
}

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

resource "aws_lb_target_group" "mke3_443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 16)}-m3-443"
  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "443"
  }
}

resource "aws_lb_target_group" "mke3_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 15)}-m3-6443"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "6443"
  }
}

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

resource "aws_lb_target_group_attachment" "ingress_443" {
  for_each = length(local.manager_instance_keys) > 0 ? {
    for key in local.manager_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.ingress_443[0].arn
  target_id        = each.value
  port             = 33001
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

resource "aws_lb_target_group" "mke4_6443" {
  count = length(local.manager_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 15)}-m4-6443"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "6443"
  }
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

resource "aws_lb_target_group_attachment" "msr_443" {
  for_each = length(local.msr_instance_keys) > 0 ? {
    for key in local.msr_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.msr_443[0].arn
  target_id        = each.value
  port             = 443
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

# MSR4 NLB: port 443 → nodePort 34003 on msr-role instances
resource "aws_lb" "msr4" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  name               = "${substr(var.resource_prefix, 0, 18)}-msr4"
  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.default_tags, {
    Name = "${var.resource_prefix}-msr4"
  })
}

resource "aws_lb_target_group" "msr4_443" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  name        = "${substr(var.resource_prefix, 0, 16)}-msr434003"
  port        = 34003
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.cluster.id

  health_check {
    protocol = "TCP"
    port     = "34003"
  }
}

resource "aws_lb_target_group_attachment" "msr4_443" {
  for_each = length(local.msr_instance_keys) > 0 ? {
    for key in local.msr_instance_keys : key => aws_instance.node[key].id
  } : {}

  target_group_arn = aws_lb_target_group.msr4_443[0].arn
  target_id        = each.value
  port             = 34003
}

resource "aws_lb_listener" "msr4_443" {
  count = length(local.msr_instance_keys) > 0 ? 1 : 0

  load_balancer_arn = aws_lb.msr4[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.msr4_443[0].arn
  }
}
