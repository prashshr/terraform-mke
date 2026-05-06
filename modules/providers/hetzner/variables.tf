variable "cluster_name" {
  type = string
}

variable "location" {
  type = string
}

variable "node_pools" {
  type = list(any)
}

variable "ssh_key_prefix" {
  type = string
}

variable "ssh_key_dir" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "network" {
  type    = string
  default = null
}

variable "create_network" {
  type    = bool
  default = false
}

variable "network_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "network_zone" {
  type = string
}

variable "dns_source_ips" {
  type    = list(string)
  default = []
}

variable "mke4_ui_backend_port" {
  type = number
}
