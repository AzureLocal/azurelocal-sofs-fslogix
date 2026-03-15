# SOFS on Azure Local — Scale-Out File Server for FSLogix Profiles

## Overview

Deploys a 3-node Windows Server 2025 Datacenter guest cluster running Storage Spaces Direct (S2D) with the Scale-Out File Server (SOFS) role on an Azure Local cluster. Provides continuously available SMB shares for FSLogix profile containers used by Azure Virtual Desktop session hosts.

## Architecture

```
AVD Session Hosts → \\FSLogixSOFS\FSLogix → SOFS Role (active on all 3 nodes)
                                                  ↓
                                          S2D Storage Pool
                                     (two-way mirror across 3 VMs)
                                                  ↓
                              Azure Local CSV Volume "SOFS-Storage"
                                       (two-way mirror)
```

## Two-Phase Deployment Model

Every SOFS deployment runs in two phases:

| Phase | What | Tools |
|-------|------|-------|
| **Phase 1 — Azure Resources** | Resource group, Arc VMs, NICs, data disks, cloud witness storage | Terraform (`azapi` + `azurerm`) |
| **Phase 2 — Guest OS Config** | Failover Clustering, S2D pool, SOFS role, SMB share, NTFS permissions | Configurable (see below) |

Phase 2 cannot run until the VMs are domain-joined and reachable via WinRM. The orchestrator script `Deploy-SOFS.ps1` manages both phases and provides a domain-join gate between them.

---

## Deployment Types (`guest_config_engine`)

The Terraform variable `guest_config_engine` controls how Phase 2 (guest OS configuration) is executed. Three modes are available:

### Mode 1: `powershell` (Default)

> **Best for:** Windows-only environments, quick deployment, no Linux VM required.

```
┌────────────────────────┐     Phase 1      ┌────────────────────────┐
│  Windows Workstation   │ ───────────────── │  Azure Local VMs       │
│  (your machine)        │  Terraform apply  │  (SOFS-01, 02, 03)    │
│                        │                   │                        │
│  Deploy-SOFS.ps1       │     Phase 2       │  WinRM (PSRemoting)    │
│  Configure-SOFS-       │ ─────────────────▶│  ├ Failover Clustering │
│   Cluster.ps1          │  PSRemoting       │  ├ S2D Pool            │
│                        │                   │  ├ SOFS Role           │
└────────────────────────┘                   │  └ SMB Share           │
                                             └────────────────────────┘
```

- Runs `Configure-SOFS-Cluster.ps1` directly from your Windows workstation via PSRemoting.
- No additional VMs required — no Linux controller, no SSH.
- Requires WinRM/Kerberos connectivity from your workstation to the SOFS VMs.
- VM admin credentials are prompted interactively or passed via `-WinRMUsername` / `-WinRMPassword`.

**When to use:** Standard deployments where the operator has direct WinRM access to the Azure Local tenant VLAN.

### Mode 2: `ansible_create`

> **Best for:** Automated/repeatable deployments where no Ansible controller exists yet.

```
┌────────────────────────┐     Phase 1     ┌─────────────────────────┐
│  Windows Workstation   │ ──────────────  │  Azure Local VMs        │
│  (your machine)        │  Terraform      │  (SOFS-01, 02, 03)     │
│                        │  apply          │                         │
│  Deploy-SOFS.ps1       │                 │                         │
└───────────┬────────────┘                 └─────────────┬───────────┘
            │ Phase 1 also deploys:                      │
            ▼                                            │
┌────────────────────────┐      Phase 2                  │
│  Ansible Controller VM │ ─────────────────────────────▶│
│  (Ubuntu 24.04 in      │  SSH → ansible-playbook       │
│   Azure hub subnet)    │  → WinRM to SOFS VMs          │
│                        │                               │
│  Cloud-init installs:  │  Configures:                  │
│  ├ ansible-core        │  ├ Failover Clustering        │
│  ├ pywinrm             │  ├ S2D Pool                   │
│  ├ requests-kerberos   │  ├ SOFS Role                  │
│  └ ansible.windows     │  └ SMB Share                  │
└────────────────────────┘                               │
                                             ┌───────────┘
```

- Terraform deploys a new Ubuntu 24.04 LTS VM in the Azure hub management subnet alongside the SOFS resources.
- Cloud-init auto-installs Ansible, pywinrm, kerberos libraries, and the `ansible.windows` collection.
- `Deploy-SOFS.ps1` waits for cloud-init completion, then SCPs the generated inventory + playbook to the controller, then runs `ansible-playbook` via SSH.
- Requires: SSH key pair (`~/.ssh/id_rsa` or `TF_VAR_ansible_controller_ssh_public_key`).
- Controller VM is deployed into the hub subnet with S2S VPN routing to the Azure Local tenant VLAN.

