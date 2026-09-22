# ---------------------------------------------------------------------------
# github-oidc.tf
# Stage 5 - GitHub Actions CI/CD, Azure side.
#
# The pipeline (defined in the rpg-map-tracker repo, not here) needs to log
# in to Azure to upload the built site. The old-fashioned way is a
# "service principal client secret" - basically a long-lived password
# stored as a GitHub Secret. The problem: it's a real credential that
# doesn't expire on its own, and if it ever leaked, whoever has it can
# authenticate as that identity indefinitely.
#
# OIDC federated identity avoids this entirely. Instead of storing a
# secret, we tell Azure AD: "trust tokens issued by GitHub Actions,
# specifically for pushes to amaadh2/rpg-map-tracker's main branch."
# GitHub's own runner then generates a short-lived, cryptographically
# signed token proving "this really is a GitHub Actions run for that exact
# repo and branch," Azure verifies it against the trust relationship below,
# and issues a short-lived access token in return. No password ever exists
# to leak.
# ---------------------------------------------------------------------------

# A "data" block reads information about something that already exists,
# rather than creating anything new. This reads details about whichever
# account is currently logged in via `az login` - specifically its tenant
# ID and subscription ID, which outputs.tf needs to hand to GitHub Secrets.
data "azurerm_client_config" "current" {}

# An "App Registration" is an identity Entra ID (Azure AD) knows about -
# think of it as registering a new named user, except the user is a piece
# of automation (the GitHub Actions pipeline) rather than a person.
resource "azuread_application" "github_actions" {
  display_name = "github-actions-dissertation-azure"
}

# The application registration alone can't be granted permissions in
# Azure - it needs an associated "Service Principal", which is the actual
# security identity that Azure RBAC role assignments attach to. Almost
# every app registration needs exactly one of these alongside it.
resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# This is the actual trust relationship described above. It tells Azure AD:
# "if a token arrives claiming to be from GitHub's OIDC issuer, for this
# specific repo and this specific branch, trust it as this application."
resource "azuread_application_federated_identity_credential" "github_actions" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-actions-main-branch"
  description    = "Allows GitHub Actions on the main branch of amaadh2/rpg-map-tracker to authenticate to Azure via OIDC, no stored secret required"

  # audiences and issuer are fixed values GitHub Actions and Azure AD both
  # expect for this integration - not project-specific, don't change these.
  audiences = ["api://AzureADTokenExchange"]
  issuer    = "https://token.actions.githubusercontent.com"

  # This is the important, project-specific part: it restricts the trust to
  # ONLY pushes to the main branch of this exact repo. A workflow run on a
  # feature branch, a pull request, or from a different repo entirely would
  # present a token with a different "subject" claim and be rejected.
  #
  # NOTE: GitHub's actual OIDC subject format includes immutable numeric IDs
  # alongside the account/repo names (repo:OWNER@ACCOUNT_ID/REPO@REPO_ID:...)
  # rather than the plain repo:OWNER/REPO:... format documented in most
  # older tutorials - confirmed directly from a real failed pipeline run's
  # error log, which shows Azure the exact subject GitHub presented. Using
  # that exact string here rather than the "clean" format.
  subject = "repo:amaadh2@200507595/rpg-map-tracker@1366801509:ref:refs/heads/main"
}

# Finally, grant the service principal permission to actually do something.
# Following the least-privilege lesson from Stage 2 (Owner ≠ automatic data
# access), this grants ONLY "Storage Blob Data Contributor" (read/write
# blobs), and ONLY scoped to this one storage account - not the whole
# resource group or subscription. If this credential ever leaked, the
# damage is capped at "can upload files to this one $web container."
resource "azurerm_role_assignment" "github_actions_storage" {
  scope                = azurerm_storage_account.dissertation.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
