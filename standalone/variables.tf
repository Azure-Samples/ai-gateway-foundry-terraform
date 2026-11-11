variable "domain" {
  description = "Azure deployment domain"
  type        = string
  default     = "ai"
}

variable "workload" {
  description = "Azure deployment workload"
  type        = string
  default     = "gw"
}

variable "environment" {
  description = "The environment deployed"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("(dev|stg|pro)", var.environment))
    error_message = "The environment value must be a valid."
  }
}

variable "location" {
  description = "Azure deployment location"
  type        = string
  default     = "swedencentral"
}

variable "region" {
  description = "Azure deployment region"
  type        = string
  default     = "swc"
}

variable "tags" {
  type        = map(any)
  description = "The custom tags for all resources"
  default     = {}
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group"
  default     = ""
}

variable "gateway_allowed_ip_ranges" {
  type        = list(string)
  description = "Optional gateway-wide allow list of caller IP ranges in CIDR notation, for all models and MCP tool servers. null (default) leaves the gateway policies unmanaged; [] removes the allow list that Terraform wrote earlier."
  default     = null
  validation {
    condition = var.gateway_allowed_ip_ranges == null ? true : alltrue([
      for entry in var.gateway_allowed_ip_ranges :
      can(cidrhost(entry, 0)) && try(tonumber(split("/", entry)[1]) > 0, false)
    ])
    error_message = "Each gateway_allowed_ip_ranges entry must be an IPv4 or IPv6 range in CIDR notation with a prefix length above zero. For a single address, use prefix length 32 (IPv4) or 128 (IPv6)."
  }
  validation {
    condition = var.gateway_allowed_ip_ranges == null ? true : alltrue([
      for entry in var.gateway_allowed_ip_ranges : !can(regex("(^|[.:])0[0-9]+[.]|[.]0[0-9]+/|/0[0-9]", entry))
    ])
    error_message = "gateway_allowed_ip_ranges entries must not use leading zeros in IPv4 parts or in the prefix length, because other tools may read them differently."
  }
}
