// =============================================================================
// SOFS on Azure Local — Subscription-Scope Wrapper
// =============================================================================
// Creates the resource group (AVM) and deploys SOFS VM resources via module.
//
// targetScope = 'subscription' allows this template to:
//   1. Create/update the resource group via AVM module
//   2. Deploy SOFS resources INTO that resource group via module scoping
//
// Inner module: sofs-resources.bicep (resource-group-scope)
//
// Resources per VM (deployed by inner module):
//   1. Microsoft.HybridCompute/machines               — Arc machine placeholder
//   2. Microsoft.AzureStackHCI/networkInterfaces       — NIC on Azure Local logical network
//   3. Microsoft.AzureStackHCI/virtualHardDisks[]      — Data disks for S2D pool
//   4. Microsoft.AzureStackHCI/VirtualMachineInstances — VM instance (extension resource)
//   5. Microsoft.HybridCompute/machines/extensions     — Domain join (JsonADDomainExtension)
//
// Also deploys:
//   6. AVM Storage Account                            — Cloud witness for guest cluster
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

@description('Number of SOFS VMs to deploy (minimum 2 for two-way mirror)')
@minValue(2)
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
// Parameters — Azure Local Infrastructure
// ---------------------------------------------------------------------------

@description('Full ARM resource ID of the Azure Local custom location')
param customLocationId string

@description('Full ARM resource ID of the Azure Local logical network for SOFS VMs')
param logicalNetworkId string

@description('Full ARM resource ID of the Azure Local marketplace gallery image')
param galleryImageId string

@description('Per-VM storage path mapping: { "01": "<ARM-ID>", "02": "<ARM-ID>" }. Falls back to first entry if key not found.')
param storagePathIds object

// ---------------------------------------------------------------------------
// Parameters — OS Credentials
// ---------------------------------------------------------------------------

@description('Local administrator username for the SOFS VMs')
param adminUsername string

@secure()
@description('Local administrator password for the SOFS VMs')
param adminPassword string

// ---------------------------------------------------------------------------
// Parameters — Domain Join
// ---------------------------------------------------------------------------

@description('Active Directory domain FQDN')
param domainFqdn string

@description('Active Directory NetBIOS domain name')
param domainNetbios string

@description('Domain join service account (sAMAccountName)')
param domainJoinAccount string = 'svc.domainjoin'

@secure()
@description('Domain join service account password')
param domainJoinPassword string

@description('OU path for SOFS VM computer objects')
param domainOuNodes string = ''

@description('OU path for the WSFC cluster name object (CNO)')
param domainOuCluster string = ''

// ---------------------------------------------------------------------------
// Parameters — Cloud Witness
// ---------------------------------------------------------------------------

@description('Storage account name for the guest cluster cloud witness (max 24 chars, lowercase alphanumeric)')
@maxLength(24)
param cloudWitnessName string

// ---------------------------------------------------------------------------
// Parameters — Deployment Architecture Choices
// ---------------------------------------------------------------------------

@description('Guest S2D volume layout. Canonical values: single, triple. Legacy aliases: option_a, option_b')
@allowed(['single', 'triple', 'option_a', 'option_b'])
param guestVolumeLayout string = 'single'

@description('Host CSV mirror: two_way or three_way')
@allowed(['two_way', 'three_way'])
param hostResiliency string = 'two_way'

@description('Guest S2D data copies: two_way or three_way')
@allowed(['two_way', 'three_way'])
param guestResiliency string = 'two_way'

// ---------------------------------------------------------------------------
// Parameters — Guest Cluster Configuration
// These parameters are NOT consumed by Azure resource deployment (Phases 1-2).
// They exist as pass-through metadata for downstream guest configuration tools
// (PowerShell, Ansible) that execute Phases 3-11.
// ---------------------------------------------------------------------------

@metadata({ phase: 'guest', passThrough: true })
@description('Windows Failover Cluster name (pass-through to guest config tool)')
param clusterName string = 'SOFS-Cluster'

@metadata({ phase: 'guest', passThrough: true })
@description('Static IP for the cluster name object (pass-through to guest config tool)')
param clusterIp string

@metadata({ phase: 'guest', passThrough: true })
@description('Scale-Out File Server access point name — Single layout (pass-through to guest config tool)')
param accessPoint string = 'FSLogixSOFS'

@metadata({ phase: 'guest', passThrough: true })
@description('FSLogix SMB share name — Single layout (pass-through to guest config tool)')
param shareName string = 'FSLogix'

@metadata({ phase: 'guest', passThrough: true })
@description('S2D volume friendly name — Single layout (pass-through to guest config tool)')
param s2dVolumeName string = 'FSLogixData'

@metadata({ phase: 'guest', passThrough: true })
@description('S2D volume size string — Single layout, e.g. "5632GB" (pass-through to guest config tool)')
param s2dVolumeSize string = '5632GB'

@metadata({ phase: 'guest', passThrough: true })
@description('S2D mirror data copies — Single layout: 2 for two-way, 3 for three-way (pass-through to guest config tool)')
param s2dDataCopies int = 2

@metadata({ phase: 'guest', passThrough: true })
@description('SOFS cluster role name (pass-through to guest config tool)')
param sofsRoleName string = 'FSLogixSOFS'

@metadata({ phase: 'guest', passThrough: true })
@description('S2D storage pool friendly name (pass-through to guest config tool)')
param s2dPoolName string = 'S2D on SOFS-Cluster'

@metadata({ phase: 'guest', passThrough: true })
@description('Enable SMB 3.x encryption on SOFS shares (pass-through to guest config tool)')
param smbEncryption bool = true

