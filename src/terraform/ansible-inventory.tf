# =============================================================================
# SOFS on Azure Local — Generate Ansible Inventory
# =============================================================================
# After terraform apply, writes a fully-populated Ansible inventory to
# ../ansible/inventory-generated.yml including:
#   - All Azure resource IDs and configuration values
#   - Cloud witness storage account key (sensitive — do not commit this file)
#   - VM host entries (IPs from var.vm_ips, or FILL_IN_IP placeholders)
#
# The generated file is consumed by:
#   ansible-playbook -i ansible/inventory-generated.yml \
#                    ansible/configure-sofs-cluster.yml
# =============================================================================

resource "local_sensitive_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory-generated.yml"

  content = templatefile("${path.module}/templates/inventory.yml.tftpl", {
    timestamp          = timestamp()
    workspace          = terraform.workspace
    subscription_id    = var.subscription_id
    resource_group     = var.resource_group_name
    location           = var.location
    custom_location_id = var.custom_location_id
    logical_network_id = var.logical_network_id
    gallery_image_id   = var.gallery_image_id
    storage_path_ids   = var.storage_path_ids
    vm_prefix          = var.vm_prefix
    vm_count           = var.vm_count
    vm_processors      = var.vm_processors
    vm_memory_mb       = var.vm_memory_mb
    admin_username     = var.admin_username
    data_disk_count    = var.data_disk_count
    data_disk_size_gb  = var.data_disk_size_gb
    cloud_witness_name = var.cloud_witness_name
    witness_key        = azurerm_storage_account.cloud_witness.primary_access_key
    cluster_name       = var.cluster_name
    cluster_ip         = var.cluster_ip
    access_point       = var.access_point
    share_name         = var.share_name
    s2d_volume_name    = var.s2d_volume_name
    s2d_volume_size    = var.s2d_volume_size
    s2d_data_copies    = var.s2d_data_copies
    domain_fqdn        = var.domain_fqdn
    domain_netbios     = var.domain_netbios
    anti_affinity_rule = var.anti_affinity_rule
    azl_cluster_name   = var.azl_cluster_name
    winrm_transport    = var.winrm_transport
    vm_hosts           = local.ansible_vm_hosts
  })

  # The generated file contains the witness key — ensure it is never committed
  lifecycle {
    ignore_changes = []
  }
}
