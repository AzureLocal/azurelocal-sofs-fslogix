# Terraform Deployment

![Terraform](https://img.shields.io/badge/-Terraform-844FBA?logo=terraform&logoColor=white) ![Status: In Progress](https://img.shields.io/badge/status-in_progress-yellow) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

## Overview

Deploys all Azure-side resources for the SOFS guest cluster using Terraform with the `azapi` and `azurerm` providers. Azure Local resource types (`Microsoft.AzureStackHCI/*`) are not fully supported by `azurerm` alone, so the `azapi` provider handles Arc VM, NIC, and data disk creation.

After `terraform apply`, a fully-populated Ansible inventory is auto-generated — feeding directly into the guest configuration phase.

### Capability vs Code Status

| Capability | Can Do? | Current Code |
|-----------|:---:|:---:|
| Azure resource provisioning | ✅ | ✅ Full |
| Domain join (JsonADDomainExtension) | ✅ via azapi | ❌ Not yet implemented |
| Guest OS configuration | Delegates to PS/Ansible | Delegates via `guest_config_engine` |

!!! info "Domain join is a TODO, not a limitation"
    Terraform can deploy the `JsonADDomainExtension` Arc extension using the `azapi` provider. The [aurelocal-avd](https://github.com/AzureLocal/aurelocal-avd) repo has a working example in `src/terraform/session-hosts.tf`. This repo's Terraform code does not implement it yet.

**What happens after Terraform:** Guest OS configuration requires the [PowerShell](powershell.md) script or [Ansible](ansible.md) playbook.

---

## Resources Created

| Resource | Provider | Type |
|----------|----------|------|
| Resource Group | `azurerm` | `azurerm_resource_group` |
| Cloud Witness Storage Account | `azurerm` | `azurerm_storage_account` |
| Arc Machine Placeholders | `azapi` | `Microsoft.HybridCompute/machines` |
| NICs (compute logical network) | `azapi` | `Microsoft.AzureStackHCI/networkInterfaces` |
| Data Disks (S2D pool) | `azapi` | `Microsoft.AzureStackHCI/virtualHardDisks` |
| VM Instances | `azapi` | `Microsoft.AzureStackHCI/virtualMachineInstances` |
| Ansible Inventory File | `local` | `local_sensitive_file` |

---

## Prerequisites

- Terraform >= 1.5
- Azure CLI authenticated (`az login`)
- `azapi` and `azurerm` providers (auto-installed by `terraform init`)
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration (azapi, azurerm, local) |
| `variables.tf` | All input variables |
| `locals.tf` | Computed values — VM names, disk flattening, pool calculations |
| `resource-group.tf` | Resource group |
| `witness.tf` | Cloud witness storage account |
| `sofs.tf` | Arc machines, NICs, data disks, VM instances |
| `ansible-inventory.tf` | Generates Ansible inventory from Terraform outputs |
| `templates/inventory.yml.tftpl` | Ansible inventory template |
| `outputs.tf` | VM IDs, witness key, pool sizing, inventory path |
| `terraform.tfvars.example` | Example variable values |

---

## Setup

### 1. Configure Variables

```powershell
cd src/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with values from your `config/variables.yml`. Key mappings:

| variables.yml | terraform.tfvars |
|--------------|-----------------|
| `azure.subscription_id` | `subscription_id` |
| `azure.resource_group` | `resource_group_name` |
| `azure.location` | `location` |
| `azure_local.custom_location_id` | `custom_location_id` |
| `azure_local.logical_network_id` | `logical_network_id` |
| `azure_local.gallery_image_name` | `gallery_image_id` |
| `azure_local.storage_path_ids` | `storage_path_ids` |
| `vm.prefix` | `vm_prefix` |
| `vm.count` | `vm_count` |
| `vm.processors` | `vm_processors` |
| `vm.memory_mb` | `vm_memory_mb` |
| `vm.ips` | `vm_ips` |
| `data_disks.count` | `data_disk_count` |
| `data_disks.size_gb` | `data_disk_size_gb` |

### 2. Set Secrets Securely

Never put passwords in `terraform.tfvars`. Use environment variables:

```powershell
$env:TF_VAR_admin_password = (az keyvault secret show `
    --vault-name "kv-platform-prod" `
    --name "sofs-vm-admin-password" `
    --query value -o tsv)
```

---

## Deployment

### Recommended: End-to-End Script

The `Deploy-SOFS.ps1` orchestration script runs Terraform (Phase 1) then Ansible (Phase 2) in sequence:

```powershell
.\Deploy-SOFS.ps1 -TfVarsFile .\terraform\terraform.tfvars
```

### Manual: Step-by-Step

```powershell
cd src/terraform

# Initialize providers
terraform init

# Preview changes
terraform plan -var-file="terraform.tfvars"

# Deploy
terraform apply -var-file="terraform.tfvars"
```

### Verify

After apply, check the generated Ansible inventory:

```powershell
# Check for placeholder IPs (need manual update if DHCP)
terraform output ansible_inventory_has_placeholders
```

If `true`, VMs were deployed with DHCP and you need to update the inventory with actual IPs before running guest configuration.

---

## VM IP Addresses

Terraform does not know VM IPs at provision time when Azure Local assigns them via DHCP. Two options:

**Option A — Pre-allocate IPs in tfvars (recommended):**

```hcl
vm_ips = {
  "01" = "192.168.1.201"
  "02" = "192.168.1.202"
  "03" = "192.168.1.203"
}
```

**Option B — Post-provision update:**

After VMs are created, discover IPs and update the generated Ansible inventory manually.

---

## Auto-Generated Ansible Inventory

Terraform writes an Ansible inventory file at `../ansible/inventory-generated.yml` that includes:

- SOFS VM hostnames and IPs
- Cloud witness storage account key (from Terraform output)
- All cluster configuration variables

This eliminates manual inventory creation when using the Terraform → Ansible deployment path.

---

## Post-Deployment

After Terraform completes:

1. **Verify VMs** are running in Azure portal or via `az stack-hci-vm list`
2. **Domain join** the VMs (manual or via Arc extension — not yet automated in this repo's Terraform)
3. **Run guest configuration** using [PowerShell](powershell.md) or [Ansible](ansible.md)

---

## Guest Configuration Engine

Terraform delegates guest OS configuration to either PowerShell or Ansible via the `guest_config_engine` variable:

| Value | Behavior |
|-------|----------|
| `powershell` (default) | After `terraform apply`, run `Configure-SOFS-Cluster.ps1` manually |
| `ansible_create` | Deploy a Linux Ansible controller VM, then run playbooks automatically |
| `ansible_existing` | Use an existing Ansible controller to run playbooks |

When using the Ansible path, Terraform auto-generates `../ansible/inventory-generated.yml` with all values populated from Terraform outputs.

---

## Destroy

To tear down all Azure resources:

```powershell
terraform destroy -var-file="terraform.tfvars"
```

!!! warning
    This destroys the resource group and all resources. Data on the SOFS shares will be lost. The Azure Local host volumes are not managed by Terraform and are unaffected.

---

## Next Steps

- [Ansible](ansible.md) — Guest OS configuration (Phases 3–11) using the auto-generated inventory
- [PowerShell](powershell.md) — Alternative guest configuration via PowerShell remoting
- [Validation](validation.md) — Verify the deployment
