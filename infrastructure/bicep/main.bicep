// =============================================================================
// SOFS on Azure Local — Subscription-Scope Wrapper
// =============================================================================
// Creates the resource group (if it doesn't exist) and deploys SOFS VM
// resources onto an Azure Local cluster via module.
//
// targetScope = 'subscription' allows this template to:
//   1. Create or update the resource group
//   2. Deploy SOFS resources INTO that resource group via module scoping
//
// Inner module: sofs-resources.bicep (resource-group-scope)
//
// Resources per VM (deployed by inner module):
//   1. Microsoft.HybridCompute/machines               — Arc machine placeholder
//   2. Microsoft.AzureStackHCI/networkInterfaces       — NIC on Azure Local logical network
//   3. Microsoft.AzureStackHCI/virtualHardDisks[]      — Data disks for S2D pool
//   4. Microsoft.AzureStackHCI/VirtualMachineInstances — VM instance (extension resource)
//
// Also deploys:
//   5. Microsoft.Storage/storageAccounts               — Cloud witness for guest cluster
// =============================================================================

targetScope = 'subscription'

// ---------------------------------------------------------------------------
// Parameters — Resource Group
// ---------------------------------------------------------------------------

@description('Name of the resource group for SOFS resources. Created if it does not exist.')
param resourceGroupName string

@description('Azure region — must match the Azure Local cluster region')
param location string

// ---------------------------------------------------------------------------
// Parameters — VM Sizing & Count
// ---------------------------------------------------------------------------

@description('Number of SOFS VMs to deploy (minimum 3 for S2D two-way mirror)')
@minValue(3)
@maxValue(16)
param vmCount int = 3

@description('VM naming prefix — VMs named {prefix}-01, {prefix}-02, etc.')
param vmPrefix string = 'SOFS'

@description('Number of vCPUs per SOFS VM')
param vmProcessors int = 4

@description('Memory in MB per SOFS VM')
param vmMemoryMB int = 8192

// ---------------------------------------------------------------------------
// Parameters — Data Disks
// ---------------------------------------------------------------------------

@description('Number of data disks per VM (S2D pool = vmCount × diskCount × diskSize)')
@minValue(1)
@maxValue(64)
param dataDiskCount int = 4

@description('Size of each data disk in GB (dynamic provisioning)')
@minValue(64)
@maxValue(32767)
param dataDiskSizeGB int = 1024

// ---------------------------------------------------------------------------
// Parameters — Azure Local Infrastructure (cross-subscription references)
// ---------------------------------------------------------------------------

@description('Full ARM resource ID of the Azure Local custom location')
param customLocationId string

@description('Full ARM resource ID of the Azure Local logical network for SOFS VMs')
param logicalNetworkId string

@description('Full ARM resource ID of the Azure Local marketplace gallery image (Windows Server 2025 Datacenter)')
param galleryImageId string

@description('Full ARM resource ID of the Azure Local storage path for VM disks')
param storagePathId string

// ---------------------------------------------------------------------------
// Parameters — OS Credentials
// ---------------------------------------------------------------------------

@description('Local administrator username for the SOFS VMs')
param adminUsername string

@secure()
@description('Local administrator password for the SOFS VMs')
param adminPassword string

// ---------------------------------------------------------------------------
// Parameters — Cloud Witness
// ---------------------------------------------------------------------------

@description('Storage account name for the guest cluster cloud witness (max 24 chars, lowercase alphanumeric)')
param cloudWitnessName string

// ---------------------------------------------------------------------------
// Parameters — Tags
// ---------------------------------------------------------------------------

@description('Resource tags applied to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Resource Group — created at subscription scope
// ---------------------------------------------------------------------------

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ---------------------------------------------------------------------------
// Module — deploy SOFS VM resources into the resource group
// ---------------------------------------------------------------------------

module sofsVMs './sofs-resources.bicep' = {
  scope: rg
  name: 'sofs-vms-${uniqueString(resourceGroupName, vmPrefix)}'
  params: {
    vmCount: vmCount
    vmPrefix: vmPrefix
    location: location
    vmProcessors: vmProcessors
    vmMemoryMB: vmMemoryMB
    dataDiskCount: dataDiskCount
    dataDiskSizeGB: dataDiskSizeGB
    customLocationId: customLocationId
    logicalNetworkId: logicalNetworkId
    galleryImageId: galleryImageId
    storagePathId: storagePathId
    adminUsername: adminUsername
    adminPassword: adminPassword
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Cloud Witness Storage Account — for the guest failover cluster quorum
// ---------------------------------------------------------------------------

module witnessStorage './witness-storage.bicep' = {
  scope: rg
  name: 'sofs-witness-${uniqueString(resourceGroupName, cloudWitnessName)}'
  params: {
    storageAccountName: cloudWitnessName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output resourceGroupName string = rg.name
output deployedVMs array = sofsVMs.outputs.deployedVMs
output totalDataDisks int = sofsVMs.outputs.totalDataDisks
output s2dPoolSizeGB int = sofsVMs.outputs.s2dPoolSizeGB
output witnessStorageAccountName string = cloudWitnessName
