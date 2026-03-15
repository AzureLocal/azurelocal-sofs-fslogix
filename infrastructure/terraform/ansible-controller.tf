# =============================================================================
# SOFS on Azure Local — Ansible Controller VM
# =============================================================================
# Conditional Linux VM deployed into the hub management subnet.
# Only created when guest_config_engine = "ansible_create".
# Used as the Ansible control node to configure SOFS guest VMs via WinRM —
# Ansible cannot run natively on Windows.
#
# Cloud-init installs: ansible, pywinrm, requests-kerberos, ansible.windows
# =============================================================================

# ---------------------------------------------------------------------------
# NIC in hub management subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_interface" "ansible_controller" {
  count = var.guest_config_engine == "ansible_create" ? 1 : 0

  name                = "${var.ansible_controller_name}-nic"
  location            = var.location
  resource_group_name = var.ansible_controller_hub_rg
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.ansible_controller_hub_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ansible_controller_private_ip
  }
}

# ---------------------------------------------------------------------------
# Linux VM
# ---------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "ansible_controller" {
  count = var.guest_config_engine == "ansible_create" ? 1 : 0

  name                = var.ansible_controller_name
  computer_name       = replace(var.ansible_controller_name, "vm-", "")
  location            = var.location
  resource_group_name = var.ansible_controller_hub_rg
  size                = var.ansible_controller_size
  admin_username      = var.ansible_controller_admin_username
  tags                = var.tags

  network_interface_ids = [
    azurerm_network_interface.ansible_controller[0].id
  ]

  admin_ssh_key {
    username   = var.ansible_controller_admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    name                 = "${var.ansible_controller_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Cloud-init: install Ansible + WinRM deps, write inventory + playbook, run playbook
  custom_data = base64encode(templatefile("${path.module}/templates/cloud-init.yml.tftpl", {
    admin_username = var.ansible_controller_admin_username
    inventory_b64  = base64encode(local_sensitive_file.ansible_inventory.content)
    playbook_b64   = base64encode(file("${path.module}/../ansible/configure-sofs-cluster.yml"))
  }))

  disable_password_authentication = true
}
