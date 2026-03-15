// main.bicep
// Entry-point Bicep template for SOFS/FSLogix supporting infrastructure on Azure Local.
// Scope: subscription (to allow resource group creation)
//
// Deploy with:
//   az deployment sub create \
//     --location <region> \
//     --template-file main.bicep \
//     --parameters main.bicepparam

targetScope = 'subscription'

// -------------------------------------------------------
// Parameters
// -------------------------------------------------------

@description('Azure region for all resources.')
param location string

@description('Name of the resource group to create.')
param resourceGroupName string

@description('Name of the diagnostic storage account (must be globally unique, 3-24 lowercase alphanumeric).')
param diagStorageAccountName string

@description('Environment tag value (e.g. production, staging, dev).')
param environmentTag string = 'production'

@description('Owner tag value.')
param ownerTag string = 'platform-team'

// -------------------------------------------------------
// Variables
// -------------------------------------------------------

var tags = {
  environment: environmentTag
  owner: ownerTag
  deployedBy: 'bicep'
}

// -------------------------------------------------------
// Resource Group
// -------------------------------------------------------

module rg 'modules/resourceGroup.bicep' = {
  name: 'deploy-rg-${resourceGroupName}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// -------------------------------------------------------
// Diagnostic Storage Account
// -------------------------------------------------------

module diagStorage 'modules/storageAccount.bicep' = {
  name: 'deploy-storage-diag'
  scope: resourceGroup(resourceGroupName)
  dependsOn: [rg]
  params: {
    name: diagStorageAccountName
    location: location
    tags: tags
  }
}

// -------------------------------------------------------
// Outputs
// -------------------------------------------------------

output resourceGroupId string = rg.outputs.resourceGroupId
output diagStorageAccountId string = diagStorage.outputs.storageAccountId
output diagStorageAccountName string = diagStorage.outputs.storageAccountName
