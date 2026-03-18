# =============================================================================
# SOFS on Azure Local — Terraform
# =============================================================================
# Provider configuration for deploying SOFS guest-cluster Azure resources.
#
# - azapi:    Azure Local VMs, NICs, data disks (Microsoft.AzureStackHCI/*)
# - azurerm:  Cloud witness storage account, resource group (via AVM modules)
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azapi" {}
