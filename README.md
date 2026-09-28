# terraform-ps

Terraform for provisioning MKE3/MKE4 infrastructure on AWS and deploying Mirantis Secure Registry (MSR2/MSR4).

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with valid credentials
- `jq`, `yq`, `helm`, `kubectl` installed
- `launchpad` binary (for MKE3 clusters)

## Quick Start

### 1. Set up credentials

```bash
mkdir -p credentials
aws sts get-session-token --duration-seconds 3600 > /tmp/creds.json
```

Create `credentials/aws-profile`:

```ini
[default]
aws_access_key_id = <from /tmp/creds.json>
aws_secret_access_key = <from /tmp/creds.json>
aws_session_token = <from /tmp/creds.json>
```

### 2. Configure

Edit `config.env` (single source of truth):

```bash
CLUSTER_NAME="ps-mke"
ROOT_DOMAIN="samkhya.cloud"
CLUSTER_TYPE="mke4"
MKE4_VERSION="4.2.0"
MKE3_VERSION="3.9.5"
MSR2_VERSION="2.9.30"
ADMIN_PASSWORD="your-secure-password"
EXPIRY_DAYS="30"
```

Generate `terraform.tfvars` from config:

```bash
make config-apply
```

### 3. Deploy

```bash
make create mke4          # Deploy MKE4 cluster
make create mke3          # Deploy MKE3 cluster
make create mke4stack     # Deploy MKE4 + MSR4
make create mke3stack     # Deploy MKE3 + MSR2
```

### 4. Access

- **MKE4 UI**: `https://mke4-ui.<root_domain>`
- **MKE3 UI**: `https://mke3test.<root_domain>`
- **MSR2 (DTR)**: `https://msr2.<root_domain>`
- **MSR4 (Harbor)**: `https://msr4.<root_domain>`
- **kubectl**: `kubectl --kubeconfig artifacts/configs/kubeconfig.yaml get pods -A`
- **Credentials**: admin / password set in `config.env`

### 5. Populate with dummy data

```bash
make dummy-data-msr2   # Populate MSR2 (DTR) with users, orgs, repos
make dummy-data-msr4   # Populate MSR4 (Harbor) with users, projects, repos
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make help` | Show clean, config-driven help |
| `make config-apply` | Generate terraform.tfvars from config.env |
| `make config-get` | Show current config values |
| `make config-edit` | Open config.env in editor |
| `make create mke4` | Deploy MKE4 cluster (auto-configured via config.env) |
| `make create mke3` | Deploy MKE3 cluster (auto-configured via config.env) |
| `make create mke4stack` | Deploy MKE4 + MSR4 |
| `make create mke3stack` | Deploy MKE3 + MSR2 |
| `make update [mke3\|mke4..]` | Update running stack in-place with new config.env |
| `make list-running` | Rich tabular status with health, OS, IPs & versions |
| `make destroy mke4stack` | Auto-approved destroy |
| `make destroy mke3stack` | Auto-approved destroy |
| `make destroy` | Auto-approved destroy of active cluster |
| `make dummy-data-msr2` | Populate MSR2 (DTR) with users, orgs, repos |
| `make dummy-data-msr4` | Populate MSR4 (Harbor) with users, projects, repos |
| `make init` | Terraform init |
| `make plan` | Show infrastructure changes |
| `make apply` | Apply infrastructure changes |

## Configuration

All configuration is in `config.env`. Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `ps-mke` | Cluster name |
| `ROOT_DOMAIN` | `samkhya.cloud` | Root domain for DNS |
| `CLUSTER_TYPE` | `mke4` | `mke3` or `mke4` |
| `MKE4_VERSION` | `4.2.0` | MKE4 version |
| `MKE3_VERSION` | `3.9.5` | MKE3 version |
| `MSR2_VERSION` | `2.9.30` | MSR2 (DTR) version |
| `MSR2_ENABLED` | `true` | Enable MSR2 installation |
| `MSR4_ENABLED` | `true` | Enable MSR4 installation |
| `ADMIN_PASSWORD` | `mkepassword` | MKE admin password |
| `EXPIRY_DAYS` | `30` | Cluster auto-expiry in days |

## Resource tags and labels

The project uses provider-native metadata, keeping the existing key names and
capitalization:

| Resources | Required project metadata | Custom metadata |
|-----------|---------------------------|----------------|
| Root AWS resources, including airgap and NFS resources | `Cluster=<cluster_name>`, `ManagedBy=terraform`, `Project=terraform-ps` | Resource-specific `Name` and `Role` values |
| AWS provider module resources | `Cluster=<cluster_name>`, `pstesting=true`; each resource also has a `Name` | Set `aws_settings.tags` |
| Hetzner provider resources | `cluster=<cluster_name>` (lowercase); resources may also have a resource-specific `role` or server-pool `pool` label | Set `hetzner_settings.labels` or node-pool `labels` |

For example, add custom values in `terraform.tfvars` without replacing the
module-managed values:

```hcl
aws_settings = {
  tags = {
    CostCenter = "platform"
  }
}

hetzner_settings = {
  labels = {
    owner = "platform"
  }
}
```

`Cluster`, `pstesting`, and `cluster` are set by the provider modules and should
not be used for custom values. AWS tags and Hetzner labels are separate
provider-specific conventions; keep their key casing as shown.

## Architecture

- 1 manager node (control plane)
- 1 worker node
- 1 MSR node (container registry)
- NLBs for: MKE UI, Ingress, MSR2, MSR4
- Calico CNI with VXLAN overlay
- ACME TLS certificates via Let's Encrypt
- Cloudflare DNS integration

## Generated Files

These are created by `make apply` and should not be committed:

- `artifacts/configs/kubeconfig.yaml`
- `artifacts/configs/mke3/launchpad.yaml`
- `artifacts/configs/mke4/hosts.yaml`
- `artifacts/ssh/*.pem`
- `artifacts/tlscerts/` (ACME certificates)
- `terraform.tfvars`
- `terraform.tfstate`

## Version History

| Component | Version |
|-----------|---------|
| MKE4 | 4.2.0 |
| MKE3 | 3.9.5 |
| MSR2 (DTR) | 2.9.30 |
| MSR4 (Harbor) | 4.13.5 |
| MCR | 25.0.13 |
