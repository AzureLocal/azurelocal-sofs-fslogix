// =============================================================================
// SOFS on Azure Local — Resource-Group-Scope Module
// =============================================================================
// Deploys N SOFS VMs onto an Azure Local cluster with data disks for S2D.
// Called by the subscription-scope wrapper (main.bicep).
//
// Resources per VM:
//   1. Microsoft.HybridCompute/machines               — Arc machine placeholder
//   2. Microsoft.AzureStackHCI/networkInterfaces       — NIC on Azure Local logical network
//   3. Microsoft.AzureStackHCI/VirtualMachineInstances — VM instance (extension resource)
//   4. Microsoft.AzureStackHCI/virtualHardDisks[]      — Data disks for S2D pool
//
// Post-deployment guest OS configuration (S2D, failover clustering, SOFS role,
// SMB share) is handled by the PowerShell script Configure-SOFS-Cluster.ps1.
// =============================================================================

// ---------------------------------------------------------------------------
// Parameters — VM Sizing & Count
// ---------------------------------------------------------------------------

@description('Number of SOFS VMs to deploy (minimum 3 for S2D two-way mirror)')
@minValue(3)
@maxValue(16)
param vmCount int = 3

@description('VM naming prefix — VMs named {prefix}-01, {prefix}-02, etc.')
param vmPrefix string = 'SOFS'

@description('Azure region — must match the Azure Local cluster region')
param location string

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
// Parameters — Tags
// ---------------------------------------------------------------------------

@description('Resource tags applied to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Resources — Arc Machine Placeholders
// ---------------------------------------------------------------------------

resource arcMachines 'Microsoft.HybridCompute/machines@2023-06-20-preview' = [for i in range(0, vmCount): {
  name: '${vmPrefix}-${padLeft(string(i + 1), 2, '0')}'
  location: location
  kind: 'HCI'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}]

// ---------------------------------------------------------------------------
// Resources — NICs on Compute Logical Network
// ---------------------------------------------------------------------------

resource nics 'Microsoft.AzureStackHCI/networkInterfaces@2025-09-01-preview' = [for i in range(0, vmCount): {
  name: '${vmPrefix}-${padLeft(string(i + 1), 2, '0')}-nic'
  location: location
  tags: tags
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    ipConfigurations: [
      {
        name: '${vmPrefix}-${padLeft(string(i + 1), 2, '0')}-nic'
        properties: {
          subnet: {
            id: logicalNetworkId
          }
        }
      }
    ]
  }
}]

// ---------------------------------------------------------------------------
// Resources — Data Disks for S2D Pool
// ---------------------------------------------------------------------------
// Flatten loop: vmCount × dataDiskCount disks total.
// Index mapping: disk[j] belongs to VM[j / dataDiskCount], disk number = (j % dataDiskCount) + 1

resource dataDisks 'Microsoft.AzureStackHCI/virtualHardDisks@2025-09-01-preview' = [for j in range(0, vmCount * dataDiskCount): {
  name: '${vmPrefix}-${padLeft(string((j / dataDiskCount) + 1), 2, '0')}-data${(j % dataDiskCount) + 1}'
  location: location
  tags: tags
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    diskSizeGB: dataDiskSizeGB
    dynamic: true
    containerId: storagePathId
  }
}]

// ---------------------------------------------------------------------------
// Resources — VM Instances
// ---------------------------------------------------------------------------

resource vmInstances 'Microsoft.AzureStackHCI/virtualMachineInstances@2025-09-01-preview' = [for i in range(0, vmCount): {
  name: 'default'
  scope: arcMachines[i]
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  dependsOn: [
    nics[i]
    // Depend on all data disks for this VM
    // Data disks for VM i are at indices: i*dataDiskCount .. (i+1)*dataDiskCount-1
  ]
  properties: {
    osProfile: {
      adminUsername: adminUsername
      adminPassword: adminPassword
      computerName: '${vmPrefix}-${padLeft(string(i + 1), 2, '0')}'
      windowsConfiguration: {
        provisionVMAgent: true
        provisionVMConfigAgent: true
      }
    }
    hardwareProfile: {
      vmSize: 'Default'
      processors: vmProcessors
      memoryMB: vmMemoryMB
    }
    storageProfile: {
      imageReference: {
        id: galleryImageId
      }
      vmConfigStoragePathId: storagePathId
      dataDisks: [for d in range(0, dataDiskCount): {
        id: dataDisks[(i * dataDiskCount) + d].id
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output deployedVMs array = [for i in range(0, vmCount): {
  vmName: arcMachines[i].name
  arcMachineId: arcMachines[i].id
  nicName: nics[i].name
  nicId: nics[i].id
}]

output totalDataDisks int = vmCount * dataDiskCount
output s2dPoolSizeGB int = vmCount * dataDiskCount * dataDiskSizeGB
