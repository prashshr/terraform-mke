#!/usr/bin/env python3
"""write_tfvars.py — Generate terraform.tfvars from config file.

Reads a bash-sourceable 'config' file and outputs HCL terraform.tfvars.
"""
import re
import sys
import os


def _strip_inline_comment(val):
    """Remove trailing '# comment' not inside quotes."""
    in_single = False
    in_double = False
    for i, ch in enumerate(val):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == '#' and not in_single and not in_double:
            if i == 0 or val[i-1].isspace():
                return val[:i].rstrip()
    return val


def parse_config(config_path):
    """Parse bash config file into a dict. Strips surrounding quotes from values."""
    config = {}
    with open(config_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            m = re.match(r'^([A-Z_][A-Z0-9_]*)=(.*)', line)
            if m:
                key = m.group(1)
                val = m.group(2).strip()
                val = _strip_inline_comment(val)
                if len(val) >= 2 and val.startswith('"') and val.endswith('"'):
                    val = val[1:-1]
                elif len(val) >= 2 and val.startswith("'") and val.endswith("'"):
                    val = val[1:-1]
                config[key] = val
    return config


def to_tfval(val):
    """Convert a config value to HCL format."""
    if val.lower() in ('true', 'false'):
        return val.lower()
    if re.match(r'^-?\d+$', val):
        return val
    if val.lower() == 'null' or val == '':
        return 'null'
    return f'"{val}"'


def build_node_pools(pools_str):
    """Parse space-separated pool definitions into HCL list of objects."""
    if not pools_str or pools_str.strip() == '':
        return '[]'

    pools = []
    for pool_def in pools_str.split():
        parts = pool_def.split(':')
        if len(parts) < 5:
            continue
        name, roles, os_type, instance_type, count_val = parts[:5]
        private_if = parts[5] if len(parts) > 5 else None

        pool_lines = []
        pool_lines.append(f'      name          = "{name}"')
        pool_lines.append(f'      roles         = ["{roles}"]')
        pool_lines.append(f'      os            = "{os_type}"')
        pool_lines.append(f'      instance_type = "{instance_type}"')
        pool_lines.append(f'      count         = {count_val}')
        if private_if:
            pool_lines.append(f'      private_interface = "{private_if}"')

        pools.append('{\n' + '\n'.join(pool_lines) + '\n    }')

    if not pools:
        return '[]'
    return '[\n    ' + ',\n    '.join(pools) + '\n  ]'


def generate_tfvars(config):
    """Generate terraform.tfvars content from parsed config."""
    lines = []

    # Map product-prefixed keys to terraform variable names
    aliases = {
        'MKE3_MCR_VERSION': 'MCR_VERSION',
        'MKE3_APP_DOMAIN': 'APP_DOMAIN_MKE3',
        'MKE4_APP_DOMAIN': 'APP_DOMAIN_MKE4',
        'MSR2_VERSION': 'MSR_VERSION',
        'MSR2_ENABLED': 'ENABLE_MSR',
        'MSR2_APP_DOMAIN': 'APP_DOMAIN_MSR',
        'MSR4_APP_DOMAIN': 'APP_DOMAIN_MSR4',
        'KOF_APP_DOMAIN': 'APP_DOMAIN_KOF',
        'K0RDENT_UI_APP_DOMAIN': 'APP_DOMAIN_K0RDENT_UI',
    }
    for src, dst in aliases.items():
        if src in config and dst not in config:
            config[dst] = config[src]

    # Simple variables
    simple_vars = [
        'cluster_name', 'cluster_type', 'admin_username', 'admin_password',
        'mke3_version', 'mke4_version', 'msr_version', 'mcr_version',
        'mke4_ui_backend_port', 'mke4_gateway_http_node_port', 'mke4_gateway_https_node_port',
        'aws_root_volume_size', 'root_domain',
        'app_domain_mke3', 'app_domain_mke4', 'app_domain_ingress',
        'app_domain_msr', 'app_domain_msr4', 'app_domain_kof', 'app_domain_k0rdent_ui',
        'enable_msr', 'airgap_enabled', 'nfs_enabled', 'kof_enabled', 'k0rdent_ui_enabled',
    ]

    for var in simple_vars:
        key = var.upper()
        if key in config and config[key]:
            lines.append(f'{var} = {to_tfval(config[key])}')

    lines.append('')

    # AWS settings
    aws_enabled = config.get('AWS_ENABLED', 'false').lower() == 'true'
    if aws_enabled:
        aws_region = config.get('AWS_REGION', 'eu-west-1')
        aws_profile = config.get('AWS_PROFILE', '')
        aws_creds = config.get('AWS_CREDENTIALS_FILE', '')
        cluster_name = config.get('CLUSTER_NAME', 'ps-mke')
        pools_str = config.get('AWS_NODE_POOLS', '')

        # If MSR2 is enabled for MKE3 and no msr pool is explicitly in pools_str, auto-append
        msr2_on = config.get('MSR2_ENABLED', config.get('ENABLE_MSR', 'false')).lower() == 'true'
        cluster_type = config.get('CLUSTER_TYPE', 'mke4').lower()
        if msr2_on and cluster_type == 'mke3' and ':msr:' not in pools_str and ':registry:' not in pools_str:
            msr2_ha = config.get('MSR2_HA', 'false').lower() == 'true'
            msr_count = 3 if msr2_ha else 1
            os_match = re.search(r':(rhel[0-9]+|ubuntu[0-9]+|rocky[0-9]+):', pools_str)
            os_name = os_match.group(1) if os_match else 'rhel96'
            pools_str = f"{pools_str.strip()} aws-msr:msr:{os_name}:m6id.large:{msr_count}".strip()

        node_pools_hcl = build_node_pools(pools_str)

        lines.append('aws_settings = {')
        lines.append('  enabled                 = true')
        lines.append(f'  region                  = "{aws_region}"')
        if aws_profile:
            lines.append(f'  profile                 = "{aws_profile}"')
        if aws_creds:
            lines.append(f'  shared_credentials_file = "{aws_creds}"')
        lines.append(f'  resource_prefix         = "{cluster_name}"')
        lines.append(f'  cluster_name            = "{cluster_name}"')
        lines.append(f'  vpc_cidr                = "10.40.0.0/16"')
        lines.append(f'  availability_zones      = ["{aws_region}a", "{aws_region}b"]')
        lines.append(f'  ssh_key_prefix          = "{cluster_name}"')
        lines.append(f'  tags                    = {{}}')
        lines.append(f'  node_pools = {node_pools_hcl}')
        lines.append('}')
        lines.append('')

    # Hetzner settings (always emit block, even when disabled)
    hz_enabled = config.get('HETZNER_ENABLED', 'false').lower() == 'true'
    hz_creds = config.get('HETZNER_CREDENTIALS_FILE', '')
    hz_create_net = config.get('HETZNER_CREATE_NETWORK', 'true')
    hz_node_pools = build_node_pools(config.get('HETZNER_NODE_POOLS', ''))

    lines.append('hetzner_settings = {')
    lines.append(f'  enabled          = {str(hz_enabled).lower()}')
    lines.append(f'  location         = "{config.get("HETZNER_LOCATION", "fsn1")}"')
    lines.append(f'  create_network   = {hz_create_net}')
    lines.append(f'  network_cidr     = "{config.get("HETZNER_NETWORK_CIDR", "10.42.0.0/16")}"')
    lines.append(f'  subnet_cidr      = "{config.get("HETZNER_SUBNET_CIDR", "10.42.0.0/24")}"')
    lines.append(f'  network_zone     = "{config.get("HETZNER_NETWORK_ZONE", "eu-central")}"')
    lines.append(f'  cluster_name     = "{config.get("CLUSTER_NAME", "ps-mke")}"')
    lines.append(f'  ssh_key_prefix   = "{config.get("CLUSTER_NAME", "ps-mke")}"')
    if hz_creds:
        lines.append(f'  credentials_file = "{hz_creds}"')
    lines.append(f'  labels           = {{}}')
    lines.append(f'  node_pools = {hz_node_pools}')
    lines.append('}')
    lines.append('')

    # TLS blocks
    email = config.get('TLS_EMAIL', 'ops@samkhya.cloud')
    tls_subsystems = [
        ('MKE3_TLS_ENABLED', 'mke3_tls'),
        ('MKE4_TLS_ENABLED', 'mke4_tls'),
        ('INGRESS_TLS_ENABLED', 'ingress_tls'),
        ('MSR2_TLS_ENABLED', 'msr_tls'),
        ('MSR4_TLS_ENABLED', 'msr4_tls'),
    ]
    # Fallback check for legacy MSR_TLS_ENABLED
    if 'MSR2_TLS_ENABLED' not in config and 'MSR_TLS_ENABLED' in config:
        config['MSR2_TLS_ENABLED'] = config['MSR_TLS_ENABLED']

    for enabled_key, var_name in tls_subsystems:
        enabled = config.get(enabled_key, 'false').lower() == 'true'
        lines.append(f'{var_name} = {{')
        lines.append(f'  enabled  = {"true" if enabled else "false"}')
        lines.append(f'  use_acme = {"true" if enabled else "false"}')
        lines.append(f'  email    = "{email}"')
        lines.append(f'}}')
    lines.append('')

    # Cloudflare settings
    cf_enabled = config.get('CLOUDFLARE_ENABLED', 'false').lower() == 'true'
    cf_token = config.get('CLOUDFLARE_API_TOKEN', '')
    lines.append('cloudflare_settings = {')
    lines.append(f'  enabled   = {"true" if cf_enabled else "false"}')
    lines.append(f'  zone_name = "{config.get("CLOUDFLARE_ZONE_NAME", "")}"')
    lines.append(f'  api_token = {"null" if not cf_token else f"\"{cf_token}\""}')
    lines.append('}')
    lines.append('')

    return '\n'.join(lines)


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

    if len(sys.argv) > 1:
        config_file = sys.argv[1]
    else:
        config_file = 'config.env' if os.path.exists(os.path.join(repo_root, 'config.env')) else 'config'

    output_file = sys.argv[2] if len(sys.argv) > 2 else 'terraform.tfvars'

    if not os.path.isabs(config_file):
        config_file = os.path.join(repo_root, config_file)
    if not os.path.isabs(output_file):
        output_file = os.path.join(repo_root, output_file)

    if not os.path.exists(config_file):
        print(f'Error: Config file not found: {config_file}', file=sys.stderr)
        sys.exit(1)

    config = parse_config(config_file)
    tfvars = generate_tfvars(config)

    with open(output_file, 'w') as f:
        f.write(tfvars + '\n')

    print(f'Generated {output_file} from {config_file}')


if __name__ == '__main__':
    main()