@metadata({ phase: 'guest', passThrough: true })
@description('Static IP for the SOFS client access point (pass-through to guest config tool)')
param accessPointIp string = ''

@metadata({ phase: 'guest', passThrough: true })
@description('Triple layout: list of SMB share definitions [{name, volume}] (pass-through to guest config tool)')
param sofsShares array = []

@metadata({ phase: 'guest', passThrough: true })
@description('Triple layout: list of S2D volume definitions [{name, size_gb, data_copies}] (pass-through to guest config tool)')
param s2dVolumes array = []

@metadata({ phase: 'guest', passThrough: true })
@description('Anti-affinity rule name (pass-through to guest config tool)')
param antiAffinityRule string = 'SOFS-AntiAffinity'

@metadata({ phase: 'guest', passThrough: true })
@description('Azure Local host cluster name (pass-through to guest config tool, used for anti-affinity)')
param azlClusterName string

// ---------------------------------------------------------------------------
// Parameters — Permissions (pass-through to guest config tool, Phases 8-9)
// ---------------------------------------------------------------------------

@metadata({ phase: 'guest', passThrough: true })
@description('AD group for share administrative access (pass-through to guest config tool)')
param permissionsAdminGroup string = 'Domain Admins'

@metadata({ phase: 'guest', passThrough: true })
@description('AD group for share user access (pass-through to guest config tool)')
param permissionsUsersGroup string = 'AVD-Users'

@metadata({ phase: 'guest', passThrough: true })
@description('AD group for AVD users (FSLogix profile access, pass-through to guest config tool)')
param permissionsAvdUsersGroup string = 'AVD-Users'

// ---------------------------------------------------------------------------
// Parameters — FSLogix (pass-through to guest config tool, Phases 9c-10)
// ---------------------------------------------------------------------------

@metadata({ phase: 'guest', passThrough: true })
@description('Whether FSLogix profile containers are enabled (pass-through to guest config tool)')
param fslogixEnabled bool = true

@metadata({ phase: 'guest', passThrough: true })
@description('Maximum profile container size in MB, FSRM quota (pass-through to guest config tool)')
param fslogixProfileSizeMb int = 30000

@metadata({ phase: 'guest', passThrough: true })
@description('Profile container format: VHDX or VHD (pass-through to guest config tool)')
param fslogixVolumeType string = 'VHDX'

@metadata({ phase: 'guest', passThrough: true })
@description('Enable FSLogix Cloud Cache for multi-site DR (pass-through to guest config tool)')
param cloudCacheEnabled bool = false

@secure()
@metadata({ phase: 'guest', passThrough: true })
@description('(Deprecated) Azure Blob connection string — use cloudCacheProviders instead (pass-through to guest config tool)')
param cloudCacheAzureProvider string = ''

@metadata({ phase: 'guest', passThrough: true })
@description('Additional Cloud Cache providers for CCDLocations, SMB providers auto-generated (pass-through to guest config tool)')
param cloudCacheProviders array = []

// ---------------------------------------------------------------------------
// Parameters — DNS (pass-through to guest config tool)
// ---------------------------------------------------------------------------

@metadata({ phase: 'guest', passThrough: true })
@description('DNS server IP addresses for guest cluster VMs (pass-through to guest config tool)')
param dnsServers array = []

// ---------------------------------------------------------------------------
// Parameters — VM IPs
// ---------------------------------------------------------------------------

@description('Map of VM suffix to static IP: { "01": "10.0.0.1", "02": "10.0.0.2" }')
param vmIps object = {}

// ---------------------------------------------------------------------------
// Parameters — Tags
// ---------------------------------------------------------------------------

@description('Resource tags applied to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Resource Group — AVM Module (Bicep Public Registry)
// ---------------------------------------------------------------------------

module rg 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'rg-${uniqueString(resourceGroupName)}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Module — deploy SOFS VM resources into the resource group
// ---------------------------------------------------------------------------

module sofsVMs './sofs-resources.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'sofs-vms-${uniqueString(resourceGroupName, vmPrefix)}'
  dependsOn: [rg]
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
    storagePathIds: storagePathIds
    adminUsername: adminUsername
    adminPassword: adminPassword
    domainFqdn: domainFqdn
    domainNetbios: domainNetbios
    domainJoinAccount: domainJoinAccount
    domainJoinPassword: domainJoinPassword
    domainOuNodes: domainOuNodes
    vmIps: vmIps
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Cloud Witness Storage Account — AVM Module (Bicep Public Registry)
// ---------------------------------------------------------------------------

module witnessStorage 'br/public:avm/res/storage/storage-account:0.15.0' = {
  scope: resourceGroup(resourceGroupName)
  name: 'sofs-witness-${uniqueString(resourceGroupName, cloudWitnessName)}'
  dependsOn: [rg]
  params: {
    name: cloudWitnessName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output resourceGroupName string = resourceGroupName
output deployedVMs array = sofsVMs.outputs.deployedVMs
output totalDataDisks int = sofsVMs.outputs.totalDataDisks
output s2dPoolSizeGB int = sofsVMs.outputs.s2dPoolSizeGB
output witnessStorageAccountName string = cloudWitnessName

@description('Phase ownership metadata: Bicep handles Phases 1-2 (Azure provisioning). Guest Phases 3-11 are delegated to the guest_config tool.')
output phaseOwnership object = {
  azure_host: 'Bicep (Phases 1-2: resource group, VMs, NICs, disks, domain join, cloud witness)'
  guest_config: 'Delegated to PowerShell or Ansible (Phases 3-11)'
  guestVolumeLayout: guestVolumeLayout
}
