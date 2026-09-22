output "resource_group_name" {
  value = azurerm_resource_group.iac_demo.name
}

output "storage_account_name" {
  value = azurerm_storage_account.iac_demo.name
}
