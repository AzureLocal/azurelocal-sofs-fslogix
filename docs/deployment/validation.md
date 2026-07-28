# Validation

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

## Overview

After deploying and configuring the SOFS, validate that everything works before onboarding AVD session hosts. This page covers automated validation, manual verification steps, and failover testing.

---

## Per-Tool Testing

Each deployment tool has its own unit/integration tests that can be run before deployment:

### PowerShell (Pester 5)

```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

Runs 23 test suites covering config parsing, schema validation, VM parameter generation, storage path mapping, FSRM quotas, Cloud Cache, and more.

### Terraform

```powershell
cd src/terraform
terraform init
terraform test
```

Validates AVM module references, variable mapping, domain join extension, per-VM storage paths, and single/triple layout conditional logic.

### Ansible (Molecule)

```bash
cd src/ansible
molecule test
```

Runs the full Molecule test suite — lint, syntax, converge, idempotence, verify — against a local Docker test matrix.

### Bicep

```powershell
az bicep build --file src/bicep/main.bicep
```

Validates Bicep syntax and AVM module references. Successful compilation confirms the template is structurally valid.

### ARM

```powershell
cd src/arm
.\build-arm.ps1
```

Recompiles from Bicep and validates the resulting JSON template.

---

## Automated Validation

The `Test-SOFSDeployment.ps1` script validates the full SOFS deployment:

```powershell
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC"
```

For Triple layout (three shares):

```powershell
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("Profiles", "ODFC", "AppData") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC"
```

**What it checks:**

- SMB share reachability (`Test-Path`)
- Share settings: Continuously Available, CachingMode None, correct ScopeName
- NTFS permissions: CREATOR OWNER, Domain Users, Domain Admins, SYSTEM
- SMB encryption settings
- S2D health status
- Cluster health

---

## Manual Verification

### 1. SOFS Share Accessibility

From any machine on the compute network:

=== "Single layout — Single Share"

    ```powershell
    Test-Path "\\FSLogixSOFS\FSLogix"
    ```

=== "Triple layout — Three Shares"

    ```powershell
    "Profiles", "ODFC", "AppData" | ForEach-Object {
        [PSCustomObject]@{ Share = $_; Accessible = (Test-Path "\\FSLogixSOFS\$_") }
    }
    ```

### 2. SMB Share Settings

Verify Continuous Availability and caching are correctly configured:

```powershell
Get-SmbShare -CimSession "sofs-01" -Name "FSLogix" |
    Select-Object Name, ScopeName, ContinuouslyAvailable, CachingMode
```

Expected:

| Property | Expected Value |
|----------|---------------|
| `ScopeName` | SOFS access point name (e.g., `FSLogixSOFS`) |
| `ContinuouslyAvailable` | `True` |
| `CachingMode` | `None` |

### 3. Anti-Affinity Verification

Confirm all three SOFS VMs are on separate Azure Local physical nodes:

```powershell
# Check VM placement
Get-ClusterGroup -Cluster "azl-cluster-01" |
    Where-Object { $_.Name -like "*sofs*" } |
    Select-Object Name, OwnerNode

# Verify affinity rule
Get-ClusterAffinityRule -Name "SOFS-AntiAffinity" -Cluster "azl-cluster-01"
```

Each VM must show a different `OwnerNode`.

### 4. S2D Health

```powershell
# Storage pool health
Get-StoragePool -CimSession "sofs-cluster" |
    Where-Object { $_.IsPrimordial -eq $false } |
    Select-Object FriendlyName, HealthStatus, OperationalStatus

# Virtual disks
Get-VirtualDisk -CimSession "sofs-cluster" |
    Select-Object FriendlyName, HealthStatus, OperationalStatus, ResiliencySettingName, NumberOfDataCopies

# Physical disks
Get-PhysicalDisk -CimSession "sofs-cluster" |
    Select-Object FriendlyName, HealthStatus, OperationalStatus, Size
```

All components should report `Healthy` / `OK`.

### 5. Cluster Health

```powershell
Get-ClusterNode -Cluster "sofs-cluster" | Select-Object Name, State
Get-ClusterGroup -Cluster "sofs-cluster" | Select-Object Name, State, OwnerNode
Get-ClusterQuorum -Cluster "sofs-cluster"
```

All nodes should be `Up`. The quorum model should show `CloudWitness`.

---

## Failover Testing

> [!WARNING]
> **Test during a maintenance window**
> Failover testing should be done before production onboarding, not during active user sessions.
>
### Test Procedure

1. **Create a test file** on the SOFS share:

    ```powershell
    New-Item "\\FSLogixSOFS\FSLogix\test-failover.txt" -Value "Failover test $(Get-Date)"
    ```

2. **Identify the current owner** of the SOFS role:

    ```powershell
    Get-ClusterGroup -Cluster "sofs-cluster" |
        Where-Object { $_.GroupType -eq "ScaleOutFileServer" } |
        Select-Object Name, OwnerNode
    ```

3. **Drain a SOFS node** (simulates host maintenance or failure):

    ```powershell
    # On the Azure Local cluster — drain the host node running one SOFS VM
    Suspend-ClusterNode -Name "azl-node-01" -Cluster "azl-cluster-01" -Drain
    ```

4. **Verify share remains accessible:**

    ```powershell
    Test-Path "\\FSLogixSOFS\FSLogix"
    Get-Content "\\FSLogixSOFS\FSLogix\test-failover.txt"
    ```

5. **Resume the node:**

    ```powershell
    Resume-ClusterNode -Name "azl-node-01" -Cluster "azl-cluster-01"
    ```

### What to Expect

- The share should remain accessible throughout the drain/resume cycle
- SMB3 transparent failover (via Continuous Availability) handles the reconnection
- Users with mounted FSLogix profiles experience no disruption
- S2D continues operating with 2 of 3 nodes — the two-way mirror serves all reads/writes

### If Failover Fails

- Verify `ContinuouslyAvailable` is `$true` on all shares
- Verify the SOFS role is configured as ScaleOutFileServer (not regular FileServer)
- Check that SMB3 is being used (not SMB2 or earlier)
- See [Troubleshooting](../operations/troubleshooting.md) for detailed diagnosis

---

## Validation Checklist

- [ ] All SOFS shares accessible via UNC path
- [ ] ContinuouslyAvailable = True on all shares
- [ ] CachingMode = None on all shares
- [ ] ScopeName matches SOFS access point
- [ ] Anti-affinity rule active and verified
- [ ] All SOFS VMs on separate physical nodes (2–16 VMs supported)
- [ ] S2D pool, virtual disks, and physical disks healthy
- [ ] Resiliency matches config (`NumberOfDataCopies` = 2 or 3)
- [ ] All cluster nodes Up
- [ ] Cloud witness configured and accessible
- [ ] NTFS permissions correct (test with a domain user account)
- [ ] Failover test passed — share accessible during node drain
- [ ] Test file created and read back after failover
- [ ] Single layout: single share (`FSLogix`) present
- [ ] Triple layout: three shares (`Profiles`, `ODFC`, `AppData`) present
- [ ] FSRM quotas applied (if configured)
- [ ] Cloud Cache CCDLocations string matches providers config (if enabled)

---

## Next Steps

- [FSLogix Configuration](../configuration/fslogix.md) — Configure session hosts to use the SOFS
- [Permissions](../configuration/permissions.md) — Verify NTFS ACL model
- [Antivirus Exclusions](../configuration/antivirus.md) — Configure AV exclusions on SOFS and session hosts
