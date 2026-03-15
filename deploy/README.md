# Deploy — Phase 2: SOFS Cluster Provisioning

Creates the Scale Out File Server cluster role and the SMB share on the Azure Local failover cluster.

---

## Scripts

| Script | Description |
|--------|-------------|
| `New-SOFSDeployment.ps1` | Creates the SOFS cluster role, CSV directory, and continuously-available SMB share |

---

## Prerequisites

- **Phase 1** (infrastructure) completed — Azure resource group exists.
- PowerShell 5.1+ on a machine with network access to the Azure Local cluster.
- RSAT – Failover Clustering tools:
  ```powershell
  Install-WindowsFeature -Name RSAT-Clustering -IncludeManagementTools
  ```
- Domain credentials with permission to manage the failover cluster.
- A healthy cluster with at least one Clustered Shared Volume (CSV) online.

---

## Quick Start

1. Ensure `config/variables.yml` is populated (see [`config/README.md`](../config/README.md)).

2. Deploy the SOFS:
   ```powershell
   .\deploy\New-SOFSDeployment.ps1 -ParametersFile .\deploy\parameters.example.ps1
   ```

   Or pass parameters directly:
   ```powershell
   .\deploy\New-SOFSDeployment.ps1 `
     -ClusterName "AZLHCI-CLUSTER" `
     -SOFSName "SOFS01" `
     -ShareName "FSLogixProfiles" `
     -SharePath "C:\ClusterStorage\Volume1\FSLogixProfiles"
   ```

---

## Parameters Reference

See `parameters.example.ps1` for all available parameters, or use the central `config/variables.yml`.

---

## Next Step

After the SOFS is deployed, proceed to [**Phase 3: Configure**](../configure/) to set share permissions and FSLogix settings.
