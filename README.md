# terraform-ps

Rebuilt Terraform environment for provisioning MKE hosts on AWS or Hetzner and rendering:

- `artifacts/configs/launchpad.yaml`
- `artifacts/configs/mke4.yaml`

## What is implemented

- AWS EC2 instances by node pool
- AWS NLBs for manager, MKE4 ingress, and MSR
- Hetzner servers by node pool
- Hetzner firewalls, optional private network, and LBs for manager, MKE4 ingress, and MSR
- Cloudflare A record automation for Hetzner LB targets only
- Launchpad host rendering with optional MSR section
- MKE4 config rendering with per-host `privateInterface`

## Important behavior

- `enable_msr = true` is required for the Launchpad template to render a populated `msr:` section.
- AWS MKE4 ingress uses an NLB listener on `443` forwarding to node port `33001`.
- The AWS node port `33001` security group rule is intentionally open to `0.0.0.0/0`. Internet-facing NLBs preserve client IP, so restricting the rule to VPC CIDRs breaks public ingress.
- Hetzner private networking is optional. When attached, load balancer targets use private IPs and internal firewall rules restrict to private CIDRs.

## Common commands

```bash
make init
make plan
make apply
make launchpad
make mkectl
```

## Credentials

- AWS shared credentials file: `credentials/aws-profile`
- Hetzner token file: `credentials/hetzner.token`
- Cloudflare token: `CF_API_TOKEN` environment variable or inline in `terraform.tfvars`
