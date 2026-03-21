# PowerShell — Full SOFS Deployment

![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen)

End-to-end PowerShell deployment for a Scale-Out File Server on Azure Local. The orchestrator runs Phase 1 (Azure resources) and Phase 2 (guest OS configuration) in sequence, with automatic domain-join wait, state tracking, and per-phase logging.

## Files

| File | Description |
|------|-------------|
| `Invoke-SOFSDeployment.ps1` | **Orchestrator** — Runs Deploy → waits for domain join → Configure in sequence. Tracks progress in a JSON state file so failed runs can be resumed. Supports `-Destroy`, `-SkipDeploy`, `-SkipConfigure`, and `-WhatIf` |
| `Deploy-SOFS-Azure.ps1` | **Phase 1** — Deploys Azure Local resources (resource group, witness storage, NICs, VMs, data disks, domain-join extensions) using Azure CLI, driven by `config/variables.yml` |
| `Configure-SOFS-Cluster.ps1` | **Phase 2** — Configures the guest cluster over WinRM: anti-affinity rules, failover clustering, S2D pool, cloud witness, mirror volumes, SOFS role, SMB shares, NTFS permissions, and deployment validation. Supports Single layout (single share) and Triple layout (per-volume shares) |
| `Remove-SOFSDeployment.ps1` | **Teardown** — Removes all Azure resources in reverse order: extensions → VMs → data disks → NICs → witness storage → (optional) resource group |

## Prerequisites

- PowerShell 7.0+
- `powershell-yaml` module (`Install-Module powershell-yaml`)
- Azure CLI authenticated (`az login`) with the `stack-hci-vm` extension
- WinRM connectivity to the SOFS VMs (basic or kerberos)
- Configuration defined in `config/variables.yml` (see `config/variables.example.yml`)

## Usage

```powershell
# Full end-to-end deployment (Deploy → wait for domain join → Configure)
.\Invoke-SOFSDeployment.ps1

# Resume a failed run (picks up from the last incomplete phase)
.\Invoke-SOFSDeployment.ps1 -Force

# Deploy infra only — skip guest OS configuration
.\Invoke-SOFSDeployment.ps1 -SkipConfigure

# Configure only — VMs already exist and are domain-joined
.\Invoke-SOFSDeployment.ps1 -SkipDeploy -DomainJoinWaitMinutes 0

# Dry-run — preview what both phases would do
.\Invoke-SOFSDeployment.ps1 -WhatIf

# Run individual scripts directly
.\Deploy-SOFS-Azure.ps1
.\Configure-SOFS-Cluster.ps1

# Tear down all resources
.\Invoke-SOFSDeployment.ps1 -Destroy

# Tear down including the resource group
.\Invoke-SOFSDeployment.ps1 -Destroy -RemoveResourceGroup
```

## State Tracking

The orchestrator writes a JSON state file to `logs/sofs/deployment-state.json` that tracks:
- Overall deployment status (`in_progress`, `completed`)
- Per-phase status (`not_started`, `running`, `completed`, `failed`, `skipped`)
- Start/end timestamps and exit codes for each phase
- Per-phase log file paths

This allows resuming after failures without re-running completed phases.

## Status

These scripts have been tested against a production Azure Local cluster and will deploy a working SOFS. Additional enhancements and configuration options may be added in future updates.
