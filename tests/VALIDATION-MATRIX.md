# E2E Validation Matrix

## Overview

This document tracks end-to-end validation of all 10 SOFS scenarios across all deployment tool combinations. Each cell represents a unique scenario × tool-path combination.

Use `Test-SOFSDeployment.ps1` for post-deployment validation:

```powershell
# Option A — single share
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC" `
    -HostClusterName "azl-cluster-01" `
    -ExpectedNodeCount 3 `
    -ExpectedDataCopies 2

# Option B — three shares
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("Profiles", "ODFC", "AppData") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC" `
    -HostClusterName "azl-cluster-01" `
    -ExpectedNodeCount 2 `
    -ExpectedDataCopies 3
```

Use `Test-ToolSmokeTests.ps1` for pre-flight validation (no infra required):

```powershell
Invoke-Pester .\tests\Test-ToolSmokeTests.ps1 -Output Detailed
```

---

## The 10 Scenarios

| # | VM Count | Host Resiliency | Guest Resiliency | Volume Layout | Short Name |
|---|----------|-----------------|------------------|--------------|------------|
| 1 | 2 | Two-way mirror | Two-way mirror | Option A (1 share) | 2n-2h-2g-A |
| 2 | 2 | Two-way mirror | Three-way mirror | Option A | 2n-2h-3g-A |
| 3 | 2 | Three-way mirror | Two-way mirror | Option A | 2n-3h-2g-A |
| 4 | 2 | Three-way mirror | Three-way mirror | Option A | 2n-3h-3g-A |
| 5 | 3 | Two-way mirror | Two-way mirror | Option A | 3n-2h-2g-A |
| 6 | 2 | Two-way mirror | Two-way mirror | Option B (3 shares) | 2n-2h-2g-B |
| 7 | 2 | Two-way mirror | Three-way mirror | Option B | 2n-2h-3g-B |
| 8 | 2 | Three-way mirror | Two-way mirror | Option B | 2n-3h-2g-B |
| 9 | 2 | Three-way mirror | Three-way mirror | Option B | 2n-3h-3g-B |
| 10 | 3 | Two-way mirror | Two-way mirror | Option B | 3n-2h-2g-B |

---

## Validation Matrix

### Legend

- ✅ Passed — all checks passed
- ❌ Failed — one or more checks failed
- 🔲 Not tested — awaiting lab environment

### Azure Provisioning + Guest Configuration

| Scenario | PS+PS | TF+PS | TF+Ansible | Bicep+PS | ARM+PS | Ansible+Ansible |
|----------|:-----:|:-----:|:----------:|:--------:|:------:|:---------------:|
| 2n-2h-2g-A | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-3g-A | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-2g-A | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-3g-A | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 3n-2h-2g-A | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-2g-B | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-3g-B | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-2g-B | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-3g-B | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 3n-2h-2g-B | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |

---

## Expected S2D Pool Sizes per Scenario

These are the expected usable capacities assuming 4 data disks × 500 GB per VM.

### Option A — Single Volume

| Scenario | VMs | Raw Disk Total | Data Copies | Usable Capacity | Volume Size |
|----------|-----|----------------|-------------|-----------------|-------------|
| 2n-2h-2g-A | 2 | 4,000 GB (2×4×500) | 2 | ~2,000 GB | 2,560 GB configured |
| 2n-2h-3g-A | 2 | 4,000 GB | 3 | ~1,333 GB | Adjust to fit |
| 2n-3h-2g-A | 2 | 4,000 GB | 2 | ~2,000 GB | 2,560 GB configured |
| 2n-3h-3g-A | 2 | 4,000 GB | 3 | ~1,333 GB | Adjust to fit |
| 3n-2h-2g-A | 3 | 6,000 GB (3×4×500) | 2 | ~3,000 GB | 2,560 GB configured |

### Option B — Three Volumes

| Scenario | VMs | Raw Disk Total | Data Copies | Profiles | ODFC | AppData | Total Used |
|----------|-----|----------------|-------------|----------|------|---------|-----------|
| 2n-2h-2g-B | 2 | 4,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |
| 2n-2h-3g-B | 2 | 4,000 GB | 3 | 1,500 GB | 800 GB | 260 GB | Needs sizing review |
| 2n-3h-2g-B | 2 | 4,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |
| 2n-3h-3g-B | 2 | 4,000 GB | 3 | 1,500 GB | 800 GB | 260 GB | Needs sizing review |
| 3n-2h-2g-B | 3 | 6,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |

!!! note "Three-way mirror sizing"
    With 3-way mirror on 2 VMs (4,000 GB raw), usable capacity is ~1,333 GB. The default Option B volumes total 2,560 GB — **this exceeds raw capacity with 3-way mirror on 2 nodes**. Either increase disk count/size or reduce volume sizes for these scenarios.

---

## Per-Check Validation Details

### SMB Share Checks (per share)

| Check | Expected | Notes |
|-------|----------|-------|
| UNC path reachable | `True` | `Test-Path \\SOFSName\ShareName` |
| SMB share exists | Present | `Get-SmbShare -ScopeName` |
| ContinuouslyAvailable | `True` | Required for FSLogix transparent failover |
| CachingMode | `None` | Branch cache must be off for profile containers |
| EncryptData | `True` | SMB encryption for data in transit |
| Write access | Success | Creates and deletes test file |

### NTFS Permission Checks (per share)

| ACE Identity | Type | Expected |
|-------------|------|----------|
| CREATOR OWNER | Allow | Full Control (subfolders + files) |
| DOMAIN\Domain Users | Allow | Modify (this folder only) |
| DOMAIN\Domain Admins | Allow | Full Control |
| NT AUTHORITY\SYSTEM | Allow | Full Control |

### Cluster Health Checks

| Check | Expected | Notes |
|-------|----------|-------|
| Node count | Matches `ExpectedNodeCount` | 2–16 |
| All nodes Up | `True` | No nodes Down or Paused |
| Cloud Witness | Present | Quorum resource type = Cloud Witness |

### S2D Health Checks

| Check | Expected | Notes |
|-------|----------|-------|
| Pool healthy | `Healthy` | Non-primordial pool |
| Virtual disk healthy | `Healthy` | Per virtual disk |
| Data copies | Matches `ExpectedDataCopies` | 2 or 3 |

### Anti-Affinity Checks (optional)

| Check | Expected | Notes |
|-------|----------|-------|
| Rule exists | Present | On host cluster |
| VMs on separate hosts | All distinct | OwnerNode must be unique per VM |

---

## Smoke Test Quick Reference

Pre-flight tests that don't require infrastructure:

```powershell
# All 10 scenarios — config generation + tool syntax
Invoke-Pester .\tests\Test-ToolSmokeTests.ps1 -Output Detailed

# Full unit test suite — 23 Describe blocks
Invoke-Pester .\tests\Test-SOFSDeployment.Tests.ps1 -Output Detailed

# Terraform
cd src/terraform && terraform init -backend=false && terraform validate && terraform test

# Bicep
az bicep build --file src/bicep/main.bicep

# ARM
cd src/arm && .\build-arm.ps1

# Ansible
cd src/ansible && molecule test
```
