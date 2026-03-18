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
  description = "Number of SOFS VMs — minimum 2 for two-way mirror, 3+ for three-way (wsfc_sofs_vm_count)"
  type        = number
  default     = 3

  validation {
    condition     = var.vm_count >= 2 && var.vm_count <= 16
    error_message = "vm_count must be between 2 and 16."
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
variable "key_vault_secret_domain_join_password" {
  description = "Name of the Key Vault secret holding the domain join account password"
  type        = string
  default     = "domain-join-password"
}

# ---------------------------------------------------------------------------
# Domain Join Configuration
# ---------------------------------------------------------------------------

variable "domain_join_account" {
  description = "Domain join service account username (sAMAccountName, no domain prefix)"
  type        = string
  default     = "svc.domainjoin"
}

variable "domain_ou_nodes" {
  description = "OU path for SOFS VM computer objects in AD"
  type        = string
  default     = ""
}

variable "domain_ou_cluster" {
  description = "OU path for the WSFC cluster name object (CNO) in AD"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Deployment Architecture Choices
# ---------------------------------------------------------------------------

variable "guest_volume_layout" {
  description = "Guest S2D volume layout: option_a (single volume/share) or option_b (three volumes/shares)"
  type        = string
  default     = "option_a"

  validation {
    condition     = contains(["option_a", "option_b"], var.guest_volume_layout)
    error_message = "guest_volume_layout must be option_a or option_b."
  }
}

variable "host_resiliency" {
  description = "Host CSV mirror: two_way or three_way"
  type        = string
  default     = "two_way"

  validation {
    condition     = contains(["two_way", "three_way"], var.host_resiliency)
    error_message = "host_resiliency must be two_way or three_way."
  }
}

variable "guest_resiliency" {
  description = "Guest S2D data copies: two_way (2 copies) or three_way (3 copies)"
  type        = string
  default     = "two_way"

  validation {
    condition     = contains(["two_way", "three_way"], var.guest_resiliency)
    error_message = "guest_resiliency must be two_way or three_way."
  }
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
  description = "FSLogix SMB share name — Option A single share (wsfc_sofs_share_name)"
  type        = string
  default     = "FSLogix"
}

# ---------------------------------------------------------------------------
# Option B: Multiple Shares / Volumes
# ---------------------------------------------------------------------------

variable "sofs_shares" {
  description = "Option B: list of SMB share definitions [{name, volume}] — used when guest_volume_layout = option_b"
  type = list(object({
    name   = string
    volume = string
  }))
  default = []
}

variable "s2d_volumes" {
  description = "Option B: list of S2D volume definitions [{name, size_gb, data_copies}] — used when guest_volume_layout = option_b"
  type = list(object({
    name        = string
    size_gb     = number
    data_copies = number
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Additional SOFS Configuration
# ---------------------------------------------------------------------------

variable "sofs_role_name" {
  description = "SOFS cluster role name for Add-ClusterScaleOutFileServerRole"
  type        = string
  default     = "FSLogixSOFS"
}

variable "s2d_pool_name" {
  description = "S2D storage pool friendly name"
  type        = string
  default     = "S2D on sofs-cluster"
}

variable "smb_encryption" {
  description = "Enable SMB 3.x encryption on SOFS shares"
  type        = bool
  default     = true
}

variable "access_point_ip" {
  description = "Static IP for the SOFS client access point"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Permissions
# ---------------------------------------------------------------------------

variable "permissions_admin_group" {
  description = "AD group for share administrative access"
  type        = string
  default     = "Domain Admins"
}

variable "permissions_users_group" {
  description = "AD group for share user access"
  type        = string
  default     = "AVD-Users"
}

variable "permissions_avd_users_group" {
  description = "AD group for AVD users (FSLogix profile access)"
  type        = string
  default     = "AVD-Users"
}

# ---------------------------------------------------------------------------
# FSLogix
# ---------------------------------------------------------------------------

variable "fslogix_enabled" {
  description = "Whether FSLogix profile containers are enabled on this SOFS cluster"
  type        = bool
  default     = true
}

variable "fslogix_profile_size_mb" {
  description = "Maximum profile container size in MB — used for FSRM quota"
  type        = number
  default     = 30000
}

variable "fslogix_volume_type" {
  description = "Profile container format: VHDX or VHD"
  type        = string
  default     = "VHDX"
}

variable "cloud_cache_enabled" {
  description = "Enable FSLogix Cloud Cache for multi-site DR"
  type        = bool
  default     = false
}

variable "cloud_cache_azure_provider" {
  description = "Azure Blob connection string for Cloud Cache provider"
  type        = string
  default     = ""
  sensitive   = true
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


