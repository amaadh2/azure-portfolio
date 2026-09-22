# ---------------------------------------------------------------------------
# main.tf
# Project 4: Bicep and Terraform IaC Environment
# Terraform implementation - deliberately the same infrastructure as the
# Bicep version in ../bicep/, so the two can be compared directly.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "iac_demo" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "iac-environment"
    tool    = "terraform"
  }
}

resource "azurerm_storage_account" "iac_demo" {
  name                     = "stiacterr${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.iac_demo.name
  location                 = azurerm_resource_group.iac_demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    project = "iac-environment"
    tool    = "terraform"
  }
}

# A plain blob container (not static website hosting - that's Project 1's
# job) just to demonstrate a nested resource, since a bare storage account
# on its own doesn't show much about how each tool handles dependencies
# between resources.
resource "azurerm_storage_container" "iac_demo" {
  name                  = "demo-data"
  storage_account_name  = azurerm_storage_account.iac_demo.name
  container_access_type = "private"
}
