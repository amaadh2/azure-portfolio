# ---------------------------------------------------------------------------
# main.tf
# Project 6: Azure Key Vault Integration
# Stage 1 - Key Vault + a secret stored in it, plus giving yourself
#           permission to actually read that secret back out.
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

# Needed for tenant_id (Key Vault requires it) and object_id (so the role
# assignment below can target whichever account is actually running this).
data "azurerm_client_config" "current" {}

resource "random_string" "vault_suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "keyvault" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "key-vault-integration"
  }
}

resource "azurerm_key_vault" "main" {
  name                = "kv-${random_string.vault_suffix.result}"
  resource_group_name = azurerm_resource_group.keyvault.name
  location            = azurerm_resource_group.keyvault.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Modern access-control model - permissions on secrets/keys/certificates
  # are granted through normal Azure RBAC role assignments (see below),
  # same as any other resource. The older model ("access policies") is
  # vault-specific and doesn't fit the same permission system as everything
  # else in this portfolio.
  enable_rbac_authorization = true

  # Purge protection stops a vault (and everything in it) from being
  # permanently deleted for a mandatory retention window, even if you want
  # to. Given how often infrastructure has been destroyed and recreated
  # throughout this whole portfolio, leaving this off is deliberate - a
  # real production vault holding real secrets would likely want this on,
  # but it would actively get in the way of a portfolio project you expect
  # to tear down and rebuild.
  purge_protection_enabled = false

  tags = {
    project = "key-vault-integration"
  }
}

# Key Vault's own RBAC roles are separate from general Azure roles like
# "Storage Blob Data Contributor" from Project 1 - this one specifically
# grants permission to read (and manage) secrets in vaults, nothing else.
resource "azurerm_role_assignment" "self_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The secret itself. In a real scenario this would be something like a
# database connection string or an API key - here it's just a placeholder
# value to prove the whole read/write path actually works end to end.
resource "azurerm_key_vault_secret" "example" {
  name         = "example-secret"
  value        = var.secret_value
  key_vault_id = azurerm_key_vault.main.id

  # Without this, Terraform would try to create the secret before the role
  # assignment above has actually finished propagating, and fail with a
  # permissions error - this forces the role assignment to complete first.
  depends_on = [azurerm_role_assignment.self_secrets_officer]
}
