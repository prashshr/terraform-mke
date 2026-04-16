variable "cluster_name" {
  description = "Logical cluster name propagated to all providers."
  type        = string
  default     = "ps-mke"
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
}

variable "enable_msr" {
  description = "Whether to render MSR settings inside Launchpad templates."
  type        = bool
  default     = false
}

variable "mke3_version" {
  description = "Launchpad (MKE 3.x) version."
  type        = string
  default     = "3.8.7"
}

variable "mke4_version" {
  description = "mkectl (MKE 4.x) version."
  type        = string
  default     = "4.1.2"
}

variable "msr_version" {
  description = "MSR version when MSR hosts are requested."
  type        = string
  default     = "2.9.3"
}

variable "mcr_version" {
  description = "Mirantis Container Runtime version provided to Launchpad templates."
  type        = string
  default     = "23.0.13"
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
    node_pools              = optional(list(any))
    tags                    = optional(map(string))
  })
  default = {}
}

variable "hetzner_settings" {
  description = "Hetzner-specific configuration map."
  type = object({
    enabled          = optional(bool)
    location         = optional(string)
    network          = optional(string)
    create_network   = optional(bool)
    network_cidr     = optional(string)
    subnet_cidr      = optional(string)
    network_zone     = optional(string)
    dns_source_ips   = optional(list(string))
    cluster_name     = optional(string)
    ssh_key_prefix   = optional(string)
    node_pools       = optional(list(any))
    labels           = optional(map(string))
    token            = optional(string)
    credentials_file = optional(string)
  })
  default = {}
}

variable "cloudflare_settings" {
  description = "Cloudflare DNS settings for the Hetzner manager/MKE4 LB."
  type = object({
    enabled     = optional(bool)
    zone_id     = optional(string)
    record_name = optional(string)
    api_token   = optional(string)
  })
  default = {}
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
