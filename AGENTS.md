# AGENTS.md — AI Context for terraform-ps

## Project Overview

Terraform module for deploying MKE (Mirantis Kubernetes Engine) clusters on AWS and Hetzner, supporting MKE3 (Launchpad) and MKE4 (mkectl), with optional MSR (Secure Registry) and MSR4.

**Repository:** `terraform-ps`  
**Location:** `/arbeit/dev/terraform-ps`  
**Maintainer:** ops@samkhya.cloud

---

## Architecture

```
terraform-ps/
├── main.tf                    # TLS, module calls, templates, Cloudflare DNS (1,001 lines)
├── locals.tf                  # Provider defaults, domains, host aggregation (233 lines)
├── variables.tf               # All input variables (360 lines)
├── outputs.tf                 # Terraform outputs (49 lines)
├── providers.tf               # AWS, Hetzner, Cloudflare, TLS, ACME providers (43 lines)
├── versions.tf                # Terraform and provider version constraints (38 lines)
├── checks.tf                  # Pre-apply validation checks (55 lines)
├── Makefile                   # All build targets (228 lines)
├── templates/
│   ├── launchpad.yaml.tmpl    # MKE3 Launchpad config
│   ├── mke4-v4.1.yaml.tmpl   # MKE4 v4.1.x config (ingressController)
│   ├── mke4-v4.2.yaml.tmpl   # MKE4 v4.2.x config (gatewayMKEIngress + metallb)
│   └── hosts.yaml.tmpl        # mkectl hosts file
├── modules/providers/aws/     # AWS: VPC, subnets, SGs, instances, NLBs (877 lines)
├── modules/providers/hetzner/ # Hetzner: servers, network, firewall, LBs (464 lines)
├── scripts/
│   ├── tls_cert_status.sh     # Check existing TLS cert validity
│   └── write_tls_cert.sh      # Write TLS cert files to disk
├── artifacts/
│   ├── scripts/
│   │   ├── mkestack.sh        # Full lifecycle: destroy → init → apply → install
│   │   ├── mkeupgrade.sh      # Upgrade orchestration (MKE3→MKE4, minor, MSR)
│   │   ├── install_msr4.sh    # MSR4 Helm install with NFS setup
│   │   ├── nfs_setup.sh       # NFS client package installation
│   │   ├── generate_msr_values.sh  # Generate MSR4 Helm values
│   │   └── download_mkectl.sh # Download mkectl binary
│   ├── msr4/values/           # MSR4 Helm values files
│   ├── mke-license/           # MKE4 license token (nfr.lic)
│   ├── ssh/                   # SSH keys (gitignored)
│   ├── configs/               # Rendered configs (gitignored)
│   └── tlscerts/              # TLS certificates (gitignored)
├── terraform.tfvars           # Current variable values (gitignored but committed)
├── terraform.tfstate          # State file (gitignored but committed)
└── logs/                      # Build logs (gitignored)
```

---

## Critical Constraints

### CRITICAL: All Existing Working Functionality Must Be Preserved

This project supports multiple providers and cluster types. Every change must preserve:

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-provider (AWS + Hetzner) | MUST PRESERVE | `module.aws` and `module.hetzner` |
| MKE3 deployment | MUST PRESERVE | `launchpad.yaml.tmpl` + `launchpad apply` |
| MKE4 v4.1 deployment | MUST PRESERVE | `mke4-v4.1.yaml.tmpl` + mkectl |
| MKE4 v4.2 deployment | MUST PRESERVE | `mke4-v4.2.yaml.tmpl` + mkectl |
| MSR4 single + HA | MUST PRESERVE | `install_msr4.sh` + Helm values |
| TLS (ACME / cert-manager / self-signed) | MUST PRESERVE | 5 TLS subsystems in main.tf |
| Cloudflare DNS | MUST PRESERVE | `cloudflare_record.*` resources |
| NFS | MUST PRESERVE | NFS setup script |
| SSH keys | MUST PRESERVE | Generated per provider |
| Kubeconfig | MUST PRESERVE | MKE3: SSH from manager; MKE4: `~/.mke/mke.kubeconf` |
| Upgrade orchestration | MUST PRESERVE | `mkeupgrade.sh` |
| Security groups | MUST PRESERVE | Per provider module |
| Load balancers | MUST PRESERVE | 5 NLBs per provider |
| AMI lookup | MUST PRESERVE | `data.aws_ami` in AWS module |
| Root volume resize | MUST PRESERVE | Launch template user_data |
| License injection | MUST PRESERVE | `mke4_license_token` in locals.tf → templates |

