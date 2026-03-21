# PowerShell Deployment

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d) ![CI/CD: Examples Available](https://img.shields.io/badge/CI%2FCD-examples_available-blueviolet?logo=githubactions&logoColor=white)

## Overview

PowerShell is the **only tool that covers the entire deployment end-to-end** — both Azure resource provisioning and guest OS configuration — without requiring a second tool.

Two main scripts:

| Script | Domain | Description |
|--------|--------|-------------|
| `Deploy-SOFS-Azure.ps1` | Azure-side | Azure CLI wrapper — creates resource group, cloud witness, NICs, VMs, data disks, domain join extension |
| `Configure-SOFS-Cluster.ps1` | Guest OS | WinRM/PSRemoting — anti-affinity, clustering, S2D, SOFS, shares, permissions, validation |

### Capability

| Capability | Supported |
|-----------|:---------:|
| Azure resource provisioning | ✅ |
| Domain join (JsonADDomainExtension) | ✅ |
| Guest OS configuration (WinRM) | ✅ |
| End-to-end deployment | ✅ |

---

## Prerequisites

- Azure CLI with `stack-hci-vm` extension
- PowerShell 7+ (`pwsh`) — see [Script Standards](../standards/scripting.md#runtime-requirement)
- WinRM access from management workstation to SOFS VMs
- RSAT Failover Clustering tools installed
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| Directory | File | Purpose |
|-----------|------|---------|
| `deploy/` | `Deploy-SOFS-Azure.ps1` | Azure resource provisioning (Phase 1–2) |
| `deploy/` | `Configure-SOFS-Cluster.ps1` | Guest OS configuration (Phases 3–11) |
| `deploy/` | `Invoke-SOFSDeployment.ps1` | End-to-end orchestrator with JSON state file for resume |
| `deploy/` | `Remove-SOFSDeployment.ps1` | Idempotent teardown — removes all Azure resources |
| `utilities/` | `New-SOFSDeployment.ps1` | Standalone: SOFS role + SMB share creation (Phases 8–9) |
| `utilities/` | `Set-FSLogixShare.ps1` | Standalone: NTFS/SMB permissions + FSLogix registry (Phases 9–10) |

---

## Azure Provisioning

### Deploy-SOFS-Azure.ps1

Creates all Azure-side resources using Azure CLI commands, including domain join via the `JsonADDomainExtension` Arc extension:

```powershell
cd src/powershell

# Using central config:
.\deploy\Deploy-SOFS-Azure.ps1 -ConfigPath "..\..\config\variables.yml"

# Or with individual parameters:
.\deploy\Deploy-SOFS-Azure.ps1 `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -ResourceGroup "rg-sofs-azl-eus-01" `
    -Location "eastus" `
    -CustomLocationId "<resource ID>" `
    -LogicalNetworkId "<resource ID>" `
    -GalleryImageId "<resource ID>" `
    -StoragePathIds @{
        "01" = "<resource ID>"
        "02" = "<resource ID>"
        "03" = "<resource ID>"
    }
```

**Resources created:**

- Resource group
- Cloud witness storage account (LRS, TLS 1.2, no public blob access)
- 2–16 NICs on the compute logical network (with optional static IPs)
- 2–16 Arc VMs (configurable vCPU and RAM)
- Data disks (configurable count per VM, dynamically provisioned)
- Domain join via `JsonADDomainExtension` (Arc extension, parallel execution)
- Per-VM storage path mapping (supports three-volume and single-volume host layouts)

Passwords are resolved from Key Vault at runtime — never passed as plaintext parameters.

---

## Guest Cluster Configuration

### Configure-SOFS-Cluster.ps1

Comprehensive WinRM/PSRemoting-based script run from a management workstation. **Idempotent** — safe to re-run if a step fails.

```powershell
# Using central config:
.\deploy\Configure-SOFS-Cluster.ps1 -ConfigPath "..\..\config\variables.yml"

# Or with individual parameters:
.\deploy\Configure-SOFS-Cluster.ps1 `
    -GuestClusterName "sofs-cluster" `
    -GuestClusterIP "192.168.1.204" `
    -SOFSAccessPoint "FSLogixSOFS" `
    -S2DVolumeSizeGB 2560 `
    -S2DDataCopies 2 `
    -ShareName "FSLogix" `
    -WitnessStorageAccountName "stsofswitnessprod01" `
    -WitnessStorageKey "<key>"
```

**Actions executed:**

| # | Action |
|-------|--------|
| 3 | Create anti-affinity rule on Azure Local host cluster |
| 4 | Verify domain join and post-deployment VM configuration |
| 5 | Install Failover-Clustering, FS-FileServer, FS-Resource-Manager, RSAT tools |
| 5b | Add domain join account to local Administrators |
| 6 | Validate cluster prerequisites, create failover cluster, configure cloud witness |
| 7 | Clean data disks, enable S2D, apply guest tuning, create S2D volume(s) — Single layout (single) or Triple layout (three) |
| 8 | Pre-stage AD objects, add SOFS Scale-Out File Server role, create SMB share(s) with CA + ABE |
| 9 | Apply NTFS permissions (CREATOR OWNER, Domain Users, Domain Admins, SYSTEM) |
| 9b | Configure FSRM quotas (soft quota at configured profile size) |
| 9c | Configure Cloud Cache CCDLocations (multi-provider support for DR) |
| 10 | Configure antivirus exclusions (ClusterStorage, VHD/VHDX, cluster processes) |
| 11 | Run validation checks |

---

## Supplemental Scripts

For targeted re-runs or environments where the full `Configure-SOFS-Cluster.ps1` isn't needed:

### New-SOFSDeployment.ps1 (Phases 8–9)

Enables the File Server cluster role, adds the SOFS role, creates the CSV directory, and creates the FSLogix SMB share:

```powershell
.\utilities\New-SOFSDeployment.ps1 `
    -ClusterName "sofs-cluster" `
    -SOFSName "FSLogixSOFS" `
    -VolumeName "FSLogixData" `
    -ShareName "FSLogix"
```

### Set-FSLogixShare.ps1 (Phases 9–10)

Configures NTFS and SMB share permissions, applies SMB settings optimized for FSLogix, and optionally sets FSLogix registry keys for testing:

```powershell
.\utilities\Set-FSLogixShare.ps1 `
    -SharePath "C:\ClusterStorage\FSLogixData\FSLogix" `
    -DomainNetBIOS "IIC" `
    -SetRegistryKeys
```

---

## Orchestrator and Teardown

### Invoke-SOFSDeployment.ps1

Runs Deploy → Configure as a single pipeline with JSON state file for resume:

```powershell
# Full end-to-end:
.\deploy\Invoke-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml"

# Skip Azure provisioning (VMs already exist):
.\deploy\Invoke-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml" -SkipDeploy

# Skip guest config (only provision Azure resources):
.\deploy\Invoke-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml" -SkipConfigure

# Force resume from a failed state:
.\deploy\Invoke-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml" -Force
```

State is tracked in `deployment-state.json` — if the script fails mid-way, re-running picks up where it left off.

### Remove-SOFSDeployment.ps1

Idempotent teardown that removes all Azure resources in reverse order:

```powershell
# Dry run — show what would be removed:
.\deploy\Remove-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml" -WhatIf

# Remove VMs, disks, NICs, witness — keep the resource group:
.\deploy\Remove-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml"

# Remove everything including the resource group:
.\deploy\Remove-SOFSDeployment.ps1 -ConfigPath "..\..\config\variables.yml" -RemoveResourceGroup
```

---

## All 10 Scenarios

The scripts support all 10 SOFS deployment scenarios through `config/variables.yml`:

| # | Nodes | Host Mirror | Guest Mirror | Guest Layout | Key Config Values |
|---|-------|-------------|-------------|-------------|------------------|
| 1 | 2 | 2-way | 2-way | Single layout | `vm.count=2`, `guest_resiliency=two_way`, `guest_layout=single` |
| 2 | 2 | 2-way | 2-way | Triple layout | `vm.count=2`, `guest_resiliency=two_way`, `guest_layout=triple` |
| 3 | 2 | 3-way | 2-way | Single layout | `vm.count=2`, `host_resiliency=three_way`, `guest_layout=single` |
| 4 | 2 | 3-way | 2-way | Triple layout | `vm.count=2`, `host_resiliency=three_way`, `guest_layout=triple` |
| 5 | 3 | 2-way | 2-way | Single layout | `vm.count=3`, `guest_resiliency=two_way`, `guest_layout=single` |
| 6 | 3 | 2-way | 2-way | Triple layout | `vm.count=3`, `guest_resiliency=two_way`, `guest_layout=triple` |
| 7 | 3 | 2-way | 3-way | Single layout | `vm.count=3`, `guest_resiliency=three_way`, `guest_layout=single` |
| 8 | 3 | 2-way | 3-way | Triple layout | `vm.count=3`, `guest_resiliency=three_way`, `guest_layout=triple` |
| 9 | 3 | 3-way | 2-way | Single layout | `vm.count=3`, `host_resiliency=three_way`, `guest_layout=single` |
| 10 | 3 | 3-way | 3-way | Triple layout | `vm.count=3`, `host_resiliency=three_way`, `guest_layout=triple` |

---

## Design Decision Support

The PowerShell scripts support all deployment combinations through `config/variables.yml`:

| Decision | Config Key |
|----------|-----------|
| VM count (2–16) | `vm.count` |
| Three host volumes | `azure_local.storage_path_ids` with per-VM entries |
| Single host volume | `azure_local.storage_path_id` with one entry |
| Two-way guest mirror | `deployment.guest_resiliency: two_way` |
| Three-way guest mirror | `deployment.guest_resiliency: three_way` |
| Single layout (single volume/share) | `deployment.guest_layout: single` |
| Triple layout (three volumes/shares) | `deployment.guest_layout: triple` |
| FSRM quotas | `fslogix.profile_size_mb` (auto-creates soft quota) |
| Cloud Cache DR | `fslogix.cloud_cache.providers[]` (multi-provider) |
| SMB encryption | `sofs.smb_encryption: true/false` |

---

## Next Steps

- [Validation](validation.md) — Verify the deployment
- [FSLogix Configuration](../configuration/fslogix.md) — Configure session hosts
- [Troubleshooting](../operations/troubleshooting.md) — If something goes wrong
