# PowerShell — SOFS Utilities

![Status: Untested](https://img.shields.io/badge/status-untested-red)

Standalone PowerShell scripts for individual SOFS and FSLogix tasks. Each script can be run independently — they are not part of the end-to-end deployment workflow.

## Files

| File | Description |
|------|-------------|
| `New-SOFSDeployment.ps1` | Enables the File Server cluster role, adds the SOFS role, creates a CSV directory, and creates/configures the FSLogix SMB share on an existing failover cluster |
| `Set-FSLogixShare.ps1` | Configures NTFS and share permissions plus FSLogix-optimised SMB settings (oplocks, leasing) on an existing SOFS share for AVD users |
| `parameters.example.ps1` | Example parameter file — defines cluster name, SOFS name, share path, AD domain, AVD user group, and Azure subscription details |

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- FailoverClusters PowerShell module
- Run on a machine with access to the failover cluster (cluster node or management workstation with RSAT)

## Usage

```powershell
# Load parameters
. .\parameters.example.ps1

# Create the SOFS role and FSLogix share
.\New-SOFSDeployment.ps1

# Configure permissions on an existing share
.\Set-FSLogixShare.ps1
```

## Status

These scripts have not been tested yet. Review and test in a non-production environment before use.