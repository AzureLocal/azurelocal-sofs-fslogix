// =============================================================================
// SOFS on Azure Local — Example Bicep Parameters
// =============================================================================
// This file is for REFERENCE ONLY — the Deploy-SOFS-Azure.ps1 script builds
// -TemplateParameterObject at runtime from solution-sofs.yml.
// Never commit secrets (passwords, keys) to parameters files.
//
// Supports all 10 SOFS scenarios via guestVolumeLayout + resiliency settings.
// =============================================================================

using 'main.bicep'

// --- Resource Group & Location ---
param resourceGroupName = 'rg-sofs-azl-eus-01'
param location = 'eastus'

// --- VM Configuration ---
param vmCount = 3
param vmPrefix = 'SOFS'
param vmProcessors = 4
param vmMemoryMB = 8192

// --- Data Disks ---
param dataDiskCount = 4
param dataDiskSizeGB = 1024

// --- Azure Local Infrastructure ---
param customLocationId = '<your-custom-location-resource-id>'
param logicalNetworkId = '<your-logical-network-resource-id>'
param galleryImageId = '<your-gallery-image-resource-id>'

// Per-VM storage path mapping (spreads I/O across CSV volumes)
param storagePathIds = {
  '01': '<your-storage-path-01-resource-id>'
  '02': '<your-storage-path-02-resource-id>'
  '03': '<your-storage-path-03-resource-id>'
}

// --- OS Credentials ---
param adminUsername = 'LocalAdmin'
param adminPassword = '<resolved-from-keyvault-at-runtime>'

// --- Domain Join ---
param domainFqdn = 'contoso.local'
param domainNetbios = 'CONTOSO'
param domainJoinAccount = 'svc.domainjoin'
param domainJoinPassword = '<resolved-from-keyvault-at-runtime>'
param domainOuNodes = 'OU=SOFS-Cluster,OU=Servers,DC=contoso,DC=local'
param domainOuCluster = 'OU=SOFS-Cluster,OU=Servers,DC=contoso,DC=local'

// --- Cloud Witness ---
param cloudWitnessName = 'sofscloudwitness'

// --- Architecture Choices (determines which of the 10 scenarios) ---
// Canonical values: single | triple. Legacy aliases still accepted: option_a | option_b
param guestVolumeLayout = 'single'
param hostResiliency = 'two_way'
param guestResiliency = 'two_way'

// --- Guest Cluster ---
param clusterName = 'SOFS-Cluster'
param clusterIp = '192.168.211.60'
param accessPoint = 'FSLogixSOFS'
param shareName = 'FSLogix'
param s2dVolumeName = 'FSLogixData'
param s2dVolumeSize = '5632GB'
param s2dDataCopies = 2
param sofsRoleName = 'FSLogixSOFS'
param s2dPoolName = 'S2D on SOFS-Cluster'
param smbEncryption = true
param accessPointIp = '192.168.211.61'
param antiAffinityRule = 'SOFS-AntiAffinity'
param azlClusterName = 'AzLocalCluster'

// Triple layout (uncomment when guestVolumeLayout = 'triple' or 'option_b'):
// param sofsShares = [
//   { name: 'Profiles', volume: 'Profiles' }
//   { name: 'ODFC',     volume: 'ODFC' }
//   { name: 'AppData',  volume: 'AppData' }
// ]
// param s2dVolumes = [
//   { name: 'Profiles', size_gb: 33485, data_copies: 2 }
//   { name: 'ODFC',     size_gb: 21299, data_copies: 2 }
//   { name: 'AppData',  size_gb: 6144,  data_copies: 2 }
// ]

// --- Permissions ---
param permissionsAdminGroup = 'Domain Admins'
param permissionsUsersGroup = 'AVD-Users'
param permissionsAvdUsersGroup = 'AVD-Users'

// --- FSLogix ---
param fslogixEnabled = true
param fslogixProfileSizeMb = 30000
param fslogixVolumeType = 'VHDX'
param cloudCacheEnabled = false
// param cloudCacheAzureProvider = ''       // deprecated — use cloudCacheProviders
// param cloudCacheProviders = [
//   { type: 'azure', connectionString: '' }
// ]

// --- DNS ---
param dnsServers = ['10.0.1.10', '10.0.1.11']

// --- VM IPs ---
param vmIps = {
  '01': '192.168.211.51'
  '02': '192.168.211.52'
  '03': '192.168.211.53'
}

// --- Tags ---
param tags = {
  project: 'SOFS'
  workload: 'FSLogix'
  solution: 'sofs-azure-local'
}
