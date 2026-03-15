# SOFS on Azure Local — Terraform Deployment

![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen)

## Overview

Deploys all Azure-side resources for the SOFS guest cluster using Terraform with the `azapi` provider (Azure Local `Microsoft.AzureStackHCI/*` resource types are not yet supported by `azurerm`).

After `terraform apply`, a fully-populated Ansible inventory is auto-generated at `../ansible/inventory-generated.yml` — including the cloud witness storage key from Terraform output. This feeds directly into the Ansible guest configuration phase.

> **Recommended**: Use the orchestration script at `../Deploy-SOFS.ps1` to run both phases end-to-end.

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

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider configuration (azapi, azurerm, local) |
| `variables.tf` | All input variables — Azure resources and guest cluster config |
| `locals.tf` | Computed values — VM names, disk flattening, pool calculations, Ansible host list |
| `resource-group.tf` | Resource group |
| `witness.tf` | Cloud witness storage account |
| `sofs.tf` | Arc machines, NICs, data disks, VM instances |
| `ansible-inventory.tf` | Generates `../ansible/inventory-generated.yml` from TF outputs |
| `templates/inventory.yml.tftpl` | Ansible inventory template |
| `outputs.tf` | VM IDs, witness key, pool sizing, inventory path |
| `terraform.tfvars.example` | Example variable values |

## Recommended: End-to-End Deployment

```powershell
# From solutions/sofs/
.\Deploy-SOFS.ps1 -TfVarsFile .\terraform\terraform.tfvars
```

This runs Terraform (Phase 1) then Ansible (Phase 2) in sequence, handling credential prompts and inventory validation automatically.

## Manual Usage

### Phase 1 — Terraform (Azure Resources)

```bash
cd solutions/sofs/terraform

# Initialize
terraform init

# Pass admin password securely (never put it in tfvars)
export TF_VAR_admin_password="$(az keyvault secret show --vault-name kv-sofs --name sofs-vm-admin-password --query value -o tsv)"

# Plan
terraform plan -var-file="terraform.tfvars"

# Apply
terraform apply -var-file="terraform.tfvars"
```

After apply, check the generated inventory:

```bash
# Verify no FILL_IN_IP placeholders remain
terraform output ansible_inventory_has_placeholders

# If true: add vm_ips to terraform.tfvars and re-apply, or manually edit:
#   ../ansible/inventory-generated.yml
```

### Phase 2 — Ansible (Guest OS Configuration)

After VMs are domain-joined:

```bash
cd solutions/sofs

ansible-playbook \
  -i ansible/inventory-generated.yml \
  ansible/configure-sofs-cluster.yml \
  --extra-vars "ansible_user=DOMAIN\svc-ansible ansible_password=<password>"
```

## VM IP Addresses

Terraform does not know VM IPs at provision time (assigned by Azure Local). Two options:

**Option A — Pre-allocate IPs in tfvars** (recommended):
```hcl
vm_ips = {
  "01" = "192.168.211.51"
  "02" = "192.168.211.52"
  "03" = "192.168.211.53"
}
```

**Option B — Fill in after deploy**:
Leave `vm_ips = {}`. Terraform writes `FILL_IN_IP` placeholders. Edit `../ansible/inventory-generated.yml` before running Ansible.

## Variable Mapping

All variables correspond to `wsfc_sofs_*` entries in `configs/variables/assets/master-registry.yaml`. The `terraform.tfvars.example` file shows the mapping.

## Security

The generated Ansible inventory (`../ansible/inventory-generated.yml`) contains the cloud witness storage key. It is:
- Written as a `local_sensitive_file` (not shown in `terraform show` output)
- Excluded from git via `.gitignore`
- Never committed to source control

## References

- [End-to-end orchestration](../Deploy-SOFS.ps1) — Terraform + Ansible in one script
- [Ansible deployment](../ansible/) — Playbooks and inventory
- [Bicep deployment](../bicep/) — Subscription-scope Bicep wrapper + module
- [PowerShell scripts](../powershell/) — Azure CLI deploy + guest OS configuration
- [SOFS Deployment Guide](../SOFS-Deployment-Guide.md)
