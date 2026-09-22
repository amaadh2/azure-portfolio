output "resource_group_name" {
  value = azurerm_resource_group.monitoring.name
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.monitoring.name
}

output "workspace_id" {
  description = "Needed in Stage 2 to point other resources' diagnostic settings at this workspace"
  value       = azurerm_log_analytics_workspace.monitoring.id
}
