# Bicep Deployment

![Bicep](https://img.shields.io/badge/-Bicep-0078D4?logo=microsoftazure&logoColor=white) ![Status: In Progress](https://img.shields.io/badge/status-in_progress-yellow) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d) ![CI/CD: Examples Available](https://img.shields.io/badge/CI%2FCD-examples_available-blueviolet?logo=githubactions&logoColor=white)

## Overview

Subscription-scope Bicep deployment that creates all Azure-side resources for the SOFS guest cluster. Bicep compiles to ARM JSON but is significantly more readable and maintainable.

### Capability vs Code Status

| Capability | Can Do? | Current Code |
|-----------|:---:|:---:|
| Azure resource provisioning | ✅ | ✅ Full |
| Domain join (JsonADDomainExtension) | ✅ natively | ❌ Not yet implemented |
| Guest OS configuration | Delegates to PS | Delegates |

!!! info "Domain join is a TODO, not a limitation"
    Bicep can natively deploy the `JsonADDomainExtension` extension on `Microsoft.HybridCompute/machines`. This is a standard Azure resource deployment. The current Bicep code does not implement it yet.

**What happens after Bicep:** Guest OS configuration requires the [PowerShell](powershell.md) script or [Ansible](ansible.md) playbook.

---

## Resources Created

| Resource | Module |
|----------|--------|
| Resource Group | `main.bicep` |
| Arc Machine Placeholders | `sofs-resources.bicep` |
| NICs (compute logical network) | `sofs-resources.bicep` |
| Data Disks (S2D pool) | `sofs-resources.bicep` |
| VM Instances | `sofs-resources.bicep` |
| Cloud Witness Storage Account | `witness-storage.bicep` |

---

## Prerequisites

- Azure CLI >= 2.50 with Bicep CLI
- Azure CLI authenticated (`az login`)
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `main.bicep` | Subscription-scope wrapper — creates RG, calls modules |
| `sofs-resources.bicep` | Resource-group-scope module — VMs, NICs, data disks |
| `witness-storage.bicep` | Cloud witness storage account |
| `main.bicepparam` | Example parameters (reference only — never commit secrets) |
| `Deploy-SOFS-Azure.ps1` | Orchestrator script — reads config, resolves KV, deploys |

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

---

## Setup

### 1. Configure Parameters

```powershell
cd src/bicep
cp main.bicepparam.example main.bicepparam
```

Edit `main.bicepparam` with values from your `config/variables.yml`.

### 2. Set Secrets

The `Deploy-SOFS-Azure.ps1` wrapper resolves Key Vault secrets automatically. If deploying manually, pass secrets as secure parameters:

```powershell
az deployment sub create `
    --location eastus `
    --template-file main.bicep `
    --parameters main.bicepparam `
    --parameters adminPassword="$(az keyvault secret show --vault-name kv-platform-prod --name sofs-vm-admin-password --query value -o tsv)"
```

---

## Deployment

### Recommended: Orchestrator Script

```powershell
# Dry run (validate templates):
.\Deploy-SOFS-Azure.ps1 -WhatIf

# Full deployment:
.\Deploy-SOFS-Azure.ps1
```

The script reads `config/variables.yml`, resolves Key Vault secrets, and runs `az deployment sub create`.

### Manual: Azure CLI

```powershell
az deployment sub create `
    --location eastus `
    --template-file main.bicep `
    --parameters main.bicepparam
```

### Manual: Az PowerShell

```powershell
New-AzSubscriptionDeployment `
    -Location "eastus" `
    -TemplateFile "main.bicep" `
    -TemplateParameterFile "main.bicepparam"
```

---

## Post-Deployment

After Bicep deploys the Azure resources:

1. **Verify VMs** are running in Azure portal
2. **Domain join** the VMs (manual or via Arc extension — not yet automated in this repo's Bicep)
3. **Run guest configuration:**

```powershell
.\src\powershell\Configure-SOFS-Cluster.ps1
```

This handles anti-affinity rules, failover clustering, S2D, SOFS role, SMB share, and NTFS permissions.

---

## Next Steps

- [PowerShell](powershell.md) — Guest OS configuration (Phases 3–11)
- [Ansible](ansible.md) — Alternative guest configuration via Ansible
- [Validation](validation.md) — Verify the deployment
