# =============================================================================
# SOFS on Azure Local — Cloud Witness Storage Account
# =============================================================================
# Standard_LRS, StorageV2, TLS 1.2 — used for guest cluster quorum.
# The storage account key is consumed by Configure-SOFS-Cluster.ps1 to set
# the cloud witness on the failover cluster.
# =============================================================================

resource "azurerm_storage_account" "cloud_witness" {
  name                     = var.cloud_witness_name
  resource_group_name      = azurerm_resource_group.sofs.name
  location                 = azurerm_resource_group.sofs.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false

  tags = var.tags
}
