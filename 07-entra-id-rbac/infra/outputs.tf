output "resource_group_name" {
  value = azurerm_resource_group.identity_demo.name
}

output "group_name" {
  value = azuread_group.portfolio_readers.display_name
}

output "group_object_id" {
  value = azuread_group.portfolio_readers.object_id
}
