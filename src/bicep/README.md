# SOFS on Azure Local — Bicep Deployment

![Status: In Progress](https://img.shields.io/badge/status-in_progress-yellow)

## Overview

Subscription-scope Bicep deployment that creates:
- Resource group (if it doesn't exist)
- 3 Azure Local VMs (Arc machines + NICs + VM instances)
- 12 data disks (4 × 1 TB per VM) for S2D storage pool
- Cloud witness storage account for guest cluster quorum

## Files

| File | Purpose |
|------|---------|
| `main.bicep` | Subscription-scope wrapper — creates RG, calls modules |
| `sofs-resources.bicep` | Resource-group-scope module — VMs, NICs, data disks |
| `witness-storage.bicep` | Cloud witness storage account |
| `main.bicepparam` | Example parameters (reference only — never commit secrets) |
| `Deploy-SOFS-Azure.ps1` | Orchestrator script — reads solution config, resolves KV, deploys |

## Usage

```powershell
# Generate solution config first:
.\tools\Generate-SolutionConfig.ps1 -Solution sofs-azure-local -Environment production

# Dry run (validate templates):
.\solutions\sofs\bicep\Deploy-SOFS-Azure.ps1 -WhatIf

# Full deployment:
.\solutions\sofs\bicep\Deploy-SOFS-Azure.ps1
```

## Architecture

```
main.bicep (subscription scope)
├── Creates resource group
├── sofs-resources.bicep (resource-group scope)
│   ├── Microsoft.HybridCompute/machines[]           — Arc placeholders
│   ├── Microsoft.AzureStackHCI/networkInterfaces[]   — NICs
│   ├── Microsoft.AzureStackHCI/virtualHardDisks[]    — Data disks
│   └── Microsoft.AzureStackHCI/VirtualMachineInstances[] — VMs
└── witness-storage.bicep (resource-group scope)
    └── Microsoft.Storage/storageAccounts             — Cloud witness
```

## Post-Deployment

After Bicep deploys the Azure resources, run the PowerShell guest configuration:

```powershell
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1
```

This handles: domain join verification, anti-affinity rules, failover clustering, S2D, SOFS role, SMB share, and NTFS permissions.
