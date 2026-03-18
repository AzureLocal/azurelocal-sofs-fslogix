# =============================================================================
# SOFS on Azure Local — Resource Group (Azure Verified Module)
# =============================================================================

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "~> 0.2"

  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Convenience references used throughout other .tf files
locals {
  rg_name     = module.resource_group.name
  rg_location = module.resource_group.resource.location
  rg_id       = module.resource_group.resource_id
}
