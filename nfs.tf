# ── NFS: Dedicated EC2 instance for persistent storage ────────────────────
#
# When NFS_ENABLED=true, creates:
# - Dedicated EC2 instance for NFS server
# - Security group for NFS access
# - EBS volume for NFS storage
#
# NFS is used by MSR4 for persistent data (registry, postgres, redis).
# ──────────────────────────────────────────────────────────────────────────

# ── Variables ────────────────────────────────────────────────────────────────
variable "nfs_instance_type" {
  description = "EC2 instance type for the NFS server."
  type        = string
  default     = "t3.medium"
}

variable "nfs_volume_size" {
  description = "Size in GB for the NFS EBS volume."
  type        = number
  default     = 100
}

variable "nfs_export_path" {
  description = "NFS export path on the server."
  type        = string
  default     = "/srv/nfs"
}

# ── Locals ───────────────────────────────────────────────────────────────────
locals {
  nfs_enabled = var.nfs_enabled

  nfs_name = "${local.cluster_name}-nfs"
}

# ── NFS security group ────────────────────────────────────────────────────
resource "aws_security_group" "nfs" {
  count = local.nfs_enabled && local.aws_enabled ? 1 : 0

  name        = "${local.nfs_name}-sg"
  description = "Security group for NFS server"
  vpc_id      = try(module.aws[0].vpc_id, null)

  # NFS
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "NFS access from VPC"
  }

  # RPC
  ingress {
    from_port   = 111
    to_port     = 111
    protocol    = "tcp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "RPC portmapper"
  }

  # SSH (for management)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "SSH access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.nfs_name}-sg"
    Role = "nfs"
  })
}

# ── NFS EBS volume ─────────────────────────────────────────────────────────
resource "aws_ebs_volume" "nfs" {
  count = local.nfs_enabled && local.aws_enabled ? 1 : 0

  availability_zone = try(module.aws[0].availability_zones[0], "eu-west-1a")
  size              = var.nfs_volume_size
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name = "${local.nfs_name}-data"
  })
}

resource "aws_volume_attachment" "nfs" {
  count = local.nfs_enabled && local.aws_enabled ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.nfs[0].id
  instance_id = aws_instance.nfs[0].id
}

# ── NFS AMI lookup ────────────────────────────────────────────────────────
data "aws_ami" "nfs" {
  count = local.nfs_enabled && local.aws_enabled ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── NFS instance ──────────────────────────────────────────────────────────
resource "aws_instance" "nfs" {
  count = local.nfs_enabled && local.aws_enabled ? 1 : 0

  ami                    = data.aws_ami.nfs[0].id
  instance_type          = var.nfs_instance_type
  subnet_id              = try(module.aws[0].private_subnet_ids[0], module.aws[0].public_subnet_ids[0], null)
  vpc_security_group_ids = [aws_security_group.nfs[0].id]
  key_name               = try(module.aws[0].ssh_key_name, null)

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail

    # Install NFS server
    dnf install -y nfs-utils

    # Wait for EBS volume
    while [ ! -b /dev/nvme1n1 ]; do sleep 1; done

    # Format and mount EBS volume
    mkfs -t ext4 /dev/nvme1n1
    mkdir -p ${var.nfs_export_path}
    mount /dev/nvme1n1 ${var.nfs_export_path}
    echo "/dev/nvme1n1 ${var.nfs_export_path} ext4 defaults,nofail 0 2" >> /etc/fstab

    # Create subdirectories for MSR4
    mkdir -p ${var.nfs_export_path}/postgres-data \
             ${var.nfs_export_path}/trivy-data \
             ${var.nfs_export_path}/jobservice-data \
             ${var.nfs_export_path}/registry-data \
             ${var.nfs_export_path}/redis-data

    # Set permissions
    chown -R 999:999     ${var.nfs_export_path}/postgres-data
    chown -R 10000:10000 ${var.nfs_export_path}/trivy-data
    chown -R 10000:10000 ${var.nfs_export_path}/jobservice-data
    chown -R 10000:10000 ${var.nfs_export_path}/registry-data
    chown -R 999:999     ${var.nfs_export_path}/redis-data

    # Export via NFS
    echo "${var.nfs_export_path} *(rw,sync,no_subtree_check,no_root_squash,fsid=0)" > /etc/exports
    exportfs -ra

    # Enable and start NFS server
    systemctl enable --now nfs-server

    # SELinux tweaks
    if command -v setsebool &>/dev/null && selinuxenabled 2>/dev/null; then
      setsebool -P nfs_export_all_rw 1 2>/dev/null || true
      setsebool -P use_nfs_home_dirs 1 2>/dev/null || true
    fi

    echo "NFS server ready." > /var/log/nfs-setup.log
  USERDATA

  tags = merge(local.common_tags, {
    Name = local.nfs_name
    Role = "nfs"
  })
}

# ── NFS outputs ────────────────────────────────────────────────────────────
output "nfs_private_ip" {
  description = "Private IP of the NFS server."
  value       = local.nfs_enabled && local.aws_enabled ? try(aws_instance.nfs[0].private_ip, null) : null
}

output "nfs_public_ip" {
  description = "Public IP of the NFS server (if in public subnet)."
  value       = local.nfs_enabled && local.aws_enabled ? try(aws_instance.nfs[0].public_ip, null) : null
}

output "nfs_ssh_command" {
  description = "SSH command to connect to the NFS server."
  value       = local.nfs_enabled && local.aws_enabled ? "ssh -i ${local.ssh_dir}/${local.cluster_name}.pem ec2-user@${try(aws_instance.nfs[0].private_ip, "")}" : null
}
