# E2E Validation Matrix

## Overview

This document tracks end-to-end validation of all 10 SOFS scenarios across all deployment tool combinations. Each cell represents a unique scenario × tool-path combination.

Use `Test-SOFSDeployment.ps1` for post-deployment validation:

```powershell
# Single layout — single share
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster" `
    -DomainNetBIOS "IIC" `
    -HostClusterName "azl-cluster-01" `
    -ExpectedNodeCount 3 `
    -ExpectedDataCopies 2

# Triple layout — three shares
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
| 1 | 2 | Two-way mirror | Two-way mirror | Single layout (1 share) | 2n-2h-2g-single |
| 2 | 2 | Two-way mirror | Three-way mirror | Single layout | 2n-2h-3g-single |
| 3 | 2 | Three-way mirror | Two-way mirror | Single layout | 2n-3h-2g-single |
| 4 | 2 | Three-way mirror | Three-way mirror | Single layout | 2n-3h-3g-single |
| 5 | 3 | Two-way mirror | Two-way mirror | Single layout | 3n-2h-2g-single |
| 6 | 2 | Two-way mirror | Two-way mirror | Triple layout (3 shares) | 2n-2h-2g-triple |
| 7 | 2 | Two-way mirror | Three-way mirror | Triple layout | 2n-2h-3g-triple |
| 8 | 2 | Three-way mirror | Two-way mirror | Triple layout | 2n-3h-2g-triple |
| 9 | 2 | Three-way mirror | Three-way mirror | Triple layout | 2n-3h-3g-triple |
| 10 | 3 | Two-way mirror | Two-way mirror | Triple layout | 3n-2h-2g-triple |

---

## Validation Matrix

### Legend

- ✅ Passed — all checks passed
- ❌ Failed — one or more checks failed
- 🔲 Not tested — awaiting lab environment

### Azure Provisioning + Guest Configuration

| Scenario | PS+PS | TF+PS | TF+Ansible | Bicep+PS | ARM+PS | Ansible+Ansible |
|----------|:-----:|:-----:|:----------:|:--------:|:------:|:---------------:|
| 2n-2h-2g-single | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-3g-single | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-2g-single | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-3g-single | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 3n-2h-2g-single | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-2g-triple | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-2h-3g-triple | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-2g-triple | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 2n-3h-3g-triple | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |
| 3n-2h-2g-triple | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 | 🔲 |

---

## Expected S2D Pool Sizes per Scenario

These are the expected usable capacities assuming 4 data disks × 500 GB per VM.

### Single layout — Single Volume

| Scenario | VMs | Raw Disk Total | Data Copies | Usable Capacity | Volume Size |
|----------|-----|----------------|-------------|-----------------|-------------|
| 2n-2h-2g-single | 2 | 4,000 GB (2×4×500) | 2 | ~2,000 GB | 2,560 GB configured |
| 2n-2h-3g-single | 2 | 4,000 GB | 3 | ~1,333 GB | Adjust to fit |
| 2n-3h-2g-single | 2 | 4,000 GB | 2 | ~2,000 GB | 2,560 GB configured |
| 2n-3h-3g-single | 2 | 4,000 GB | 3 | ~1,333 GB | Adjust to fit |
| 3n-2h-2g-single | 3 | 6,000 GB (3×4×500) | 2 | ~3,000 GB | 2,560 GB configured |

### Triple layout — Three Volumes

| Scenario | VMs | Raw Disk Total | Data Copies | Profiles | ODFC | AppData | Total Used |
|----------|-----|----------------|-------------|----------|------|---------|-----------|
| 2n-2h-2g-triple | 2 | 4,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |
| 2n-2h-3g-triple | 2 | 4,000 GB | 3 | 1,500 GB | 800 GB | 260 GB | Needs sizing review |
| 2n-3h-2g-triple | 2 | 4,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |
| 2n-3h-3g-triple | 2 | 4,000 GB | 3 | 1,500 GB | 800 GB | 260 GB | Needs sizing review |
| 3n-2h-2g-triple | 3 | 6,000 GB | 2 | 1,500 GB | 800 GB | 260 GB | 2,560 GB |

---

## Epic Evidence Coverage

### Issue #67 — Phase 0 decision-tree enforcement

- Source of truth: `deployment.guest_layout` (`single` or `triple`), with legacy alias support via `deployment.guest_volume_layout`.
- Evidence: `tests/Test-ToolSmokeTests.ps1` now generates all matrix scenarios using canonical values and verifies alias mapping.
- Evidence: `tests/Test-SOFSDeployment.Tests.ps1` validates canonical layout values and legacy alias compatibility.

### Issue #68 — Tool parity and phase ownership clarity

- Evidence: this matrix explicitly separates Azure provisioning + guest configuration paths per tool pair.
- Evidence: `docs/deployment/ansible.md` corrected to remove unsupported FSRM/antivirus claims and align stated phase coverage with implemented tasks.

### Issue #69 — Validation and reproducibility

- Evidence: this matrix preserves all 10 scenarios with canonical naming and repeatable test commands.
- Evidence: smoke, unit, and per-tool validation commands are documented in this file and `tests/README.md`.

---

## Phase Ownership by Tool

| Tool | Phase 0 | Phases 1-2 | Phases 3-11 |
|------|:-------:|:----------:|:-----------:|
| PowerShell | ✅ | ✅ | ✅ |
| Terraform | ✅ (variable validation) | ✅ | ❌ (delegates) |
| Bicep | ⚠️ (parameter validation only) | ✅ | ❌ (delegates) |
| ARM | ⚠️ (parameter validation only) | ✅ | ❌ (delegates) |
| Ansible | ✅ (preflight in guest configure playbook) | ✅ | ✅ |

Legend:

- ✅ implemented directly
- ⚠️ partial / parameter-level only
- ❌ delegated to another tool

!!! note "Three-way mirror sizing"
    With 3-way mirror on 2 VMs (4,000 GB raw), usable capacity is ~1,333 GB. The default Triple layout volumes total 2,560 GB — **this exceeds raw capacity with 3-way mirror on 2 nodes**. Either increase disk count/size or reduce volume sizes for these scenarios.

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

---

## Pre-Flight Validation Report

This section captures the current pass/fail status of all validation that can be run without lab infrastructure.

### PowerShell Pester Tests

| Suite | Tests | Passed | Failed | Status |
|-------|:-----:|:------:|:------:|:------:|
| `Test-SOFSDeployment.Tests.ps1` | 117 | 117 | 0 | ✅ |
| `Test-ToolSmokeTests.ps1` | — | — | — | ✅ (syntax verified) |

### Terraform Validation

| Check | Status |
|-------|:------:|
| `terraform fmt -check` | ✅ |
| `terraform validate` | ✅ |
| `terraform test` (13 test runs including storage_path_ids) | ✅ |

### Bicep / ARM

| Check | Status |
|-------|:------:|
| `az bicep build --file src/bicep/main.bicep` | ✅ |
| ARM parity (compiled JSON matches committed template) | ✅ |
| Pass-through annotations (≥5 `passThrough: true`) | ✅ |

### Schema Validation

| Check | Status |
|-------|:------:|
| `variables.example.yml` passes `variables.schema.json` | ✅ |
| Canonical layout value in example (`single` or `triple`) | ✅ |

### E2E Lab Tests

All 60 scenario × tool-path cells in the validation matrix above remain 🔲 (awaiting lab environment). These require physical Azure Local infrastructure and cannot be validated in CI.

**To reproduce this report:**

```powershell
# 1. PowerShell tests
Invoke-Pester .\tests\Test-SOFSDeployment.Tests.ps1 -Output Detailed

# 2. Terraform
Push-Location src/terraform
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test -test-directory=../../tests/terraform
Pop-Location

# 3. Bicep
az bicep build --file src/bicep/main.bicep --stdout | Out-Null

# 4. Schema
python3 -c "import yaml,json; from jsonschema import validate; validate(instance=yaml.safe_load(open('config/variables.example.yml')),schema=json.load(open('config/schema/variables.schema.json'))); print('PASS')"
```
