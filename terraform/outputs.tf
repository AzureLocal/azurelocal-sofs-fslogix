output "resource_group_id" {
  description = "Resource ID of the created resource group."
  value       = azurerm_resource_group.main.id
}

output "resource_group_name" {
  description = "Name of the created resource group."
  value       = azurerm_resource_group.main.name
}

output "diag_storage_account_id" {
  description = "Resource ID of the diagnostic storage account."
  value       = azurerm_storage_account.diag.id
}

output "diag_storage_account_name" {
  description = "Name of the diagnostic storage account."
  value       = azurerm_storage_account.diag.name
}
