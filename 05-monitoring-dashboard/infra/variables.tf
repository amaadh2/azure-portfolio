variable "resource_group_name" {
  description = "Name of the resource group for the monitoring setup"
  type        = string
  default     = "rg-monitoring"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "uksouth"
}

variable "workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-monitoring-dashboard"
}

variable "alert_email" {
  description = "Email address to notify when the failed-operations alert fires. No default deliberately - pass this via a .tfvars file (gitignored) or -var flag, not hardcoded into committed code."
  type        = string
}
