# terraform-ps

Terraform for provisioning MKE3/MKE4 infrastructure on AWS and deploying Mirantis Secure Registry (MSR4).

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with valid credentials
- `jq`, `yq`, `helm`, `kubectl` installed

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

Edit `terraform.tfvars` with your settings:

```hcl
cluster_name     = "ps-mke"
resource_prefix  = "ps-mke-aws"
root_domain      = "samkhya.cloud"
cluster_type     = "mke4"
mke4_version     = "4.2.0"
admin_password   = "your-secure-password"

node_pools = [
  { name = "manager", count = 1, roles = ["manager"], instance_type = "m6id.xlarge" },
  { name = "worker",  count = 2, roles = ["worker"],  instance_type = "m6id.large" },
  { name = "msr",     count = 2, roles = ["msr"],     instance_type = "m6id.large" },
]
```

### 3. Deploy

Full lifecycle (destroy existing, create new, install MKE):

```bash
MKE_VERSION=4.2.0 MSR_VERSION=4.13.5 YES=1 make mkestack
```

Or step-by-step:

```bash
make init
make apply
make mke4                               # installs MKE4
```

### 4. Access

- **MKE4 UI**: `https://mke4-ui.<root_domain>`
- **kubectl**: `kubectl --kubeconfig artifacts/configs/kubeconfig.yaml get pods -A`
- **Credentials**: admin / password set in `terraform.tfvars`

### 5. Deploy MSR4 (optional)

```bash
make msr4
make msr4 MSR4_HA=true    # high availability mode
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make mkestack` | Full lifecycle: destroy, init, apply, install MKE |
| `make init` | Terraform init |
| `make plan` | Show infrastructure changes |
| `make apply` | Apply infrastructure changes |
| `make destroy` | Destroy all infrastructure |
| `make mke3` | Install MKE3 via Launchpad |
| `make mke4` | Install MKE4 via mkectl |
| `make msr4` | Install MSR4 via Helm |

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_PASSWORD` | `mkepassword` | MKE admin password (env or flag) |
| `CLUSTER_TYPE` | `mke4` | `mke3` or `mke4` |
| `MKE4_VERSION` | `4.2.0` | MKE4 version |
| `MSR_VERSION` | `4.13.5` | MSR4 Helm chart version |

## Generated Files

These are created by `make apply` and should not be committed:

- `artifacts/configs/kubeconfig.yaml`
- `artifacts/configs/mke4-*.yaml`
- `artifacts/ssh/*.pem`
- `terraform.tfstate`

## Architecture

- 1 manager node (control plane)
- 2 worker nodes
- 2 MSR nodes (container registry)
- NLBs for: MKE4 UI, Ingress, MSR4
- Calico CNI with VXLAN overlay
