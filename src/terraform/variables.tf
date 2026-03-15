# =============================================================================
# SOFS on Azure Local — Terraform Variables
# =============================================================================
# All variables map 1:1 to wsfc_sofs_* entries in master-registry.yaml.
# =============================================================================

# ---------------------------------------------------------------------------
# Azure Location & Subscription
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID for SOFS resources (wsfc_sofs_subscription_id)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name (wsfc_sofs_resource_group)"
  type        = string
}

variable "location" {
  description = "Azure region — must match the Azure Local cluster region (wsfc_sofs_location)"
  type        = string
}

# ---------------------------------------------------------------------------
# Azure Local Infrastructure IDs
# ---------------------------------------------------------------------------

variable "custom_location_id" {
  description = "Full ARM resource ID of the Azure Local custom location (wsfc_sofs_custom_location_id)"
  type        = string
}

variable "logical_network_id" {
  description = "Full ARM resource ID of the compute logical network (wsfc_sofs_logical_network_id)"
  type        = string
}

variable "gallery_image_id" {
  description = "Full ARM resource ID of the Windows Server 2025 gallery image (wsfc_sofs_gallery_image_name)"
  type        = string
}

variable "storage_path_ids" {
  description = "Map of VM suffix (01, 02, 03) to Azure Local storage path ARM ID — spreads VMs across storage paths (wsfc_sofs_storage_path_ids)"
  type        = map(string)
  # Example: { "01" = "/subscriptions/.../sp-01", "02" = "/subscriptions/.../sp-02", "03" = "/subscriptions/.../sp-03" }
}

# ---------------------------------------------------------------------------
# VM Configuration
# ---------------------------------------------------------------------------

variable "vm_count" {
  description = "Number of SOFS VMs — minimum 3 for S2D two-way mirror (wsfc_sofs_vm_count)"
  type        = number
  default     = 3

  validation {
    condition     = var.vm_count >= 3
    error_message = "SOFS requires at least 3 VMs for a two-way mirror."
  }
}

variable "vm_prefix" {
  description = "VM naming prefix — VMs named {prefix}-01, {prefix}-02, etc. (wsfc_sofs_vm_prefix)"
  type        = string
  default     = "SOFS"

  validation {
    condition     = length(var.vm_prefix) <= 11
    error_message = "VM prefix must be 11 characters or fewer (Windows NetBIOS limit with suffix)."
  }
}

variable "vm_processors" {
  description = "Number of vCPUs per SOFS VM (wsfc_sofs_vm_processors)"
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Memory in MB per SOFS VM (wsfc_sofs_vm_memory_mb)"
  type        = number
  default     = 8192
}

variable "admin_username" {
  description = "Local administrator username for the SOFS VMs (wsfc_sofs_vm_admin_username)"
  type        = string
  default     = "LocalAdmin"
}

# admin_password is resolved directly from Key Vault by keyvault.tf — no TF_VAR needed.

variable "key_vault_name" {
  description = "Key Vault name containing the SOFS VM admin password secret (e.g. kv-platform-prod)"
  type        = string
}

variable "key_vault_secret_admin_password" {
  description = "Name of the Key Vault secret holding the VM admin password"
  type        = string
  default     = "sofs-vm-admin-password"
}

