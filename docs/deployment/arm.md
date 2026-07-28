# ARM Template Deployment

![ARM](https://img.shields.io/badge/-ARM_Templates-0078D4?logo=microsoftazure&logoColor=white) ![Status: Tested](https://img.shields.io/badge/status-tested-brightgreen) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d) ![CI/CD: Examples Available](https://img.shields.io/badge/CI%2FCD-examples_available-blueviolet?logo=githubactions&logoColor=white)

> [!NOTE]
> **Bicep recommended for new deployments**
> ARM JSON templates are maintained for environments that require JSON (legacy tooling, policy constraints). For new deployments, use [Bicep](bicep.md) instead — it compiles to the same ARM JSON but is more readable and maintainable.
>
## Overview

The ARM template is **compiled from Bicep** (`az bicep build`) and deploys all the same Azure-side resources. This ensures feature parity — any capability added to Bicep is automatically available in ARM.

Microsoft references used for this implementation:

- ARM template deployments: https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-cli
- Bicep docs (source of ARM compilation): https://learn.microsoft.com/azure/azure-resource-manager/bicep/
- AVM overview: https://azure.github.io/Azure-Verified-Modules/

### Capability

| Capability | Supported |
|-----------|:---------:|
| Azure resource provisioning | ✅ |
| Domain join (JsonADDomainExtension) | ✅ |
| Per-VM storage path mapping | ✅ |
| Guest OS configuration | Delegates to PS/Ansible |

### Phase Ownership

| Phase Group | Ownership |
|-------------|-----------|
| Phase 0 (decision tree) | Parameter validation only |
| Phases 1-2 (Azure/Host plane) | Implemented by compiled ARM template |
| Phases 3-11 (Guest OS plane) | Delegated to PowerShell or Ansible |

---

## Prerequisites

- Azure CLI >= 2.50 or Az PowerShell >= 9.0
- Azure subscription with Contributor or higher RBAC
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `azuredeploy.json` | ARM template (compiled from Bicep) — full resource deployment |
| `azuredeploy.parameters.example.json` | Example parameters file with all 50 parameters |
| `build-arm.ps1` | Script to recompile ARM JSON from Bicep source |

---

## Setup

```powershell
cd src/arm
cp azuredeploy.parameters.example.json azuredeploy.parameters.json
```

Edit `azuredeploy.parameters.json` with values from your `config/variables.yml`. See `azuredeploy.parameters.example.json` for all parameters and descriptions.

---

## Deployment

### Azure CLI

```powershell
az deployment sub create `
    --location eastus `
    --template-file azuredeploy.json `
    --parameters azuredeploy.parameters.json
```

### Az PowerShell

```powershell
New-AzSubscriptionDeployment `
    -Location "eastus" `
    -TemplateFile "azuredeploy.json" `
    -TemplateParameterFile "azuredeploy.parameters.json"
```

---

## Recompiling from Bicep

When the Bicep source changes, regenerate the ARM template:

```powershell
cd src/arm
.\build-arm.ps1
# Or manually:
az bicep build --file ..\bicep\main.bicep --outfile azuredeploy.json
```

---

## Post-Deployment

After ARM deploys the Azure resources:

1. **Verify VMs** are running in Azure portal
2. **Verify domain join** — the `JsonADDomainExtension` is deployed automatically
3. **Run guest configuration** using [PowerShell](powershell.md) or [Ansible](ansible.md)

---

## Next Steps

- [PowerShell](powershell.md) — Guest OS configuration
- [Validation](validation.md) — Verify the deployment