**When to use:** First-time deployment, no existing Linux VM available, or you want a purpose-built disposable controller.

**Terraform resources created (in addition to SOFS VMs):**
- `azurerm_network_interface.ansible_controller` — NIC in hub mgmt subnet
- `azurerm_linux_virtual_machine.ansible_controller` — Ubuntu 24.04, Standard_B2s

### Mode 3: `ansible_existing`

> **Best for:** Environments with a shared Ansible controller already deployed (e.g., a jump box or automation VM).

```
┌────────────────────────┐     Phase 1     ┌─────────────────────────┐
│  Windows Workstation   │ ──────────────  │  Azure Local VMs        │
│  (your machine)        │  Terraform      │  (SOFS-01, 02, 03)     │
│                        │  apply          │                         │
│  Deploy-SOFS.ps1       │                 │                         │
└───────────┬────────────┘                 └─────────────┬───────────┘
            │                                            │
            │ Phase 2 (SSH)                              │
            ▼                                            │
┌────────────────────────┐      WinRM                    │
│  Existing Linux VM     │ ─────────────────────────────▶│
│  (pre-configured)      │  ansible-playbook             │
│                        │  → WinRM to SOFS VMs          │
│  Ansible + pywinrm     │                               │
│  already installed     │  Configures:                  │
│                        │  ├ Failover Clustering        │
│                        │  ├ S2D Pool                   │
│                        │  ├ SOFS Role                  │
│                        │  └ SMB Share                  │
└────────────────────────┘                               │
                                             ┌───────────┘
```

- No new VM is deployed — Terraform only creates the SOFS Azure resources.
- `Deploy-SOFS.ps1` uses SSH to connect to the existing controller, SCPs the generated inventory + playbook, and runs `ansible-playbook`.
- The existing VM must already have Ansible, pywinrm, and `ansible.windows` installed.
- Requires: `ansible_existing_controller_ip` and `ansible_existing_controller_user` in tfvars.

**When to use:** Shared automation infrastructure already exists; you don't want Terraform managing the controller lifecycle.

### Mode Comparison

| Capability | `powershell` | `ansible_create` | `ansible_existing` |
|------------|:------------:|:----------------:|:------------------:|
| Linux VM required | No | Auto-deployed | Pre-existing |
| Extra Terraform resources | 0 | 2 (NIC + VM) | 0 |
| SSH key required | No | Yes | Yes |
| WinRM from workstation | Yes | No (from controller) | No (from controller) |
| Idempotent | Partial | Yes (Ansible) | Yes (Ansible) |
| Check/dry-run mode | `-WhatIf` | `--check` | `--check` |
| Config tool on workstation | PowerShell 7 | ssh, scp | ssh, scp |
| Kerberos auth | Via PSRemoting | Via pywinrm | Via pywinrm |

---

## Solution Directory Structure

```
solutions/sofs/
├── Deploy-SOFS.ps1                        # Orchestrator — runs Phase 1 + Phase 2
├── README.md                              # This file
├── SOFS-Deployment-Guide.md               # Detailed step-by-step guide
├── solution-sofs.yml                      # Generated solution config
│
├── terraform/                             # Phase 1: Azure resources
│   ├── main.tf                            # Provider config (azapi, azurerm, local, tls)
│   ├── variables.tf                       # All input variables (wsfc_sofs_* mapping)
│   ├── locals.tf                          # Computed values (VM names, disk maps, pool math)
│   ├── resource-group.tf                  # SOFS resource group
│   ├── sofs.tf                            # Arc machines, NICs, data disks, VM instances
│   ├── witness.tf                         # Cloud witness storage account
│   ├── ansible-inventory.tf               # Generates ansible/inventory-generated.yml
│   ├── ansible-controller.tf              # Conditional Linux VM (ansible_create only)
│   ├── outputs.tf                         # VM IDs, witness key, controller IP, engine type
│   ├── templates/
│   │   ├── inventory.yml.tftpl            # Ansible inventory template
│   │   └── cloud-init.yml.tftpl           # Controller VM cloud-init (Ubuntu)
│   ├── terraform.tfvars.example           # Example values (Infinite Improbability Corp)
│   └── terraform.tfvars                   # Real environment values (gitignored)
│
├── ansible/                               # Phase 2: Guest config (Ansible path)
│   ├── configure-sofs-cluster.yml         # Main playbook — clustering, S2D, SOFS, shares
│   ├── deploy-azure-resources.yml         # Standalone Azure resource playbook (az CLI)
│   ├── inventory.yml                      # Example static inventory
│   └── inventory-generated.yml            # Auto-generated by Terraform (gitignored)
│
├── powershell/                            # Phase 2: Guest config (PowerShell path)
│   ├── Configure-SOFS-Cluster.ps1         # PSRemoting-based cluster configuration
│   └── Deploy-SOFS-Azure.ps1              # Standalone Azure resource deployment (az CLI)
│
└── bicep/                                 # Alternative Phase 1: Bicep ARM templates
    ├── Deploy-SOFS-Azure.ps1              # Bicep deployment wrapper script
    ├── main.bicep                         # Subscription-scope entry point
    ├── main.bicepparam                    # Bicep parameters file
    ├── sofs-resources.bicep               # VM + NIC + disk resources module
    └── witness-storage.bicep              # Cloud witness storage module
```

