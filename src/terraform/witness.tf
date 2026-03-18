# =============================================================================
# SOFS on Azure Local — Cloud Witness Storage Account (Azure Verified Module)
# =============================================================================
# Standard_LRS, StorageV2, TLS 1.2 — used for guest cluster quorum.
# The storage account key is consumed by Configure-SOFS-Cluster.ps1 to set
# the cloud witness on the failover cluster.
# =============================================================================

module "cloud_witness" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.6"

  name                          = var.cloud_witness_name
  resource_group_name           = local.rg_name
  location                      = local.rg_location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false

  tags = var.tags
}
