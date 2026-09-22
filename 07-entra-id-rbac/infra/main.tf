# ---------------------------------------------------------------------------
# main.tf
# Project 7: Entra ID and RBAC Setup
# Stage 1 - An Entra ID group, with an Azure RBAC role assigned to the
#           GROUP rather than to an individual user. This is the real best
#           practice: manage who's in the group, not a growing list of
#           one-off per-person role assignments scattered across resources.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "identity_demo" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "entra-id-rbac"
  }
}

# The group itself. In a real organisation this might be "cloud-readers" or
# "network-team", something reflecting an actual job function - membership
# changes (people joining/leaving) rather than the role assignment itself
# needing to change every time.
resource "azuread_group" "portfolio_readers" {
  display_name     = "portfolio-readers"
  security_enabled = true

  # Adding the current account as the only member for now - in a real team
  # this is where you'd add multiple people's object IDs.
  owners = [data.azurerm_client_config.current.object_id]
}

# Membership is managed as a SEPARATE resource from the group itself - this
# mirrors how it actually works in Entra ID, the group can exist with zero
# members, and membership changes independently of the group's own settings.
resource "azuread_group_member" "self" {
  group_object_id  = azuread_group.portfolio_readers.object_id
  member_object_id = data.azurerm_client_config.current.object_id
}

# The actual RBAC grant - "Reader" (read-only, can view but not change
# anything) assigned to the GROUP, scoped to just this one resource group.
# Anyone added to the group in future automatically inherits this access,
# without a new role assignment needing to be created for each person.
resource "azurerm_role_assignment" "readers_group" {
  scope                = azurerm_resource_group.identity_demo.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.portfolio_readers.object_id
}
