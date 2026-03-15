# PowerShell – SOFS & FSLogix Deployment

PowerShell scripts for deploying and configuring a Scale Out File Server (SOFS) on Azure Local for FSLogix profile containers.

---

## Scripts

| Script | Description |
|--------|-------------|
| `New-SOFSDeployment.ps1` | Creates the SOFS cluster role and SMB share |
| `Set-FSLogixShare.ps1` | Configures share permissions and FSLogix-specific settings |
| `Test-SOFSDeployment.ps1` | Validates SOFS connectivity and FSLogix configuration |

---

## Prerequisites

- PowerShell 5.1 or later running on a machine with network access to the Azure Local cluster.
- RSAT – Failover Clustering tools:
  ```powershell
  Install-WindowsFeature -Name RSAT-Clustering -IncludeManagementTools
  ```
- Domain credentials with permission to manage the failover cluster.

---

## Quick Start

1. Copy the example parameters file and fill in your values:
   ```powershell
   Copy-Item parameters.example.ps1 parameters.ps1
   # Edit parameters.ps1 with your environment values
   ```

2. Deploy the SOFS:
   ```powershell
   .\New-SOFSDeployment.ps1 -ParametersFile .\parameters.ps1
   ```

3. Configure FSLogix share permissions:
   ```powershell
   .\Set-FSLogixShare.ps1 -ParametersFile .\parameters.ps1
   ```

4. Validate:
   ```powershell
   .\Test-SOFSDeployment.ps1 -SOFSName "SOFS01" -ShareName "FSLogixProfiles"
   ```

---

## Parameters Reference

See `parameters.example.ps1` for all available parameters and descriptions.
