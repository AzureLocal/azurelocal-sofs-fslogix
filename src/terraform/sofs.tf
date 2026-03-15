# =============================================================================
# SOFS on Azure Local — VM Resources (azapi)
# =============================================================================
# Creates Azure Local resources via the azapi provider:
#   1. Arc machine placeholders  (Microsoft.HybridCompute/machines)
#   2. NICs on compute network   (Microsoft.AzureStackHCI/networkInterfaces)
#   3. Data disks for S2D pool   (Microsoft.AzureStackHCI/virtualHardDisks)
#   4. VM instances               (Microsoft.AzureStackHCI/virtualMachineInstances)
#
# Guest OS configuration (S2D, clustering, SOFS, SMB share) is handled by
# the PowerShell script ../powershell/Configure-SOFS-Cluster.ps1.
# =============================================================================

# ---------------------------------------------------------------------------
# Arc Machine Placeholders
# ---------------------------------------------------------------------------

resource "azapi_resource" "arc_machines" {
  for_each = toset(local.vm_names)

  type      = "Microsoft.HybridCompute/machines@2023-06-20-preview"
  name      = each.value
  location  = azurerm_resource_group.sofs.location
  parent_id = azurerm_resource_group.sofs.id
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "HCI"
  }

  schema_validation_enabled = false
}

# ---------------------------------------------------------------------------
# NICs on Compute Logical Network
# ---------------------------------------------------------------------------

resource "azapi_resource" "nics" {
  for_each = toset(local.vm_names)

  type      = "Microsoft.AzureStackHCI/networkInterfaces@2025-09-01-preview"
  name      = "${each.value}-nic"
  location  = azurerm_resource_group.sofs.location
  parent_id = azurerm_resource_group.sofs.id
  tags      = var.tags

  body = {
    extendedLocation = local.extended_location
    properties = {
      ipConfigurations = [
        {
          name = "${each.value}-nic"
          properties = merge(
            {
              subnet = {
                id = var.logical_network_id
              }
            },
            lookup(var.vm_ips, replace(each.value, "${var.vm_prefix}-", ""), "") != "" ? {
              privateIPAddress = lookup(var.vm_ips, replace(each.value, "${var.vm_prefix}-", ""), "")
            } : {}
          )
        }
      ]
    }
  }

  schema_validation_enabled = false
}

# ---------------------------------------------------------------------------
# Data Disks for S2D Pool
# ---------------------------------------------------------------------------

resource "azapi_resource" "data_disks" {
  for_each = local.data_disk_map

  type      = "Microsoft.AzureStackHCI/virtualHardDisks@2025-09-01-preview"
  name      = each.value.disk_name
  location  = azurerm_resource_group.sofs.location
  parent_id = azurerm_resource_group.sofs.id
  tags      = var.tags

  body = {
    extendedLocation = local.extended_location
    properties = {
      diskSizeGB  = var.data_disk_size_gb
      dynamic     = true
      containerId = local.vm_storage_path[each.value.vm_name]
    }
  }

  schema_validation_enabled = false
}

# ---------------------------------------------------------------------------
# VM Instances — extension resource on Arc machines
# ---------------------------------------------------------------------------

resource "azapi_resource" "vm_instances" {
  for_each = toset(local.vm_names)

  type      = "Microsoft.AzureStackHCI/virtualMachineInstances@2025-09-01-preview"
  name      = "default"
  parent_id = azapi_resource.arc_machines[each.value].id

  body = {
    extendedLocation = local.extended_location
    properties = {
      osProfile = {
        adminUsername = var.admin_username
        adminPassword = data.external.admin_password.result.value
        computerName  = each.value
        windowsConfiguration = {
          provisionVMAgent       = true
          provisionVMConfigAgent = true
        }
      }
      hardwareProfile = {
        vmSize     = "Default"
        processors = var.vm_processors
        memoryMB   = var.vm_memory_mb
      }
      storageProfile = {
        imageReference = {
          id = var.gallery_image_id
        }
        vmConfigStoragePathId = local.vm_storage_path[each.value]
        dataDisks = [
          for disk_key in local.disks_per_vm[index(local.vm_names, each.value)] : {
            id = azapi_resource.data_disks[disk_key].id
          }
        ]
      }
      networkProfile = {
        networkInterfaces = [
          {
            id = azapi_resource.nics[each.value].id
          }
        ]
      }
    }
  }

  depends_on = [
    azapi_resource.nics,
    azapi_resource.data_disks,
  ]

  schema_validation_enabled = false
}
