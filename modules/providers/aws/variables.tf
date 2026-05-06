variable "cluster_name" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
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

variable "tags" {
  type    = map(string)
  default = {}
}

variable "mke4_ui_backend_port" {
  type = number
}
