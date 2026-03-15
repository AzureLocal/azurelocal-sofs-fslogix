// =============================================================================
// SOFS on Azure Local — Example Bicep Parameters
// =============================================================================
// This file is for REFERENCE ONLY — the Deploy-SOFS-Azure.ps1 script builds
// -TemplateParameterObject at runtime from solution-sofs.yml.
// Never commit secrets (passwords, keys) to parameters files.
// =============================================================================

using 'main.bicep'

param resourceGroupName = 'rg-sofs-azl-eus-01'
param location = 'eastus'
param vmCount = 3
param vmPrefix = 'SOFS'
param vmProcessors = 4
param vmMemoryMB = 8192
param dataDiskCount = 4
param dataDiskSizeGB = 1024
param customLocationId = '<your-custom-location-resource-id>'
param logicalNetworkId = '<your-logical-network-resource-id>'
param galleryImageId = '<your-gallery-image-resource-id>'
param storagePathId = '<your-storage-path-resource-id>'
param adminUsername = 'LocalAdmin'
param adminPassword = '<resolved-from-keyvault-at-runtime>'
param cloudWitnessName = 'sofscloudwitness'
param tags = {
  project: 'SOFS'
  workload: 'FSLogix'
}
