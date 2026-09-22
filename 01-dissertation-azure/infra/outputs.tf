# ---------------------------------------------------------------------------
# outputs.tf
# Values Terraform prints after `apply`, and that other tools (like the
# GitHub Actions pipeline in a later stage) can read back out.
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group created for this project"
  value       = azurerm_resource_group.dissertation.name
}

output "storage_account_name" {
  description = "Name of the storage account - needed later to upload the build and to reference it from GitHub Actions"
  value       = azurerm_storage_account.dissertation.name
}

output "static_website_url" {
  description = "The storage account's own URL - kept as a fallback / for debugging origin issues directly"
  value       = azurerm_storage_account.dissertation.primary_web_endpoint
}

# Disabled alongside the CDN resources in main.tf - see the explanation
# there for why the CDN layer was skipped (Front Door's cost model doesn't
# fit a personal-budget project; classic CDN can no longer be created).
# output "cdn_endpoint_url" {
#   description = "The CDN-fronted URL - this is the one to actually share/use as the live demo link"
#   value       = "https://${azurerm_cdn_frontdoor_endpoint.dissertation.fqdn}"
# }

# The three values GitHub Actions needs as repository secrets to log in via
# OIDC (see github-oidc.tf). None of these are secret in the traditional
# sense - they're IDs, not passwords - but GitHub Secrets is still the
# right place for them so they're not hardcoded into a public workflow file.
output "github_actions_client_id" {
  description = "AZURE_CLIENT_ID GitHub secret value - identifies the app registration to Azure"
  value       = azuread_application.github_actions.client_id
}

output "github_actions_tenant_id" {
  description = "AZURE_TENANT_ID GitHub secret value - identifies which Entra ID directory the app registration lives in"
  value       = data.azurerm_client_config.current.tenant_id
}

output "github_actions_subscription_id" {
  description = "AZURE_SUBSCRIPTION_ID GitHub secret value - which subscription the pipeline is allowed to act in"
  value       = data.azurerm_client_config.current.subscription_id
}
