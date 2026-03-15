# Bicep – SOFS & FSLogix Deployment

Bicep templates for deploying Azure-side resources that support the SOFS/FSLogix solution on Azure Local.

---

## Templates

| File | Description |
|------|-------------|
| `main.bicep` | Entry-point template; orchestrates module deployments |
| `main.bicepparam.example` | Example parameters file |
| `modules/resourceGroup.bicep` | Resource group creation (subscription scope) |
| `modules/storageAccount.bicep` | Diagnostic / backup storage account |

---

## Prerequisites

- **Azure CLI** >= 2.50 with the Bicep CLI (`az bicep install`).
- Azure subscription with **Contributor** or higher RBAC.

---

## Quick Start

1. Build and validate:
   ```bash
   az bicep build --file main.bicep
   ```

2. Copy and edit the parameters file:
   ```bash
   cp main.bicepparam.example main.bicepparam
   # Edit main.bicepparam with your values
   ```

3. Deploy:
   ```bash
   az deployment sub create \
     --location eastus \
     --template-file main.bicep \
     --parameters main.bicepparam
   ```

---

## Parameters Reference

See `main.bicepparam.example` for all parameters and descriptions.
