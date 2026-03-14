variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group to create."
  type        = string
  default     = "rg-azurelocal-prod"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "diag_storage_account_name" {
  description = "Globally unique name for the diagnostic storage account (3-24 lowercase alphanumeric)."
  type        = string
}

variable "environment_tag" {
  description = "Value for the 'environment' resource tag."
  type        = string
  default     = "production"
}

variable "owner_tag" {
  description = "Value for the 'owner' resource tag."
  type        = string
  default     = "platform-team"
}
