variable "cluster_name" {
  description = "Logical cluster name for tagging and resource naming."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix applied to all AWS resource names for uniqueness."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the cluster VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of AWS availability zones to deploy subnets into."
  type        = list(string)
}

variable "node_pools" {
  description = "List of node pool definitions specifying instance type, count, OS, and roles."
  type = list(object({
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
  }))
}

variable "ssh_key_prefix" {
  description = "Prefix for the SSH key pair name uploaded to AWS."
  type        = string
}

variable "ssh_key_dir" {
  description = "Local directory where the generated SSH private key is written."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to all AWS resources."
  type        = map(string)
  default     = {}
}

variable "mke4_ui_backend_port" {
  description = "Backend target port for the MKE4 UI load balancer."
  type        = number
}

variable "root_volume_size" {
  description = "Default root volume size (GB) applied via launch template block_device_mappings. Expanded on first boot via user_data growpart script."
  type        = number
  default     = 120
}

variable "profile" {
  description = "AWS CLI profile for volume resize operations."
  type        = string
  default     = null
}

variable "shared_credentials_file" {
  description = "Path to AWS shared credentials file for volume resize operations."
  type        = string
  default     = null
}
