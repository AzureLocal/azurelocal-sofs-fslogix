# =============================================================================
# SOFS on Azure Local — Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the SOFS resource group"
  value       = local.rg_name
}

output "resource_group_id" {
  description = "Resource ID of the SOFS resource group"
  value       = local.rg_id
}

output "deployed_vms" {
  description = "Map of deployed SOFS VM names to their Arc machine resource IDs"
  value = {
    for name in local.vm_names : name => {
      arc_machine_id = azapi_resource.arc_machines[name].id
      nic_id         = azapi_resource.nics[name].id
    }
  }
}

output "total_data_disks" {
  description = "Total number of data disks deployed across all VMs"
  value       = local.total_data_disks
}

output "s2d_pool_size_gb" {
  description = "Total raw S2D pool size in GB (before mirror overhead)"
  value       = local.s2d_pool_size_gb
}

output "cloud_witness_storage_account_name" {
  description = "Cloud witness storage account name"
  value       = module.cloud_witness.name
}

output "cloud_witness_storage_account_key" {
  description = "Primary access key for the cloud witness storage account"
  value       = module.cloud_witness.resource.primary_access_key
  sensitive   = true
}

output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file (contains sensitive witness key — do not commit)"
  value       = local_sensitive_file.ansible_inventory.filename
}

output "ansible_inventory_has_placeholders" {
  description = "True if any VM host entries still contain FILL_IN_IP placeholders — update vm_ips in tfvars and re-apply before running Ansible"
  value       = anytrue([for h in local.ansible_vm_hosts : h.ip == "FILL_IN_IP"])
}

output "guest_config_engine" {
  description = "Phase 2 engine selected: powershell, ansible_create, or ansible_existing"
  value       = var.guest_config_engine
}

output "ansible_controller_private_ip" {
  description = "Private IP of the Ansible controller VM (created or existing)"
  value = (
    var.guest_config_engine == "ansible_create"
    ? azurerm_network_interface.ansible_controller[0].private_ip_address
    : var.guest_config_engine == "ansible_existing"
      ? var.ansible_existing_controller_ip
      : null
  )
}

output "ansible_controller_id" {
  description = "Resource ID of the Ansible controller VM (only when ansible_create)"
  value       = var.guest_config_engine == "ansible_create" ? azurerm_linux_virtual_machine.ansible_controller[0].id : null
}

output "ansible_controller_admin_username" {
  description = "SSH admin username for the controller VM"
  value = (
    var.guest_config_engine == "ansible_create"
    ? var.ansible_controller_admin_username
    : var.guest_config_engine == "ansible_existing"
      ? var.ansible_existing_controller_user
      : null
  )
}

output "guest_volume_layout_canonical" {
  description = "Normalized guest volume layout (single/triple). Legacy aliases option_a/option_b are mapped to canonical values."
  value       = local.guest_volume_layout_canonical
}

output "phase_ownership" {
  description = "Phase ownership metadata documenting which tool owns each deployment phase"
  value       = local.phase_ownership
}
