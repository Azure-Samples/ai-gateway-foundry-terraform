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

variable "foundry_disable_local_auth" {
  type        = bool
  description = "Set to true to turn off key-based sign-in on the Foundry account so that all callers must use Microsoft Entra ID"
  default     = false
  nullable    = false
}
