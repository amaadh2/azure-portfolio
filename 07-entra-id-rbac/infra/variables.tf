variable "resource_group_name" {
  description = "Name of the resource group the group's Reader access is scoped to"
  type        = string
  default     = "rg-entra-id-rbac"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "uksouth"
}
