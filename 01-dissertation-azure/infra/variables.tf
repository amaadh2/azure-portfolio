# ---------------------------------------------------------------------------
# variables.tf
# Input variables for Project 1's Terraform config. Keeping these separate
# from main.tf makes it obvious at a glance what's configurable vs fixed.
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the Azure Resource Group that will hold all Project 1 resources"
  type        = string
  default     = "rg-dissertation-azure"
}

variable "location" {
  description = "Azure region to deploy into. uksouth is the primary UK region with the widest service availability"
  type        = string
  default     = "uksouth"
}
