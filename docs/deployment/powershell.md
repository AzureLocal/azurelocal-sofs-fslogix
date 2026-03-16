# PowerShell Deployment

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

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
| Azure resource provisioning | :material-check: |
| Domain join (JsonADDomainExtension) | :material-check: |
| Guest OS configuration (WinRM) | :material-check: |
| End-to-end deployment | :material-check: |

---

## Prerequisites

- Azure CLI with `stack-hci-vm` extension
- PowerShell 5.1+ or PowerShell 7+
- WinRM access from management workstation to SOFS VMs
- RSAT Failover Clustering tools installed
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| Directory | File | Purpose |
|-----------|------|---------|
| `deploy/` | `Deploy-SOFS-Azure.ps1` | Azure resource provisioning |
| `deploy/` | `Configure-SOFS-Cluster.ps1` | Guest OS configuration (Phases 3–11) |
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
- 3 NICs on the compute logical network (with optional static IPs)
- 3 Arc VMs (4 vCPU, 8 GB RAM each)
- 12 data disks (4 per VM, dynamically provisioned)
- Domain join via `JsonADDomainExtension` (Arc extension, parallel execution)

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
| 1 | Create anti-affinity rule on Azure Local host cluster |
| 2 | Verify domain join and post-deployment VM configuration |
| 3 | Install Failover-Clustering, FS-FileServer, RSAT tools |
| 4 | Validate cluster prerequisites, create failover cluster, configure cloud witness |
| 5 | Clean data disks, enable S2D, apply guest tuning (HwTimeout, auto-replace disable), create S2D volume(s) |
| 6 | Add SOFS Scale-Out File Server role, create SMB share(s) with CA + ABE |
| 7 | Apply NTFS permissions (CREATOR OWNER, Domain Users, Domain Admins, SYSTEM) |
| 8 | Configure antivirus exclusions (ClusterStorage, VHD/VHDX, cluster processes) |
| 9 | Run validation checks |

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

## Design Decision Support

The PowerShell scripts support all deployment combinations through variables:

| Decision | Parameter |
|----------|-----------|
| Three host volumes | `storage_path_ids` with three entries |
| Single host volume | `storage_path_id` with one entry |
| Two-way mirror | `-S2DDataCopies 2` |
| Three-way mirror | `-S2DDataCopies 3` |
| Option A (single share) | `-ShareName "FSLogix"` with single `-S2DVolumeName` |
| Option B (three shares) | Multiple share names and volume names |

---

## Next Steps

- [Validation](validation.md) — Verify the deployment
- [FSLogix Configuration](../configuration/fslogix.md) — Configure session hosts
- [Troubleshooting](../operations/troubleshooting.md) — If something goes wrong
