// =============================================================================
// Cloud Witness Storage Account — for SOFS guest cluster quorum
// =============================================================================

@description('Storage account name for cloud witness (max 24 chars, lowercase alphanumeric)')
@maxLength(24)
param storageAccountName string

@description('Azure region')
param location string

@description('Resource tags')
param tags object = {}

resource witnessStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    accessTier: 'Hot'
  }
}

@description('Primary access key for use as cloud witness key')
output storageAccountKey string = witnessStorage.listKeys().keys[0].value

@description('Storage account name')
output storageAccountName string = witnessStorage.name
