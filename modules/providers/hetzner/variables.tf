variable "cluster_name" {
  description = "Logical cluster name for tagging and resource naming."
  type        = string
}

variable "location" {
  description = "Hetzner datacenter location (e.g. fsn1, hel1, nbg1)."
  type        = string
}

variable "node_pools" {
  description = "List of node pool definitions specifying server type, count, OS, and roles."
  type = list(object({
    name              = string
    roles             = list(string)
    os                = optional(string)
    server_type       = optional(string)
    count             = optional(number)
    private_interface = optional(string)
    labels            = optional(map(string))
    metadata          = optional(map(string))
  }))
}

variable "ssh_key_prefix" {
  description = "Prefix for the SSH key pair name uploaded to Hetzner."
  type        = string
}

variable "ssh_key_dir" {
  description = "Local directory where the generated SSH private key is written."
  type        = string
}

variable "labels" {
  description = "Additional labels applied to all Hetzner resources."
  type        = map(string)
  default     = {}
}

variable "network" {
  description = "ID of an existing Hetzner network to attach servers to."
  type        = string
  default     = null
}

variable "create_network" {
  description = "Whether to create a new Hetzner network for the cluster."
  type        = bool
  default     = false
}

variable "network_cidr" {
  description = "CIDR block for the Hetzner network."
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block for the Hetzner network subnet."
  type        = string
}

variable "network_zone" {
  description = "Hetzner network zone (e.g. eu-central, us-east)."
  type        = string
}

variable "dns_source_ips" {
  description = "Source IPs allowed to query DNS on the cluster firewall (used only when no private network is attached)."
  type        = list(string)
  default     = []
}

variable "mke4_ui_backend_port" {
  description = "Backend target port for the MKE4 UI load balancer."
  type        = number
}
