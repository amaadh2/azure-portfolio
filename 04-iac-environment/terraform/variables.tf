variable "resource_group_name" {
  description = "Name of the resource group for the Terraform side of this comparison"
  type        = string
  default     = "rg-iac-terraform"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "uksouth"
}