**DO NOT** change resource addresses (e.g., `tls_private_key.mke3_acme_account`) without importing existing state.

---

## Key Configuration Details

### Cluster Type
- `cluster_type` variable: `"mke3"` or `"mke4"` (default: `"mke4"`)
- Controls `render_mke3` / `render_mke4` locals
- `mkestack.sh` reads from `terraform.tfvars`

### MKE4 Version-Specific Templates
- v4.1: `ingressController.enabled: true`, nginx-based
- v4.2: `spec.metallb.enabled`, `spec.gatewayMKEIngress`, `spec.envoyGateway`
- Template selected via `mke4_version_major_minor` in locals.tf

### Node Ports
- `mke4_gateway_http_node_port`: 34000
- `mke4_gateway_https_node_port`: 34001
- MSR4: 34002 (HTTP), 34003 (HTTPS), 34004 (metrics)

### External Address
- `externalAddress` must be a domain name (no port)
- SANs must include DNS names
- Managed via `mkectl_sans` in locals.tf

### Security Group Ports
- 4789/UDP (Calico VXLAN)
- 179/tcp (Calico BGP)
- 5473/tcp (Calico Typha)
- 9443/tcp (k0s API)
- 10250/tcp (kubelet)
- 80/tcp, 34000/tcp (Ingress)

### Network CIDRs
- `pod_cidr`: `10.42.0.0/16`
- `service_cidr`: `10.97.0.0/16`
- AWS VPC: `10.40.0.0/16`

### Kubeconfig Paths
- MKE4: `~/.mke/mke.kubeconf` (written by `mkectl apply`)
- MKE3: SSH to manager, `sudo cat /var/lib/k0s/pki/admin.conf`
- Copied to: `artifacts/configs/kubeconfig.yaml`

### License
- File: `artifacts/mke-license/nfr.lic`
- Injected via: `mke4_license_token` local in locals.tf
- Used in: `mkectl_context` → both v4.1 and v4.2 templates

---

## Development Workflow

### Making Changes

1. **Read this file first** — understand what must not break
2. **Check git status** — never commit secrets or state files
3. **Run `terraform validate`** — after any .tf changes
4. **Run `terraform plan`** — verify no unexpected destruction
5. **Test incrementally** — use `make plan` before `make apply`

### File Sizes (Target: <200 lines/file)
- `main.tf`: Currently 1,001 lines — needs splitting
- `locals.tf`: 233 lines — OK
- `variables.tf`: 360 lines — acceptable for now
- `outputs.tf`: 49 lines — OK

### Common Commands
```bash
make help              # Show all targets
make init              # terraform init
make plan              # terraform plan
make apply             # terraform apply
make destroy           # terraform destroy (removes ACME certs first)
make mkestack          # Full lifecycle (interactive)
make mke3 CLUSTER_TYPE=mke3   # Install MKE3
make mke4 CLUSTER_TYPE=mke4   # Install MKE4
make msr4              # Install MSR4
make upgrade           # Upgrade MKE/MSR versions
make msr4-cleanup      # Remove MSR4
```

### Testing New Features
```bash
# Plan only (no changes)
make plan

# Full build with minimal resources
YES=1 make mkestack CLUSTER_TYPE=mke4

# MKE3 build
YES=1 make mkestack CLUSTER_TYPE=mke3

# With logging
YES=1 LOG=1 make mkestack
```

---

## Known Gotchas

