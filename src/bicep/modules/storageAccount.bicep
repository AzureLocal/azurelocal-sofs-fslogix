// modules/storageAccount.bicep
// Creates an Azure Storage Account for diagnostics / FSLogix backup.

@description('Storage account name (3-24 lowercase alphanumeric, globally unique).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    encryption: {
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

output storageAccountId   string = storageAccount.id
output storageAccountName string = storageAccount.name
