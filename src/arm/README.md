# ARM — SOFS & FSLogix Deployment

![Status: Untested](https://img.shields.io/badge/status-untested-red)

ARM JSON templates for deploying Azure-side resources supporting the SOFS/FSLogix solution on Azure Local.

> **This ARM template is a compiled artifact.** It is generated from the Bicep
> source in `src/bicep/` using `az bicep build`. Do **not** edit
> `azuredeploy.json` by hand — regenerate it instead.

---

## Templates

| File | Description |
|------|-------------|
| `azuredeploy.json` | Main ARM template (subscription scope) — compiled from Bicep |
| `azuredeploy.parameters.example.json` | Example parameters file (all 30+ params) |

---

## Regenerating the ARM Template

Whenever the Bicep source changes, recompile:

```bash
az bicep build -f src/bicep/main.bicep --outfile src/arm/azuredeploy.json
```

Or use the helper script:

```powershell
.\src\arm\Build-ARM-Template.ps1
```

---

## Prerequisites

- **Azure CLI** >= 2.50 _or_ **Az PowerShell** >= 9.0.
- **Bicep CLI** >= 0.41 (bundled with Azure CLI, or install standalone).
- Azure subscription with **Contributor** or higher RBAC.

---

## Quick Start with Azure CLI

```bash
az deployment sub create \
  --location eastus \
  --template-file azuredeploy.json \
  --parameters @azuredeploy.parameters.json
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

See `azuredeploy.parameters.example.json` for all parameters with example values.
All parameters mirror the Bicep source — see `src/bicep/main.bicep` for
`@description` metadata and allowed values.
