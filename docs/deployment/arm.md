# ARM Template Deployment

![ARM](https://img.shields.io/badge/-ARM_Templates-0078D4?logo=microsoftazure&logoColor=white) ![Status: Untested](https://img.shields.io/badge/status-untested-red) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d) ![CI/CD: None](https://img.shields.io/badge/CI%2FCD-none-lightgrey)

!!! note "Bicep recommended for new deployments"
    ARM JSON templates are maintained for environments that require JSON (legacy tooling, policy constraints). For new deployments, use [Bicep](bicep.md) instead — it compiles to the same ARM JSON but is more readable and maintainable.

## Overview

ARM templates can deploy **all the same Azure-side resources as Bicep** — Bicep literally compiles to ARM JSON. This means ARM has full capability for resource groups, Arc VMs, NICs, data disks, cloud witness, and domain join extensions.

### Capability vs Code Status

| Capability | Can Do? | Current Code |
|-----------|:---:|:---:|
| Azure resource provisioning | ✅ (same as Bicep) | ❌ Partial — RG + witness only |
| Domain join (JsonADDomainExtension) | ✅ natively | ❌ Not implemented |
| Guest OS configuration | Delegates to PS | Delegates |

!!! warning "Current template is incomplete"
    The ARM template (`azuredeploy.json`) currently only creates the resource group and cloud witness storage account. It does **not** create VMs, NICs, or data disks. A complete ARM deployment would include all the resources shown in the [Bicep](bicep.md) deployment. This is an implementation gap, not a technology limitation.

**What happens after ARM:** Guest OS configuration requires the [PowerShell](powershell.md) script or [Ansible](ansible.md) playbook.

---

## Prerequisites

- Azure CLI >= 2.50 or Az PowerShell >= 9.0
- Azure subscription with Contributor or higher RBAC
- All [general prerequisites](prerequisites.md) met

---

## File Inventory

| File | Purpose |
|------|---------|
| `azuredeploy.json` | ARM template (subscription scope) — currently creates RG + witness storage |
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

## Code Gaps

The following resources are **not yet implemented** in the ARM template but are fully supported by ARM:

- `Microsoft.HybridCompute/machines` — Arc machine placeholders
- `Microsoft.AzureStackHCI/networkInterfaces` — NICs on compute logical network
- `Microsoft.AzureStackHCI/virtualHardDisks` — S2D data disks
- `Microsoft.AzureStackHCI/virtualMachineInstances` — VM instances
- `Microsoft.HybridCompute/machines/extensions` — Domain join extension (`JsonADDomainExtension`)

See the [Bicep](bicep.md) deployment for the complete resource set — the ARM equivalent would be structurally identical.

---

## Post-Deployment

After ARM deploys the Azure resources:

1. **Verify resources** created in Azure portal
2. **Domain join** the VMs (manual — not yet automated in ARM template)
3. **Run guest configuration** using [PowerShell](powershell.md) or [Ansible](ansible.md)

---

## Next Steps

- [PowerShell](powershell.md) — Guest OS configuration
- [Validation](validation.md) — Verify the deployment
