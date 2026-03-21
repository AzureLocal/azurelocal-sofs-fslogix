# Bicep Deployment

![Bicep](https://img.shields.io/badge/-Bicep-0078D4?logo=microsoftazure&logoColor=white) ![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d) ![CI/CD: Examples Available](https://img.shields.io/badge/CI%2FCD-examples_available-blueviolet?logo=githubactions&logoColor=white)

## Overview

Subscription-scope Bicep deployment that creates all Azure-side resources for the SOFS guest cluster using **Azure Verified Modules (AVM)** from the public Bicep registry for the resource group and cloud witness storage account.

Microsoft references used for this implementation:

- Bicep docs: https://learn.microsoft.com/azure/azure-resource-manager/bicep/
- AVM overview: https://azure.github.io/Azure-Verified-Modules/
- AVM Bicep quickstart: https://azure.github.io/Azure-Verified-Modules/usage/quickstart/bicep/

### Capability

| Capability | Supported |
|-----------|:---------:|
| Azure resource provisioning | ✅ |
| Domain join (JsonADDomainExtension) | ✅ |
| Per-VM storage path mapping | ✅ |
| Guest OS configuration | Delegates to PS/Ansible |
| AVM modules (RG + Storage) | ✅ |

### Phase Ownership

| Phase Group | Ownership |
|-------------|-----------|
| Phase 0 (decision tree) | Parameter validation only |
| Phases 1-2 (Azure/Host plane) | Implemented in Bicep modules |
| Phases 3-11 (Guest OS plane) | Delegated to PowerShell or Ansible |

---

## Resources Created

| Resource | Module |
|----------|--------|
| Resource Group | AVM `br/public:avm/res/resources/resource-group` |
| Cloud Witness Storage Account | AVM `br/public:avm/res/storage/storage-account` |
| Arc Machine Placeholders | `sofs-resources.bicep` |
| NICs (compute logical network) | `sofs-resources.bicep` |
| Data Disks (S2D pool) | `sofs-resources.bicep` |
| VM Instances (with per-VM storage paths) | `sofs-resources.bicep` |
| Domain Join Extensions | `sofs-resources.bicep` |

---

## Prerequisites

- Azure CLI >= 2.50 with Bicep CLI
- Azure CLI authenticated (`az login`)
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `main.bicep` | Subscription-scope wrapper — AVM RG + storage, calls sofs-resources module |
| `sofs-resources.bicep` | Resource-group-scope module — VMs, NICs, data disks, domain join extensions |
| `main.bicepparam` | Bicep parameters file (reference only — never commit secrets) |
| `Deploy-SOFS-Azure.ps1` | Orchestrator script — reads config, resolves KV, deploys |

## Architecture

```
main.bicep (subscription scope)
├── AVM: avm/res/resources/resource-group
├── AVM: avm/res/storage/storage-account (cloud witness)
└── sofs-resources.bicep (resource-group scope)
    ├── Microsoft.HybridCompute/machines[]               — Arc placeholders
    ├── Microsoft.AzureStackHCI/networkInterfaces[]       — NICs
    ├── Microsoft.AzureStackHCI/virtualHardDisks[]        — Data disks
    ├── Microsoft.AzureStackHCI/VirtualMachineInstances[] — VMs (per-VM storage paths)
    └── Microsoft.HybridCompute/machines/extensions[]     — Domain join
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
2. **Verify domain join** — the `JsonADDomainExtension` is deployed automatically
3. **Run guest configuration:**

```powershell
.\src\powershell\deploy\Configure-SOFS-Cluster.ps1 -ConfigPath "config\variables.yml"
```

---

## Next Steps

- [PowerShell](powershell.md) — Guest OS configuration (Phases 3–11)
- [Ansible](ansible.md) — Alternative guest configuration via Ansible
- [Validation](validation.md) — Verify the deployment
