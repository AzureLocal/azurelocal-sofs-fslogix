# ARM Template Deployment

![ARM](https://img.shields.io/badge/-ARM_Templates-0078D4?logo=microsoftazure&logoColor=white) ![Status: Untested](https://img.shields.io/badge/status-untested-red) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

!!! note "Bicep recommended for new deployments"
    ARM JSON templates are maintained for environments that require JSON (legacy tooling, policy constraints). For new deployments, use [Bicep](bicep.md) instead — it compiles to the same ARM JSON but is more readable and maintainable.

## Overview

Subscription-scope ARM JSON templates that create the same Azure-side resources as the Bicep deployment: resource group, Arc VMs, NICs, data disks, and cloud witness storage account.

**Phases covered:** 1–2 (Azure resource provisioning and VM creation)

**What happens after ARM:** Guest OS configuration (Phases 3–11) requires the [PowerShell](powershell.md) script or [Ansible](ansible.md) playbook.

---

## Prerequisites

- Azure CLI >= 2.50 or Az PowerShell >= 9.0
- Azure subscription with Contributor or higher RBAC
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `azuredeploy.json` | Main ARM template (subscription scope) |
| `azuredeploy.parameters.example.json` | Example parameters file |

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

## Post-Deployment

After ARM deploys the Azure resources:

1. **Verify VMs** are running
2. **Domain join** the VMs
3. **Run guest configuration** using [PowerShell](powershell.md) or [Ansible](ansible.md)

---

## Next Steps

- [PowerShell](powershell.md) — Guest OS configuration (Phases 3–11)
- [Validation](validation.md) — Verify the deployment
