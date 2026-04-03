# =============================================================================
# SOFS on Azure Local — Local Values
# =============================================================================

locals {
  # Normalize guest layout: option_a -> single, option_b -> triple
  guest_volume_layout_canonical = (
    lower(var.guest_volume_layout) == "option_a" ? "single" :
    lower(var.guest_volume_layout) == "option_b" ? "triple" :
    lower(var.guest_volume_layout)
  )

  # Phase ownership metadata — documents which tool owns each deployment phase
  phase_ownership = {
    azure_host   = "Terraform (Phases 1-2: resource provisioning + domain join)"
    guest_config = var.guest_config_engine == "ansible_create" || var.guest_config_engine == "ansible_existing" ? "Ansible (Phases 3-11)" : "PowerShell (Phases 3-11)"
    phase_map = {
      "Phase 0"  = "Preflight validation (this plan)"
      "Phase 1"  = "Azure resource provisioning (Terraform)"
      "Phase 2"  = "VM bootstrap + domain join (Terraform)"
      "Phase 3"  = "Anti-affinity rules (${var.guest_config_engine})"
      "Phase 5"  = "Role/feature install (${var.guest_config_engine})"
      "Phase 6"  = "Failover cluster (${var.guest_config_engine})"
      "Phase 7"  = "S2D volumes (${var.guest_config_engine})"
      "Phase 8"  = "SOFS role + shares (${var.guest_config_engine})"
      "Phase 9"  = "Permissions + FSRM (${var.guest_config_engine})"
      "Phase 10" = "AV guidance (${var.guest_config_engine})"
      "Phase 11" = "Validation (${var.guest_config_engine})"
    }
  }

  # Build VM name list: SOFS-01, SOFS-02, SOFS-03, ...
  vm_names = [for i in range(var.vm_count) : format("%s-%02d", var.vm_prefix, i + 1)]

  # Flatten data disks: one entry per (vm_index, disk_number) combination
  data_disks = flatten([
    for vm_idx in range(var.vm_count) : [
      for disk_idx in range(var.data_disk_count) : {
        key       = format("%s-%02d-data%d", var.vm_prefix, vm_idx + 1, disk_idx + 1)
        vm_index  = vm_idx
        vm_name   = local.vm_names[vm_idx]
        disk_num  = disk_idx + 1
        disk_name = format("%s-%02d-data%d", var.vm_prefix, vm_idx + 1, disk_idx + 1)
      }
    ]
  ])

  # Map for easy lookup: disk_key -> disk object
  data_disk_map = { for d in local.data_disks : d.key => d }

  # Group disk keys by VM index for attachment references
  disks_per_vm = {
    for vm_idx in range(var.vm_count) : vm_idx => [
      for d in local.data_disks : d.key if d.vm_index == vm_idx
    ]
  }

  # Extended location block reused by all Azure Local resources
  extended_location = {
    type = "CustomLocation"
    name = var.custom_location_id
  }

  # Per-VM storage path lookup: vm_name -> storage_path_id
  vm_storage_path = {
    for i in range(var.vm_count) : local.vm_names[i] =>
    lookup(var.storage_path_ids, format("%02d", i + 1), values(var.storage_path_ids)[0])
  }

  # Total pool calculations
  total_data_disks = var.vm_count * var.data_disk_count
  s2d_pool_size_gb = var.vm_count * var.data_disk_count * var.data_disk_size_gb

  # Ansible host objects: name + IP (from var.vm_ips keyed by zero-padded index, or placeholder)
  ansible_vm_hosts = [
    for i in range(var.vm_count) : {
      name = local.vm_names[i]
      ip   = lookup(var.vm_ips, format("%02d", i + 1), "FILL_IN_IP")
    }
  ]

  # SSH public key — read from disk; wrapper does not need to pass TF_VAR
  ssh_public_key = (
    var.ansible_controller_ssh_public_key != "" ? var.ansible_controller_ssh_public_key :
    fileexists(pathexpand(var.ssh_public_key_path)) ? file(pathexpand(var.ssh_public_key_path)) :
    ""
  )
}
