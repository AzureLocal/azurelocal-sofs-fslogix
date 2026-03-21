# Tests

End-to-end validation, unit tests, and smoke tests for the SOFS deployment.

---

## Test Inventory

| Script | Type | Description |
|--------|------|-------------|
| `Test-SOFSDeployment.ps1` | E2E Validator | Post-deployment validation: SMB shares, NTFS permissions, cluster health, S2D health, anti-affinity |
| `Test-SOFSDeployment.Tests.ps1` | Pester Unit | 23 test suites covering config loading, parameter resolution, single/triple layout, storage paths, FSRM, Cloud Cache |
| `Test-ToolSmokeTests.ps1` | Pester Smoke | Pre-flight validation of all 10 scenarios across all 5 tools (no infra required) |
| `VALIDATION-MATRIX.md` | Documentation | Tracks E2E test results for all scenario × tool-path combinations |
| `terraform/` | Terraform Test | `.tftest.hcl` files for `terraform test` |

---

## Quick Start

### Pre-Flight (no infrastructure required)

```powershell
# Full unit test suite
Invoke-Pester .\tests\Test-SOFSDeployment.Tests.ps1 -Output Detailed

# All 10 scenarios — smoke tests
Invoke-Pester .\tests\Test-ToolSmokeTests.ps1 -Output Detailed
```

### Post-Deployment Validation

```powershell
# Single layout — single share
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC"

# Triple layout — three shares
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("Profiles", "ODFC", "AppData") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC"

# With anti-affinity verification
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC" `
    -HostClusterName "azl-cluster-01" `
    -ExpectedNodeCount 3 `
    -ExpectedDataCopies 2
```

---

## Validation Checks

### Post-Deployment (`Test-SOFSDeployment.ps1`)

| Category | Check | Description |
|----------|-------|-------------|
| **SMB Shares** | UNC reachable | `Test-Path \\SOFSName\ShareName` |
| | Share exists | `Get-SmbShare -ScopeName` |
| | ContinuouslyAvailable | CA flag = True |
| | CachingMode | Must be None |
| | SMB Encryption | EncryptData = True |
| | Write access | Create/delete test file |
| **NTFS** | CREATOR OWNER | Full Control (subfolders + files) |
| | Domain Users | Modify (this folder only) |
| | Domain Admins | Full Control |
| | SYSTEM | Full Control |
| **Cluster** | Node count | Matches expected (2–16) |
| | Nodes Up | All nodes in Up state |
| | Cloud Witness | Quorum type = Cloud Witness |
| **S2D** | Pool healthy | Non-primordial pool health |
| | Virtual disks | Each VDisk healthy |
| | Data copies | Matches expected resiliency (2 or 3) |
| **Anti-Affinity** | Rule exists | On host cluster |
| | VM separation | Each VM on distinct physical host |

### Pre-Flight (`Test-ToolSmokeTests.ps1`)

| Category | Check |
|----------|-------|
| Config generation | All 10 scenarios produce valid configs |
| Data copies | Match guest resiliency setting |
| IP addresses | Count matches VM count |
| Share structure | Single layout = 1 share, Triple layout = 3 shares |
| No hardcoding | No scenario-specific constants in source |
| PowerShell syntax | All .ps1 files parse without errors |
| Terraform validate | `terraform validate` passes |
| Bicep build | `az bicep build` succeeds |
| ARM JSON | Valid JSON structure |
| Pool sizes | All volumes have positive sizes |

---

## Validation Matrix

See [VALIDATION-MATRIX.md](VALIDATION-MATRIX.md) for the full 10 scenarios × 6 tool-path matrix tracking E2E test results.