# SSH public key — read directly from disk; wrapper does not need to set TF_VAR.
variable "ssh_public_key_path" {
  description = "Path to SSH public key file for Ansible controller VM"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# ---------------------------------------------------------------------------
# Data Disk Configuration
# ---------------------------------------------------------------------------

variable "data_disk_count" {
  description = "Number of data disks per VM for S2D pool (wsfc_sofs_data_disk_count)"
  type        = number
  default     = 4
}

variable "data_disk_size_gb" {
  description = "Size of each data disk in GB — dynamic provisioning (wsfc_sofs_data_disk_size_gb)"
  type        = number
  default     = 1024
}

# ---------------------------------------------------------------------------
# Cloud Witness
# ---------------------------------------------------------------------------

variable "cloud_witness_name" {
  description = "Cloud witness storage account name — max 24 chars, globally unique (wsfc_sofs_cloud_witness_name)"
  type        = string

  validation {
    condition     = length(var.cloud_witness_name) <= 24 && can(regex("^[a-z0-9]+$", var.cloud_witness_name))
    error_message = "Storage account name must be <= 24 lowercase alphanumeric characters."
  }
}

# ---------------------------------------------------------------------------
# Phase 2: Guest Config Engine
# ---------------------------------------------------------------------------
# Controls how SOFS guest OS configuration is executed after Terraform.
#   powershell       — Run Configure-SOFS-Cluster.ps1 via PSRemoting from Windows
#   ansible_create   — Deploy a new Linux controller VM in Azure, then SSH + ansible
#   ansible_existing — Use an existing Linux controller VM, then SSH + ansible
# ---------------------------------------------------------------------------

variable "guest_config_engine" {
  description = "Phase 2 engine: powershell (PSRemoting), ansible_create (new Linux VM), ansible_existing (reuse existing VM) (wsfc_sofs_guest_config_engine)"
  type        = string
  default     = "powershell"

  validation {
    condition     = contains(["powershell", "ansible_create", "ansible_existing"], var.guest_config_engine)
    error_message = "guest_config_engine must be powershell, ansible_create, or ansible_existing."
  }
}

# ---------------------------------------------------------------------------
# Ansible Controller VM — only when guest_config_engine = "ansible_create"
# ---------------------------------------------------------------------------

variable "ansible_controller_name" {
  description = "Name of the Ansible controller VM (wsfc_sofs_ansible_controller_name)"
  type        = string
  default     = "vm-ansible-sofs-eus-01"
}

variable "ansible_controller_size" {
  description = "Azure VM size for the Ansible controller (wsfc_sofs_ansible_controller_size)"
  type        = string
  default     = "Standard_B2s"
}

variable "ansible_controller_admin_username" {
  description = "Linux admin username for the Ansible controller VM (wsfc_sofs_ansible_controller_admin_username)"
  type        = string
  default     = "ansibleadmin"
}

variable "ansible_controller_ssh_public_key" {
  description = "SSH public key for the controller VM — falls back to ssh_public_key_path file if empty"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ansible_controller_hub_subnet_id" {
  description = "Full ARM resource ID of the hub subnet for the controller VM (wsfc_sofs_ansible_controller_hub_subnet_id)"
  type        = string
  default     = ""
}

variable "ansible_controller_hub_rg" {
  description = "Resource group containing the hub VNet (wsfc_sofs_ansible_controller_hub_rg)"
  type        = string
  default     = ""
}

variable "ansible_controller_private_ip" {
  description = "Static private IP for the Ansible controller VM in the hub management subnet"
  type        = string
  default     = "10.250.1.41"
}

# ---------------------------------------------------------------------------
# Ansible Controller — only when guest_config_engine = "ansible_existing"
# ---------------------------------------------------------------------------

variable "ansible_existing_controller_ip" {
  description = "Private IP of an existing Ansible controller VM (wsfc_sofs_ansible_existing_controller_ip)"
  type        = string
  default     = ""
}

variable "ansible_existing_controller_user" {
  description = "SSH username on the existing Ansible controller (wsfc_sofs_ansible_existing_controller_user)"
  type        = string
  default     = "ansibleadmin"
}

# ---------------------------------------------------------------------------
# Guest Cluster Configuration (consumed by generated Ansible inventory)
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Windows Failover Cluster name for the SOFS guest cluster (wsfc_sofs_cluster_name)"
  type        = string
  default     = "SOFS-Cluster"
}

variable "cluster_ip" {
  description = "Static IP for the cluster name object (wsfc_sofs_cluster_ip)"
  type        = string
}

variable "access_point" {
  description = "Scale-Out File Server access point name (wsfc_sofs_access_point)"
  type        = string
  default     = "FSLogixSOFS"
}

variable "share_name" {
  description = "FSLogix SMB share name (wsfc_sofs_share_name)"
  type        = string
  default     = "FSLogix"
}

variable "s2d_volume_name" {
  description = "Friendly name for the S2D CSV volume (wsfc_sofs_s2d_volume_name)"
  type        = string
  default     = "FSLogixData"
}

variable "s2d_volume_size" {
  description = "S2D volume size as a string (e.g. '5632GB') (wsfc_sofs_s2d_volume_size)"
  type        = string
  default     = "5632GB"
}

variable "s2d_data_copies" {
  description = "Number of S2D mirror data copies — 2 for two-way, 3 for three-way (wsfc_sofs_s2d_data_copies)"
  type        = number
  default     = 2
}

variable "domain_fqdn" {
  description = "Active Directory domain FQDN — VMs must be joined before Ansible runs (wsfc_sofs_domain_fqdn)"
  type        = string
}

variable "domain_netbios" {
  description = "Active Directory NetBIOS domain name (wsfc_sofs_domain_netbios)"
  type        = string
}

variable "anti_affinity_rule" {
  description = "Azure Local anti-affinity rule name to keep SOFS VMs on separate hosts (wsfc_sofs_anti_affinity_rule)"
  type        = string
  default     = "SOFS-AntiAffinity"
}

variable "azl_cluster_name" {
  description = "Azure Local host cluster name (wsfc_sofs_azl_cluster_name)"
  type        = string
}

variable "vm_ips" {
  description = "Map of VM name suffix (01, 02, 03) to static IP — must be free IPs within the assigned logical network (wsfc_sofs_vm_ips)"
  type        = map(string)
  default     = {}
  # Example: { "01" = "192.168.220.201", "02" = "192.168.220.202", "03" = "192.168.220.203" }
}

variable "dns_servers" {
  description = "DNS server IP addresses for SOFS guest cluster VMs — used in Ansible inventory for in-guest WSFC/AD configuration (wsfc_sofs_dns_servers)"
  type        = list(string)
  default     = []
}

variable "winrm_transport" {
  description = "WinRM transport for Ansible: kerberos (domain-joined) or ntlm (workgroup/pre-domain)"
  type        = string
  default     = "kerberos"

  validation {
    condition     = contains(["kerberos", "ntlm", "basic"], var.winrm_transport)
    error_message = "winrm_transport must be kerberos, ntlm, or basic."
  }
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Resource tags applied to all resources"
  type        = map(string)
  default = {
    project  = "SOFS"
    workload = "FSLogix"
    solution = "sofs-azure-local"
  }
}


