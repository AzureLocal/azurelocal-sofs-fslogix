# =============================================================================
# SOFS on Azure Local — Resource Group
# =============================================================================

resource "azurerm_resource_group" "sofs" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
