variable "resource_group_name" {
  description = "Name of the resource group for the Key Vault"
  type        = string
  default     = "rg-keyvault"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "uksouth"
}

variable "secret_value" {
  description = "The example secret's value - passed via terraform.tfvars (gitignored), not hardcoded, same reasoning as Project 5's alert email"
  type        = string
  sensitive   = true
}
