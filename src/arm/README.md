# ARM – SOFS & FSLogix Deployment

ARM JSON templates for deploying Azure-side resources supporting the SOFS/FSLogix solution on Azure Local.

> For new deployments, Bicep is recommended over raw ARM JSON. Use this folder if you need JSON templates for tooling that does not yet support Bicep.

---

## Templates

| File | Description |
|------|-------------|
| `azuredeploy.json` | Main ARM template (subscription scope) |
| `azuredeploy.parameters.example.json` | Example parameters file |

---

## Prerequisites

- **Azure CLI** >= 2.50 _or_ **Az PowerShell** >= 9.0.
- Azure subscription with **Contributor** or higher RBAC.

---

## Quick Start with Azure CLI

```bash
az deployment sub create \
  --location eastus \
  --template-file azuredeploy.json \
  --parameters azuredeploy.parameters.json
```

## Quick Start with PowerShell

```powershell
New-AzSubscriptionDeployment `
  -Location "eastus" `
  -TemplateFile "azuredeploy.json" `
  -TemplateParameterFile "azuredeploy.parameters.json"
```

---

## Parameters Reference

See `azuredeploy.parameters.example.json` for all parameters and descriptions.
