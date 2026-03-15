# PowerShell — Full SOFS Deployment

![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen)

End-to-end PowerShell deployment for a 3-node Scale-Out File Server on Azure Local. These two scripts together deploy all Azure resources and configure the guest cluster, SOFS role, and FSLogix SMB share.

## Files

| File | Description |
|------|-------------|
| `Deploy-SOFS-Azure.ps1` | **Phase 1** — Deploys Azure Local resources (resource group, witness storage, NICs, VMs, data disks) using Azure CLI, driven by a solution config YAML |
| `Configure-SOFS-Cluster.ps1` | **Phase 2** — Configures the guest cluster over WinRM: anti-affinity rules, failover clustering, S2D pool, cloud witness, mirror volumes, SOFS role, FSLogix SMB share, NTFS permissions, and deployment validation |

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Azure CLI authenticated (`az login`)
- WinRM connectivity to the SOFS VMs (Kerberos or HTTPS)
- SOFS VMs deployed and domain-joined (Phase 1 must complete before Phase 2)

## Usage

```powershell
# Phase 1 — Deploy Azure resources
.\Deploy-SOFS-Azure.ps1

# Phase 2 — Configure the guest cluster (after VMs are domain-joined)
.\Configure-SOFS-Cluster.ps1
```

## Status

These scripts have been tested against a production Azure Local cluster and will deploy a working SOFS. Additional enhancements and configuration options may be added in future updates.
