# ── Airgap: Bastion, private subnet, and SSH tunnels ───────────────────────
#
# When AIRGAP_ENABLED=true, creates:
# - Bastion host with public IP (registry + DNS + proxy)
# - Private subnet (no internet gateway)
# - SSH tunnel commands for remote access
#
# The bastion is the only internet-facing machine. Cluster nodes
# communicate through the bastion for package/image pulls.
# ──────────────────────────────────────────────────────────────────────────

# ── Variables ────────────────────────────────────────────────────────────────
variable "airgap_bastion_instance_type" {
  description = "EC2 instance type for the airgap bastion host."
  type        = string
  default     = "t3.medium"
}

variable "airgap_bastion_ami" {
  description = "AMI ID for the bastion host. Uses Amazon Linux 2023 if empty."
  type        = string
  default     = ""
}

# ── Local: airgap enabled? ──────────────────────────────────────────────────
locals {
  airgap_enabled = var.airgap_enabled

  bastion_name = "${local.cluster_name}-bastion"

  # Resolve bastion AMI (latest AL2023)
  bastion_ami = local.airgap_enabled && var.airgap_bastion_ami == "" ? (
    try(data.aws_ami.bastion[0].id, "")
  ) : var.airgap_bastion_ami
}

# ── AMI lookup for bastion ──────────────────────────────────────────────────
data "aws_ami" "bastion" {
  count = local.airgap_enabled && local.aws_enabled && var.airgap_bastion_ami == "" ? 1 : 0

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

# ── Bastion security group ─────────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  count = local.airgap_enabled && local.aws_enabled ? 1 : 0

  name        = "${local.bastion_name}-sg"
  description = "Security group for airgap bastion host"
  vpc_id      = try(module.aws[0].vpc_id, null)

  # SSH (tunnel entry point)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access for tunneling"
  }

  # Harbor registry (direct access from cluster nodes)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "Registry access from VPC"
  }

  # DNS
  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "DNS resolution from VPC"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [try(module.aws[0].vpc_cidr, "10.40.0.0/16")]
    description = "DNS resolution from VPC (TCP)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name    = "${local.bastion_name}-sg"
    Cluster = local.cluster_name
    Role    = "bastion"
  }
}

# ── Bastion EIP ──────────────────────────────────────────────────────────────
resource "aws_eip" "bastion" {
  count = local.airgap_enabled && local.aws_enabled ? 1 : 0

  instance = try(aws_instance.bastion[0].id, "")
  domain   = "vpc"

  tags = {
    Name    = "${local.bastion_name}-eip"
    Cluster = local.cluster_name
  }
}

# ── Bastion instance ────────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  count = local.airgap_enabled && local.aws_enabled ? 1 : 0

  ami                         = local.bastion_ami != "" ? local.bastion_ami : null
  instance_type               = var.airgap_bastion_instance_type
  subnet_id                   = try(module.aws[0].public_subnet_ids[0], null)
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  associate_public_ip_address = true
  key_name                    = try(module.aws[0].ssh_key_name, null)

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -euo pipefail

    # Install Docker (for Harbor registry)
    dnf install -y docker
    systemctl enable --now docker

    # Install bind9 (DNS)
    dnf install -y bind bind-utils

    # Install socat (for port forwarding)
    dnf install -y socat || true

    # Create Harbor config directory
    mkdir -p /opt/harbor

    # Pull and start Harbor (offline installer)
    # This is done manually after bootstrap
    echo "Bastion ready. Run Harbor setup manually." > /opt/harbor/STATUS
  USERDATA

  tags = {
    Name    = local.bastion_name
    Cluster = local.cluster_name
    Role    = "bastion"
  }
}

# ── Bastion outputs ─────────────────────────────────────────────────────────
output "airgap_bastion_public_ip" {
  description = "Public IP of the airgap bastion host."
  value       = local.airgap_enabled && local.aws_enabled ? try(aws_eip.bastion[0].public_ip, null) : null
}

output "airgap_bastion_private_ip" {
  description = "Private IP of the airgap bastion host."
  value       = local.airgap_enabled && local.aws_enabled ? try(aws_instance.bastion[0].private_ip, null) : null
}

output "airgap_bastion_ssh_command" {
  description = "SSH command to connect to the bastion."
  value       = local.airgap_enabled && local.aws_enabled ? "ssh -i ${local.ssh_dir}/${local.cluster_name}.pem ubuntu@${try(aws_eip.bastion[0].public_ip, "")}" : null
}
