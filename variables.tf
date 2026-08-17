variable "cluster_name" {
  description = "Logical cluster name propagated to all providers."
  type        = string
  default     = "ps-mke"
}

variable "root_domain" {
  description = "Primary DNS domain used for application hostnames."
  type        = string
  default     = "samkhya.cloud"
}

variable "app_domain_mke3" {
  description = "Hostname prefix for MKE3 services."
  type        = string
  default     = "mke3"
}

variable "app_domain_mke4" {
  description = "Hostname prefix for MKE4 API server (externalAddress)."
  type        = string
  default     = "mke4"
}

variable "app_domain_mke4_ui" {
  description = "Hostname prefix for MKE4 UI/certificates (must differ from app_domain_mke4 per MKE 4.2+ validation)."
  type        = string
  default     = "mke4-ui"
}

variable "app_domain_ingress" {
  description = "Hostname prefix for ingress services."
  type        = string
  default     = "ingress"
}

variable "app_domain_msr" {
  description = "Hostname prefix for MSR services."
  type        = string
  default     = "msr"
}

variable "app_domain_msr4" {
  description = "Hostname prefix for MSR4 services."
  type        = string
  default     = "msr4"
}

variable "admin_username" {
  description = "Username for both Launchpad and mkectl administrative users."
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Password for both Launchpad and mkectl administrative users."
  type        = string
  sensitive   = true
  default     = "mkepassword"
}

variable "enable_msr" {
  description = "Whether to render MSR settings inside Launchpad templates."
  type        = bool
  default     = false
}

variable "mke3_version" {
  description = "Launchpad (MKE 3.x) version."
  type        = string
  default     = "3.8.11"
}

variable "mke4_version" {
  description = "mkectl (MKE 4.x) version."
  type        = string
  default     = "4.2.0"
}

variable "mke4_ui_backend_port" {
  description = "Backend target port for the MKE4 UI load balancer. Ports 33000-33001 are reserved for MKE3 ingress during MKE3→MKE4 upgrades."
  type        = number
  default     = 34001
}

variable "mke4_gateway_http_node_port" {
  description = "Gateway HTTP node port passed to mkectl upgrade. Ports 33000-33001 are reserved for MKE3 ingress."
  type        = number
  default     = 34000
}

variable "mke4_gateway_https_node_port" {
  description = "Gateway HTTPS node port passed to mkectl upgrade. Ports 33000-33001 are reserved for MKE3 ingress."
  type        = number
  default     = 34001
}

variable "mke4_metallb_enabled" {
  description = "Enable MetalLB load balancer in MKE4 (spec.metallb.enabled)."
  type        = bool
  default     = false
}

variable "msr_version" {
  description = "MSR version when MSR hosts are requested."
  type        = string
  default     = "2.9.29"
}

variable "mcr_version" {
  description = "Mirantis Container Runtime version provided to Launchpad templates."
  type        = string
  default     = "25.0.13"
}

variable "artifacts_dir" {
  description = "Directory where rendered configs, keys, and metadata are stored."
  type        = string
  default     = null
}

variable "san_override" {
  description = "Optional SAN override for Launchpad install flags. Defaults to the manager LB or first manager."
  type        = string
  default     = null
}

variable "aws_root_volume_size" {
  description = "Default root volume size (GB) for AWS instances. Applied via launch template with automatic partition expansion on first boot."
  type        = number
  default     = 120
}

variable "tls_reuse_min_validity_hours" {
  description = "Minimum remaining certificate validity required before reusing an existing certificate from artifacts/tlscerts."
  type        = number
  default     = 168
}

variable "mke3_tls" {
  description = "Optional TLS certificate configuration for MKE3 direct installation."
  type = object({
    enabled            = optional(bool)
    use_acme           = optional(bool)
    common_name        = optional(string)
    email              = optional(string)
    acme_directory_url = optional(string)
    cert_pem           = optional(string)
    key_pem            = optional(string)
    ca_pem             = optional(string)
  })
  default = {}
}

variable "mke4_tls" {
  description = "Optional TLS certificate configuration for MKE4 direct installation."
  type = object({
    enabled            = optional(bool)
    use_acme           = optional(bool)
    common_name        = optional(string)
    email              = optional(string)
    acme_directory_url = optional(string)
    cert_pem           = optional(string)
    key_pem            = optional(string)
    ca_pem             = optional(string)
  })
  default = {}
}

variable "ingress_tls" {
  description = "TLS certificate configuration for ingress."
  type = object({
    enabled            = optional(bool)
    use_acme           = optional(bool)
    common_name        = optional(string)
    email              = optional(string)
    acme_directory_url = optional(string)
    cert_pem           = optional(string)
    key_pem            = optional(string)
    ca_pem             = optional(string)
  })
  default = {}
}

