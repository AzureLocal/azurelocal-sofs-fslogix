# =============================================================================
# SOFS on Azure Local — Terraform Variable Validation Tests
# =============================================================================
# Verifies input variable validation rules using `terraform test`.
# Run: cd src/terraform && terraform test -test-directory=../../tests/terraform
# =============================================================================

# ---------------------------------------------------------------------------
# Shared mock providers — no cloud calls needed for validation tests
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}
mock_provider "azapi" {}
mock_provider "local" {}
mock_provider "external" {}

# ---------------------------------------------------------------------------
# Minimal valid variable set reused across runs
# ---------------------------------------------------------------------------
variables {
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "rg-test"
  location            = "eastus"
  custom_location_id  = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.ExtendedLocation/customLocations/cl"
  logical_network_id  = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.AzureStackHCI/logicalNetworks/ln"
  gallery_image_id    = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.AzureStackHCI/marketplaceGalleryImages/img"
  storage_path_ids    = { "01" = "/sub/rg/sp-01", "02" = "/sub/rg/sp-02", "03" = "/sub/rg/sp-03" }
  key_vault_name      = "kv-test"
  cloud_witness_name  = "stwitness01"
  cluster_name        = "SOFS-Test"
  cluster_ip          = "192.168.1.60"
  domain_fqdn         = "test.local"
  domain_netbios      = "TEST"
  azl_cluster_name    = "AzlCluster"
  vm_count            = 3
  vm_prefix           = "SOFS"
}

# ---------------------------------------------------------------------------
# 1. vm_count — minimum 2
# ---------------------------------------------------------------------------
run "vm_count_minimum_2_passes" {
  command = plan

  variables {
    vm_count = 2
  }
}

run "vm_count_below_minimum_fails" {
  command = plan

  variables {
    vm_count = 1
  }

  expect_failures = [
    var.vm_count,
  ]
}

# ---------------------------------------------------------------------------
# 2. vm_count — maximum 16
# ---------------------------------------------------------------------------
run "vm_count_maximum_16_passes" {
  command = plan

  variables {
    vm_count = 16
  }
}

run "vm_count_above_maximum_fails" {
  command = plan

  variables {
    vm_count = 17
  }

  expect_failures = [
    var.vm_count,
  ]
}

# ---------------------------------------------------------------------------
# 3. vm_prefix — max 11 characters
# ---------------------------------------------------------------------------
run "vm_prefix_11_chars_passes" {
  command = plan

  variables {
    vm_prefix = "ABCDEFGHIJK"
  }
}

run "vm_prefix_12_chars_fails" {
  command = plan

  variables {
    vm_prefix = "ABCDEFGHIJKL"
  }

  expect_failures = [
    var.vm_prefix,
  ]
}

# ---------------------------------------------------------------------------
# 4. cloud_witness_name — lowercase alphanumeric, max 24 chars
# ---------------------------------------------------------------------------
run "cloud_witness_name_valid" {
  command = plan

  variables {
    cloud_witness_name = "stwitness01"
  }
}

run "cloud_witness_name_uppercase_fails" {
  command = plan

  variables {
    cloud_witness_name = "StWitness01"
  }

  expect_failures = [
    var.cloud_witness_name,
  ]
}

run "cloud_witness_name_too_long_fails" {
  command = plan

  variables {
    cloud_witness_name = "abcdefghijklmnopqrstuvwxy"
  }

  expect_failures = [
    var.cloud_witness_name,
  ]
}

# ---------------------------------------------------------------------------
# 5. guest_volume_layout — option_a or option_b only
# ---------------------------------------------------------------------------
run "guest_volume_layout_option_a_passes" {
  command = plan

  variables {
    guest_volume_layout = "option_a"
  }
}

run "guest_volume_layout_option_b_passes" {
  command = plan

  variables {
    guest_volume_layout = "option_b"
  }
}

run "guest_volume_layout_invalid_fails" {
  command = plan

  variables {
    guest_volume_layout = "option_c"
  }

  expect_failures = [
    var.guest_volume_layout,
  ]
}

# ---------------------------------------------------------------------------
# 6. host_resiliency — two_way or three_way only
# ---------------------------------------------------------------------------
run "host_resiliency_two_way_passes" {
  command = plan

  variables {
    host_resiliency = "two_way"
  }
}

run "host_resiliency_three_way_passes" {
  command = plan

  variables {
    host_resiliency = "three_way"
  }
}

run "host_resiliency_invalid_fails" {
  command = plan

  variables {
    host_resiliency = "four_way"
  }

  expect_failures = [
    var.host_resiliency,
  ]
}

# ---------------------------------------------------------------------------
# 7. guest_resiliency — two_way or three_way only
# ---------------------------------------------------------------------------
run "guest_resiliency_two_way_passes" {
  command = plan

  variables {
    guest_resiliency = "two_way"
  }
}

run "guest_resiliency_three_way_passes" {
  command = plan

  variables {
    guest_resiliency = "three_way"
  }
}

run "guest_resiliency_invalid_fails" {
  command = plan

  variables {
    guest_resiliency = "four_way"
  }

  expect_failures = [
    var.guest_resiliency,
  ]
}

# ---------------------------------------------------------------------------
# 8. guest_config_engine validation
# ---------------------------------------------------------------------------
run "guest_config_engine_powershell_passes" {
  command = plan

  variables {
    guest_config_engine = "powershell"
  }
}

run "guest_config_engine_ansible_create_passes" {
  command = plan

  variables {
    guest_config_engine = "ansible_create"
  }
}

run "guest_config_engine_invalid_fails" {
  command = plan

  variables {
    guest_config_engine = "chef"
  }

  expect_failures = [
    var.guest_config_engine,
  ]
}

# ---------------------------------------------------------------------------
# 9. winrm_transport validation
# ---------------------------------------------------------------------------
run "winrm_transport_kerberos_passes" {
  command = plan

  variables {
    winrm_transport = "kerberos"
  }
}

run "winrm_transport_ntlm_passes" {
  command = plan

  variables {
    winrm_transport = "ntlm"
  }
}

run "winrm_transport_invalid_fails" {
  command = plan

  variables {
    winrm_transport = "ssh"
  }

  expect_failures = [
    var.winrm_transport,
  ]
}