---

## Quick Start

### Option A: Orchestrated deployment (recommended)

The `Deploy-SOFS.ps1` script handles both phases end-to-end:

```powershell
# 1. Copy and fill in terraform.tfvars
cp solutions/sofs/terraform/terraform.tfvars.example solutions/sofs/terraform/terraform.tfvars
# Edit terraform.tfvars with your environment values

# 2. Set admin password (or let the script prompt you)
$env:TF_VAR_admin_password = (az keyvault secret show --vault-name kv-platform --name sofs-vm-admin-password --query value -o tsv)

# 3. Dry run (WhatIf)
.\solutions\sofs\Deploy-SOFS.ps1 -WhatIf

# 4. Full deploy
.\solutions\sofs\Deploy-SOFS.ps1
```

#### Engine-specific examples

```powershell
# PowerShell mode (default) — simplest, no SSH required
.\solutions\sofs\Deploy-SOFS.ps1 -WhatIf

# Ansible with new controller — also provide SSH key
$env:TF_VAR_ansible_controller_ssh_public_key = (Get-Content ~/.ssh/id_rsa.pub)
.\solutions\sofs\Deploy-SOFS.ps1 -WhatIf

# Ansible with existing controller — no extra infra
.\solutions\sofs\Deploy-SOFS.ps1 -WhatIf

# Phase 1 only (Terraform) — skip guest config
.\solutions\sofs\Deploy-SOFS.ps1 -SkipPhase2

# Phase 2 only (guest config) — Terraform already applied
.\solutions\sofs\Deploy-SOFS.ps1 -SkipPhase1
```

### Option B: Manual step-by-step

#### Phase 1 — Terraform

```powershell
cd solutions/sofs/terraform
terraform init
terraform plan -var-file="terraform.tfvars"     # Review the plan
terraform apply -var-file="terraform.tfvars"     # Deploy
```

#### Phase 2 — PowerShell (manual)

```powershell
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1 -WhatIf
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1
```

#### Phase 2 — Ansible (manual, from Linux controller)

```bash
cd ~/sofs
ansible-playbook -i inventory.yml configure-sofs-cluster.yml --check   # dry run
ansible-playbook -i inventory.yml configure-sofs-cluster.yml           # apply
```

### Option C: Standalone methods (no orchestrator)

| Method | Phase 1 Command | Phase 2 Command |
|--------|----------------|-----------------|
| **Bicep** | `.\solutions\sofs\bicep\Deploy-SOFS-Azure.ps1` | Use PowerShell or Ansible |
| **PowerShell (Azure CLI)** | `.\solutions\sofs\powershell\Deploy-SOFS-Azure.ps1` | `.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1` |
| **Ansible only** | `ansible-playbook deploy-azure-resources.yml` | `ansible-playbook configure-sofs-cluster.yml` |

---

## Configuration

### Variable sources

All values flow from the master registry through environment config into Terraform:

```
master-registry.yaml (schema)
        ↓
configs/infrastructure-<env>.yml (values)
        ↓
terraform/terraform.tfvars (Terraform input)
        ↓
terraform outputs → Deploy-SOFS.ps1 (runtime orchestration)
```

### Key Variables

