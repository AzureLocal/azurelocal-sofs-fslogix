# Infrastructure Standards

> **Canonical reference:** [Infrastructure Standards (full)](https://azurelocal.cloud/standards/infrastructure/)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Overview

Standards for Infrastructure as Code (IaC), Terraform state management, and deployment processes for the SOFS + FSLogix solution.

---

## Infrastructure Pipeline

```mermaid
flowchart LR
    A[Generate Variables] --> B[Validate Config]
    B --> C[Plan Infrastructure]
    C --> D[Review Changes]
    D --> E[Apply Changes]
    E --> F[Update State]
```

---

## State Management

| Principle | Rule |
|-----------|------|
| Remote state | Store Terraform state in Azure Storage Account |
| State locking | Enable locking during all operations |
| Backup | Regular state file backups before destructive operations |
| Naming | `sofs-<env>.tfstate` (e.g., `sofs-prod.tfstate`) |

---

## IaC Tool Parity

All tools must produce **identical infrastructure** when given the same configuration values:

| Tool | Primary Format | State Management |
|------|---------------|-----------------|
| Bicep | `.bicep` / `.bicepparam` | ARM deployment history |
| Terraform | `.tf` / `.tfvars` | Remote state in Azure Storage |
| ARM | `.json` | ARM deployment history |
| PowerShell | `.ps1` | Config-driven, logged |
| Ansible | `.yml` | Inventory-based |

---

## SOFS-Specific Infrastructure

| Convention | Rule |
|-----------|------|
| Primary IaC tool | Bicep |
| Config source | `config/variables.yml` (single source of truth) |
| Parameter derivation | All tool-specific param files derived from central config |
| Deployment phases | Azure foundation → Domain join → Guest config (Phases 1–11) |
| Storage design | Shared VHDs on Cluster Shared Volumes |

### Deployment Phases

| Phase | Scope | Tools |
|-------|-------|-------|
| Phase 1: Azure Foundation | Resource groups, networking, Key Vault | Bicep, Terraform, ARM |
| Phase 2: Domain Join | AD join, OU placement | PowerShell, Ansible |
| Phases 3–11: Guest Config | SOFS roles, volumes, FSLogix, permissions | PowerShell, Ansible |

---

## Related Standards

- [Infrastructure Generation & Deployment Process](https://azurelocal.cloud/standards/infrastructure/infrastructure-generation-deployment-process)
- [State Management](https://azurelocal.cloud/standards/infrastructure/state-management)
- [Solution Development Standard](solutions.md)
- [Variable Standards](variables.md)
- [Automation Interoperability](automation.md)