1. **`terraform -chdir` requires `=` sign** — `-chdir PATH` (space) silently fails
2. **MKE4 password via env** — `ADMIN_PASSWORD` env var (default: `mkepassword`)
3. **Node ports default to 34000/34001** — not 33000/33001
4. **MSR4 chart versions are 4.13.x** — NOT 4.2.0 (that's MKE4 version)
5. **Manager instance type must be `m6id.xlarge`** — fixes NFD GC scheduling failure
6. **`terraform.tfvars` is gitignored but committed** — needs `git rm --cached`
7. **SSH key path**: `artifacts/ssh/ps-mke-aws.pem`
8. **MCR version**: Default `25.0.13`
9. **NFS pre-install**: Required on ALL worker nodes before MSR4 install

---

## Provider-Specific Notes

### AWS
- Uses `437775732836_IAM_config_access` profile
- Credentials: `credentials/aws-profile` (gitignored)
- AMI lookup: `data.aws_ami` in AWS module
- Root volume: 120 GB with auto-resize on first boot

### Hetzner
- Token: `HCLOUD_TOKEN` env or `credentials/hetzner.token`
- Network: `10.42.0.0/16` CIDR
- Server types: `cx23` for all roles

### Cloudflare
- Zone: `samkhya.cloud`
- Token: `CF_API_TOKEN` or `CLOUDFLARE_API_TOKEN` env
- API token in `cloudflare_settings.api_token` (null = use env)

---

## Version History

- Current MKE4: `4.2.0`
- Current MKE3: `3.8.11`
- Current MSR4: `4.13.5`
- Current MCR: `25.0.13`

---

## Refactoring Plan

### Phase 0: Cleanup
- Remove stray files: `:q!`, `nohup.out`, `mke-config.toml`
- Clean `.gitignore`
- Create AGENTS.md (this file)

### Phase 1: Structural Refactoring
- Split `main.tf` into `tls.tf`, `dns.tf`, `templates.tf`
- Extract TLS pattern with `for_each`

### Phase 2: Config File
- Single bash `config` file
- `write_tfvars.py` to generate `terraform.tfvars`
- Update all scripts to use `config_parser.sh`

### Phase 3: Airgap + SSH Tunnels
- Bastion host with registry, DNS, proxy
- SSH tunnel system for remote access
- Private subnet configuration

### Phase 4: NFS + KOF + k0rdent-ui
- Dedicated NFS EC2 instance
- KOF Helm (MKE4 only, lean/full profiles)
- k0rdent-ui Helm (MKE4 only)

### Phase 5: Auto-Expiry
- EventBridge Scheduler + Lambda reaper
- Terraform output warnings

### Phase 6: Better Tagging
- Cluster, ManagedBy, Owner, Role, Environment, Expiry

### Phase 7: Deploy Phase Timing
- `phase_start()`/`phase_end()` in mkestack.sh

### Phase 8: AWS Env Var Credentials
- Fallback to `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`

### Phase 9: Documentation
- Expand README to ~400 lines
- AGENTS.md (this file)

---

## Testing Matrix

| Scenario | Provider | Cluster Type | TLS | MSR4 | Nodes |
|----------|----------|-------------|-----|------|-------|
| MKE4 online | AWS | mke4 v4.2 | ACME | Yes | 1mgr + 1wrk |
| MKE3 online | AWS | mke3 | ACME | No | 1mgr + 1wrk |
| MKE4 + MSR4 | AWS | mke4 v4.2 | ACME | Yes | 1mgr + 1wrk |
| MKE4 airgap | AWS | mke4 v4.2 | self-signed | No | 1mgr + 1wrk + bastion |

---

## Emergency Procedures

### Destroy Everything
```bash
make destroy
# or
terraform destroy -auto-approve
```

### Clean State
```bash
terraform state list | rg '^acme_certificate\.' | xargs -r terraform state rm
terraform destroy
```

### Fix Stale Kubeconfig
```bash
# MKE4
cp ~/.mke/mke.kubeconf artifacts/configs/kubeconfig.yaml
# MKE3
ssh -i artifacts/ssh/ps-mke-aws.pem ec2-user@<manager_ip> \
    "sudo cat /var/lib/k0s/pki/admin.conf" > artifacts/configs/kubeconfig.yaml
```
