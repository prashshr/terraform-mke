# terraform-mke

Terraform stack for provisioning Mirantis Kubernetes Engine infrastructure on AWS or Hetzner and rendering the deployment inputs consumed by Launchpad and `mkectl`.

Generated outputs:

- `artifacts/configs/launchpad.yaml`
- `artifacts/configs/mke4.yaml`

## Features

- Provision AWS EC2 node pools for managers, workers, and optional MSR/registry nodes
- Provision AWS network load balancers for manager access, MKE ingress, and optional MSR
- Provision Hetzner servers, firewalls, optional private networking, and load balancers
- Optionally manage Cloudflare A records for Hetzner load balancer endpoints
- Render Launchpad inventory and MKE4 configuration from the same Terraform inputs
- Export host metadata, SSH key paths, and rendered config locations as Terraform outputs

## Repository layout

- `main.tf`, `variables.tf`, `locals.tf`: shared orchestration, input schema, and normalization
- `modules/providers/aws`: AWS infrastructure module
- `modules/providers/hetzner`: Hetzner infrastructure module
- `templates/launchpad.yaml.tmpl`: Launchpad inventory template
- `templates/mke4.yaml.tmpl`: MKE4 cluster configuration template
- `scripts/`: helper scripts for node preparation and maintenance tasks

## Important behavior

- `enable_msr = true` is required for the Launchpad template to render a populated `msr:` section.
- AWS MKE ingress uses an NLB listener on `443` forwarding to node port `33001`.
- The AWS node port `33001` security group rule is intentionally open to `0.0.0.0/0`. Internet-facing NLBs preserve client IP, so restricting the rule to VPC CIDRs breaks public ingress.
- Hetzner private networking is optional. When attached, load balancer targets use private IPs and internal firewall rules restrict traffic to private CIDRs.
- SSH keys, rendered artifacts, state files, and local credential files are intentionally ignored by Git and should remain local only.

## Common workflow

```bash
make init
make plan
make apply
make launchpad
make mkectl
make destroy
```

`make destroy` runs `terraform destroy`. If `cloudflare_settings` is enabled, Terraform can still refuse to delete the managed A record because the Cloudflare resource uses `prevent_destroy = true`.

## Credentials

Keep credentials outside the repository history. Expected local inputs are:

- AWS shared credentials file: `credentials/aws-profile`
- Hetzner token file: `credentials/hetzner.token`
- Cloudflare token: `CF_API_TOKEN` environment variable or `cloudflare_settings.api_token`

## Publishing note

This repository is intended to be public. Do not commit `terraform.tfvars`, Terraform state, generated SSH keys, rendered artifacts, or provider credential files.
