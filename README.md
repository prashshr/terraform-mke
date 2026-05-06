# terraform-ps

Terraform for provisioning MKE infrastructure on AWS or Hetzner and generating the config files used for:

- MKE3 deployment via Launchpad
- MKE4 deployment via `mkectl`
- MKE3 -> MKE4 upgrade via `mkectl upgrade`

## Start here

Normal workflow:

```bash
make init
make plan
make apply
make mke3
make mke3-upgrade-prereq
make mkectl-upgrade
make mkectl
make destroy
```

What these do:

- `make init`
  - initializes Terraform
  - regenerates `artifacts/configs/hosts.yaml` from existing state if present
- `make plan`
  - shows infra changes
- `make apply`
  - applies infra changes
  - renders config artifacts
- `make mke3`
  - Install MKE3 using `artifacts/config/launchpad.yaml`
- `make mke3-upgrade-prereq`
  - updates MKE3 config so `calico_kdd = true`
- `make mkectl-upgrade`
  - upgrades MKE3 to MKE4
- `make mkectl`
  - Install MKE using `artifacts/config/mke4.yaml`
- `make destroy`
  - destroys terraform managed infrastructure resources

## What it creates

Infrastructure:
- nodes for `manager`, `worker`, and optional `msr`
- load balancers
- SSH keys under `artifacts/ssh`

Config files:
- `artifacts/configs/launchpad.yaml`
- `artifacts/configs/mke4.yaml`
- `artifacts/configs/hosts.yaml`
- `artifacts/configs/mkectl-upgrade.env`

## Load balancer layout

Current layout is split by purpose:

- MKE3 UI
  - `443 -> 443`
- Ingress
  - `443 -> 33001`
- Kubernetes API
  - `6443 -> 6443`
- MKE4 UI
  - `443 -> 34001` by default
- MSR
  - `443 -> 443` when MSR nodes are enabled

`mke4_ui_backend_port` is configurable in `terraform.tfvars`.

## Main files

- `terraform.tfvars`
  - cluster name, versions, node pools, provider settings
- `main.tf`
  - shared orchestration and rendered artifacts
- `modules/providers/aws`
  - AWS infrastructure
- `modules/providers/hetzner`
  - Hetzner infrastructure
- `templates/launchpad.yaml.tmpl`
  - MKE3 config template
- `templates/mke4.yaml.tmpl`
  - MKE4 config template
- `scripts/mke3_upgrade_prereq.sh`
  - sets `calico_kdd = true` on the running MKE3 cluster before upgrade

## Required local files

- AWS credentials:
  - `credentials/aws-profile`
- Hetzner token:
  - `credentials/hetzner.token`

Keep these local. Do not commit credentials, state, SSH keys, or rendered artifacts.


## Important values in `terraform.tfvars`

Top-level:

```hcl
admin_username               = "admin"
admin_password               = "mkepassword"
mke3_version                 = "3.8.7"
mke4_version                 = "4.1.5"
mke4_ui_backend_port         = 34001
mke4_gateway_http_node_port  = 34000
mke4_gateway_https_node_port = 34001
enable_msr                   = true
```

Notes:
- `admin_password` is used for both rendered MKE3 and MKE4 configs
- `mke4_ui_backend_port` controls the MKE4 UI LB backend port
- `enable_msr = true` is required if you want a populated MSR section in `launchpad.yaml`

## Generated upgrade env file

`artifacts/configs/mkectl-upgrade.env` is generated from Terraform values and contains:

- `MKCTL_UPGRADE_HOSTS_PATH`
- `MKCTL_UPGRADE_ADMIN_USERNAME`
- `MKCTL_UPGRADE_ADMIN_PASSWORD`
- `MKCTL_MKE3_EXTERNAL_ADDRESS`
- `MKCTL_UPGRADE_EXTERNAL_ADDRESS`
- `MKCTL_UPGRADE_GATEWAY_HTTP_NODE_PORT`
- `MKCTL_UPGRADE_GATEWAY_HTTPS_NODE_PORT`

`make mkectl-upgrade` reads this file automatically.

## Destroy

```bash
make destroy
```

If Cloudflare is enabled and managed records use `prevent_destroy`, Terraform may refuse to remove them automatically.