| Terraform Variable | Registry Path | Description | Default |
|-------------------|---------------|-------------|---------|
| `vm_count` | `wsfc_sofs_vm_count` | Number of SOFS VMs | `3` |
| `vm_prefix` | `wsfc_sofs_vm_prefix` | VM naming prefix | `SOFS` |
| `vm_processors` | `wsfc_sofs_vm_processors` | vCPUs per VM | `4` |
| `vm_memory_mb` | `wsfc_sofs_vm_memory_mb` | RAM in MB per VM | `8192` |
| `data_disk_count` | `wsfc_sofs_data_disk_count` | Data disks per VM | `4` |
| `data_disk_size_gb` | `wsfc_sofs_data_disk_size_gb` | Size per data disk | `1024` |
| `cluster_name` | `wsfc_sofs_cluster_name` | Failover cluster name | `SOFS-Cluster` |
| `cluster_ip` | `wsfc_sofs_cluster_ip` | Cluster static IP | — |
| `access_point` | `wsfc_sofs_access_point` | SOFS access point name | `FSLogixSOFS` |
| `share_name` | `wsfc_sofs_share_name` | SMB share name | `FSLogix` |
| `s2d_volume_name` | `wsfc_sofs_s2d_volume_name` | S2D CSV volume name | `FSLogixData` |
| `s2d_volume_size` | `wsfc_sofs_s2d_volume_size` | S2D volume size | `5632GB` |
| `s2d_data_copies` | `wsfc_sofs_s2d_data_copies` | Mirror copies | `2` |
| `cloud_witness_name` | `wsfc_sofs_cloud_witness_name` | Witness storage account | — |
| `guest_config_engine` | `wsfc_sofs_guest_config_engine` | Phase 2 engine | `powershell` |

### Phase 2 Engine Variables

| Variable | Required When | Description |
|----------|--------------|-------------|
| `guest_config_engine` | Always | `powershell`, `ansible_create`, or `ansible_existing` |
| `ansible_controller_name` | `ansible_create` | Controller VM name |
| `ansible_controller_size` | `ansible_create` | Azure VM size (default: `Standard_B2s`) |
| `ansible_controller_admin_username` | `ansible_create` | Linux admin user (default: `ansibleadmin`) |
| `ansible_controller_ssh_public_key` | `ansible_create` | SSH public key (set via `TF_VAR_*` env var) |
| `ansible_controller_hub_subnet_id` | `ansible_create` | Hub subnet ARM resource ID |
| `ansible_controller_hub_rg` | `ansible_create` | Hub resource group name |
| `ansible_existing_controller_ip` | `ansible_existing` | Private IP of existing controller |
| `ansible_existing_controller_user` | `ansible_existing` | SSH username on existing controller |

---

## Deploy-SOFS.ps1 Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-TfVarsFile` | `string` | Path to `terraform.tfvars` (default: `.\terraform\terraform.tfvars`) |
| `-AdminPassword` | `string` | SOFS VM admin password (or set `TF_VAR_admin_password`) |
| `-SshKeyPath` | `string` | SSH private key path (default: `~/.ssh/id_rsa`) |
| `-WinRMUsername` | `string` | WinRM / PSRemoting username for Phase 2 |
| `-WinRMPassword` | `string` | WinRM / PSRemoting password for Phase 2 |
| `-SkipPhase1` | `switch` | Skip Terraform (Azure resources already exist) |
| `-SkipPhase2` | `switch` | Skip guest config (deploy Azure resources only) |
| `-WhatIf` | `switch` | Dry-run: `terraform plan` + `--check` / `-WhatIf` |

---

## Terraform Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | SOFS resource group name |
| `resource_group_id` | SOFS resource group ARM ID |
| `deployed_vms` | Map of VM names → Arc machine ID + NIC ID |
| `total_data_disks` | Total data disks deployed |
| `s2d_pool_size_gb` | Raw S2D pool size in GB |
| `cloud_witness_storage_account_name` | Witness storage account name |
| `cloud_witness_storage_account_key` | Witness storage account key (sensitive) |
| `ansible_inventory_path` | Path to generated inventory file |
| `ansible_inventory_has_placeholders` | `true` if any VMs still have `FILL_IN_IP` |
| `guest_config_engine` | Selected Phase 2 engine |
| `ansible_controller_private_ip` | Controller IP (created or existing, `null` for powershell) |
| `ansible_controller_id` | Controller VM ARM ID (`ansible_create` only) |
| `ansible_controller_admin_username` | Controller SSH username |

---

## Prerequisites

### All modes