variable "msr_tls" {
  description = "TLS certificate configuration for MSR (v2.9)."
  type = object({
    enabled            = optional(bool)
    use_acme           = optional(bool)
    common_name        = optional(string)
    email              = optional(string)
    acme_directory_url = optional(string)
    cert_pem           = optional(string)
    key_pem            = optional(string)
    ca_pem             = optional(string)
  })
  default = {}
}

variable "msr4_tls" {
  description = "TLS certificate configuration for MSR4."
  type = object({
    enabled            = optional(bool)
    use_acme           = optional(bool)
    common_name        = optional(string)
    email              = optional(string)
    acme_directory_url = optional(string)
    cert_pem           = optional(string)
    key_pem            = optional(string)
    ca_pem             = optional(string)
  })
  default = {}
}

variable "mkectl_binary" {
  description = "mkectl binary name or path to execute after configs are rendered."
  type        = string
  default     = "mkectl"
}

variable "aws_settings" {
  description = "AWS-specific configuration map."
  type = object({
    enabled                 = optional(bool)
    region                  = optional(string)
    profile                 = optional(string)
    shared_credentials_file = optional(string)
    resource_prefix         = optional(string)
    cluster_name            = optional(string)
    vpc_cidr                = optional(string)
    availability_zones      = optional(list(string))
    ssh_key_prefix          = optional(string)
    node_pools = optional(list(object({
      name              = string
      roles             = list(string)
      os                = optional(string)
      instance_type     = optional(string)
      count             = optional(number)
      root_volume_size  = optional(number)
      subnet_index      = optional(number)
      private_interface = optional(string)
      labels            = optional(map(string))
      metadata          = optional(map(string))
    })))
    tags = optional(map(string))
  })
  default = {}
}

variable "hetzner_settings" {
  description = "Hetzner-specific configuration map."
  type = object({
    enabled        = optional(bool)
    location       = optional(string)
    network        = optional(string)
    create_network = optional(bool)
    network_cidr   = optional(string)
    subnet_cidr    = optional(string)
    network_zone   = optional(string)
    dns_source_ips = optional(list(string))
    cluster_name   = optional(string)
    ssh_key_prefix = optional(string)
    node_pools = optional(list(object({
      name              = string
      roles             = list(string)
      os                = optional(string)
      server_type       = optional(string)
      count             = optional(number)
      private_interface = optional(string)
      labels            = optional(map(string))
      metadata          = optional(map(string))
    })))
    labels           = optional(map(string))
    token            = optional(string)
    credentials_file = optional(string)
  })
  default = {}
}

variable "cloudflare_settings" {
  description = "Cloudflare DNS settings used for managed DNS records."
  type = object({
    enabled             = optional(bool)
    zone_id             = optional(string)
    zone_name           = optional(string)
    record_name         = optional(string)
    record_name_manager = optional(string)
    record_name_ingress = optional(string)
    record_name_mke4    = optional(string)
    record_name_mke4_ui = optional(string)
    api_token           = optional(string)
  })
  default = {}
}

variable "cloudflare_records" {
  description = "Additional Cloudflare records to create in the configured zone."
  type = list(object({
    name    = string
    type    = string
    content = string
    proxied = optional(bool, false)
  }))
  default = []
}

variable "azure_settings" {
  description = "Reserved for future Azure implementation."
  type = object({
    enabled            = optional(bool)
    location           = optional(string)
    subscription_id    = optional(string)
    tenant_id          = optional(string)
    client_id          = optional(string)
    client_secret      = optional(string)
    environment        = optional(string)
    credentials_file   = optional(string)
    resource_group     = optional(string)
    vnet_cidr          = optional(string)
    subnet_cidr        = optional(string)
    ssh_key_prefix     = optional(string)
    node_pools         = optional(list(any))
    availability_zones = optional(list(string))
    tags               = optional(map(string))
  })
  default = {}
}

variable "vsphere_settings" {
  description = "Reserved for future vSphere implementation."
  type = object({
    enabled        = optional(bool)
    server         = optional(string)
    user           = optional(string)
    password       = optional(string)
    password_file  = optional(string)
    datacenter     = optional(string)
    datastore      = optional(string)
    cluster        = optional(string)
    network        = optional(string)
    folder         = optional(string)
    ssh_key_prefix = optional(string)
    template_map   = optional(map(string))
    node_pools     = optional(list(any))
  })
  default = {}
}
