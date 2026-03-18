# =============================================================================
# SOFS on Azure Local — Terraform Locals & Output Tests
# =============================================================================
# Validates computed local values (VM names, disk maps, pool calculations)
# and output structure using mocked providers.
# Run: cd src/terraform && terraform test -test-directory=../../tests/terraform
# =============================================================================

mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "local" {}
mock_provider "external" {}

# ---------------------------------------------------------------------------
# Shared baseline
# ---------------------------------------------------------------------------
variables {
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "rg-test"
  location            = "eastus"
  custom_location_id  = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.ExtendedLocation/customLocations/cl"
  logical_network_id  = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.AzureStackHCI/logicalNetworks/ln"
  gallery_image_id    = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.AzureStackHCI/marketplaceGalleryImages/img"
  storage_path_ids    = { "01" = "/sp-01", "02" = "/sp-02", "03" = "/sp-03" }
  key_vault_name      = "kv-test"
  cloud_witness_name  = "stwitness01"
  cluster_name        = "SOFS-Test"
  cluster_ip          = "192.168.1.60"
  domain_fqdn         = "test.local"
  domain_netbios      = "TEST"
  azl_cluster_name    = "AzlCluster"
  vm_count            = 3
  vm_prefix           = "SOFS"
  data_disk_count     = 4
  data_disk_size_gb   = 1024
}

# ---------------------------------------------------------------------------
# 1. Total data disks = vm_count * data_disk_count
# ---------------------------------------------------------------------------
run "total_data_disks_3x4" {
  command = plan

  assert {
    condition     = output.total_data_disks == 12
    error_message = "Expected total_data_disks = 12 (3 VMs * 4 disks), got ${output.total_data_disks}"
  }
}

# ---------------------------------------------------------------------------
# 2. S2D pool size = vm_count * data_disk_count * data_disk_size_gb
# ---------------------------------------------------------------------------
run "s2d_pool_size_3x4x1024" {
  command = plan

  assert {
    condition     = output.s2d_pool_size_gb == 12288
    error_message = "Expected s2d_pool_size_gb = 12288, got ${output.s2d_pool_size_gb}"
  }
}

# ---------------------------------------------------------------------------
# 3. 2-node scenario has correct disk count
# ---------------------------------------------------------------------------
run "total_data_disks_2x4" {
  command = plan

  variables {
    vm_count         = 2
    data_disk_count  = 4
    data_disk_size_gb = 512
    storage_path_ids = { "01" = "/sp-01", "02" = "/sp-02" }
  }

  assert {
    condition     = output.total_data_disks == 8
    error_message = "Expected total_data_disks = 8 (2 VMs * 4 disks)"
  }

  assert {
    condition     = output.s2d_pool_size_gb == 4096
    error_message = "Expected s2d_pool_size_gb = 4096 (2*4*512)"
  }
}

# ---------------------------------------------------------------------------
# 4. Resource group output populated
# ---------------------------------------------------------------------------
run "resource_group_output_set" {
  command = plan

  assert {
    condition     = output.resource_group_name != ""
    error_message = "resource_group_name output should not be empty"
  }
}

# ---------------------------------------------------------------------------
# 5. Guest config engine output matches variable
# ---------------------------------------------------------------------------
run "guest_config_engine_output" {
  command = plan

  variables {
    guest_config_engine = "ansible_existing"
  }

  assert {
    condition     = output.guest_config_engine == "ansible_existing"
    error_message = "guest_config_engine output should match variable"
  }
}

# ---------------------------------------------------------------------------
# 6. Ansible inventory placeholder detection
# ---------------------------------------------------------------------------
run "placeholder_when_no_ips" {
  command = plan

  variables {
    vm_ips = {}
  }

  assert {
    condition     = output.ansible_inventory_has_placeholders == true
    error_message = "Should detect FILL_IN_IP placeholders when vm_ips is empty"
  }
}

run "no_placeholder_when_ips_provided" {
  command = plan

  variables {
    vm_ips = { "01" = "10.0.0.1", "02" = "10.0.0.2", "03" = "10.0.0.3" }
  }

  assert {
    condition     = output.ansible_inventory_has_placeholders == false
    error_message = "Should not have placeholders when all vm_ips are provided"
  }
}