- Azure Local cluster with ≥3 physical nodes
- ~25 TB raw physical capacity available
- Windows Server 2025 Datacenter gallery image registered in the Azure Local marketplace
- Active Directory domain environment with DNS
- Key Vault with SOFS VM admin credentials (`sofs-vm-admin-username`, `sofs-vm-admin-password`)
- Azure CLI (`az`) authenticated to the target subscription
- Terraform ≥ 1.0

### PowerShell mode (`powershell`)

- PowerShell 7.0+
- WinRM/PSRemoting access from your workstation to SOFS VMs
- Kerberos authentication configured (workstation domain-joined or `runas /netonly`)

### Ansible create mode (`ansible_create`)

- OpenSSH client on Windows (`ssh`, `scp`)
- SSH key pair — public key at `~/.ssh/id_rsa.pub` or set `TF_VAR_ansible_controller_ssh_public_key`
- Hub management subnet with S2S VPN route to Azure Local tenant VLAN
- The controller needs outbound internet during cloud-init (to install packages)

### Ansible existing mode (`ansible_existing`)

- OpenSSH client on Windows (`ssh`, `scp`)
- SSH key pair with access to the existing controller VM
- The existing controller must have: `ansible-core`, `pywinrm`, `requests-kerberos`, `ansible.windows` collection
- Network route from existing controller to SOFS VMs (WinRM port 5985/5986)

---

## Guest Config: What Phase 2 Does

Both the PowerShell and Ansible Phase 2 paths perform the same operations:

1. **Install roles & features** — `Failover-Clustering`, `FS-FileServer`, `RSAT-Clustering-PowerShell`
2. **Validate cluster** — `Test-Cluster` on all nodes
3. **Create failover cluster** — `New-Cluster` with cluster name + static IP
4. **Configure cloud witness** — `Set-ClusterQuorum` with Azure storage account + key
5. **Enable S2D** — `Enable-ClusterS2D` (auto-claims all raw data disks)
6. **Create S2D volume** — `New-Volume` with two-way mirror, specified size
7. **Add SOFS role** — `Add-ClusterScaleOutFileServerRole` with access point name
8. **Create SMB share** — `New-SmbShare` on the CSV volume
9. **Set NTFS permissions** — Configure share + NTFS ACLs for FSLogix
10. **Set anti-affinity rule** — Keeps SOFS VMs on separate physical hosts
11. **Validate** — Verify cluster health, volume status, share accessibility

---

## Example tfvars

See [terraform/terraform.tfvars.example](terraform/terraform.tfvars.example) for a complete example using the fictional "Infinite Improbability Corp" company.

```hcl
# Core
guest_config_engine = "powershell"    # or "ansible_create" or "ansible_existing"
vm_count            = 3
vm_prefix           = "IIC-SOFS"
cluster_name        = "SOFS-Cluster"
cluster_ip          = "192.168.211.60"
share_name          = "FSLogix"

# Ansible create mode — uncomment these:
# guest_config_engine               = "ansible_create"
# ansible_controller_name           = "vm-ansible-sofs-eus-01"
# ansible_controller_hub_rg         = "rg-hub-eus-01"
# ansible_controller_hub_subnet_id  = "/subscriptions/.../subnets/snet-mgmt"

# Ansible existing mode — uncomment these:
# guest_config_engine               = "ansible_existing"
# ansible_existing_controller_ip    = "10.250.1.50"
# ansible_existing_controller_user  = "ansibleadmin"
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `terraform plan` fails on `admin_password` | Password not set | Set `TF_VAR_admin_password` env var or pass `-AdminPassword` |
| `FILL_IN_IP` in inventory | `vm_ips` not set in tfvars | Add `vm_ips` map, re-run `terraform apply` |
| Ansible fails on Windows | Ansible control node requires Linux | Set `guest_config_engine = "ansible_create"` or `"ansible_existing"` |
| Cloud-init timeout | Controller didn't finish setup in 5 min | SSH to controller, check `/var/log/cloud-init-output.log` |
| WinRM connection refused | VMs not domain-joined or firewall | Ensure domain join complete, WinRM enabled, ports 5985/5986 open |
| Kerberos auth failure | Clock skew or missing SPN | Verify NTP sync, check `setspn -L` on VMs |
| SSH key rejected | Wrong key or not in `authorized_keys` | Verify `TF_VAR_ansible_controller_ssh_public_key` matches private key |

---

*Maintained by the ProdTech team — Hybrid Cloud Solutions. See the full [SOFS Deployment Guide](SOFS-Deployment-Guide.md) for detailed walkthroughs.*
