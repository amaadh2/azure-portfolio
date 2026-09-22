# ---------------------------------------------------------------------------
# variables.tf
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the Azure Resource Group holding the hub-and-spoke topology"
  type        = string
  default     = "rg-vnet-topology"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "uksouth"
}
