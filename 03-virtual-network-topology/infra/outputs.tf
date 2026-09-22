# ---------------------------------------------------------------------------
# outputs.tf
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group holding this topology"
  value       = azurerm_resource_group.network.name
}

output "hub_vnet_name" {
  description = "Name of the hub VNet"
  value       = azurerm_virtual_network.hub.name
}

output "hub_vnet_address_space" {
  description = "Hub VNet's address space"
  value       = azurerm_virtual_network.hub.address_space
}

output "spoke_vnet_name" {
  description = "Name of the spoke VNet"
  value       = azurerm_virtual_network.spoke.name
}

output "spoke_vnet_address_space" {
  description = "Spoke VNet's address space"
  value       = azurerm_virtual_network.spoke.address_space
}
