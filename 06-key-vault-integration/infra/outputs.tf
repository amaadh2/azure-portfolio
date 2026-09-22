output "resource_group_name" {
  value = azurerm_resource_group.keyvault.name
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "secret_name" {
  value = azurerm_key_vault_secret.example.name
}
