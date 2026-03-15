# Infrastructure — Phase 1: Azure Resource Provisioning

Deploy the Azure-side resources (resource group + diagnostic storage account) that support the SOFS/FSLogix solution on Azure Local.

> **Choose one** of the four IaC tools below — they all deploy the same resources.

---

## Tool Comparison

| Tool | Path | Best For |
|------|------|----------|
| [**Bicep**](./bicep/) | `infrastructure/bicep/` | Azure-native IaC — **recommended for new deployments** |
| [**ARM**](./arm/) | `infrastructure/arm/` | Legacy tooling that requires raw JSON templates |
| [**Terraform**](./terraform/) | `infrastructure/terraform/` | Multi-cloud strategy, GitOps workflows |
| [**Azure CLI**](./azure-cli/) | `infrastructure/azure-cli/` | Cross-platform CLI, quick-start scripting |

---

## What Gets Deployed

All four tools create identical resources:

| Resource | Description |
|----------|-------------|
| **Resource Group** | Container for all Azure-side SOFS resources |
| **Diagnostic Storage Account** | StorageV2 account for diagnostics and monitoring (Standard_LRS, HTTPS-only, TLS 1.2) |

---

## Configuration

All tools read parameters from `config/variables.yml`. Each tool also ships its own example parameters file for tool-specific use.

See [`config/README.md`](../config/README.md) for the full variable reference.

---

## Next Step

After infrastructure is deployed, proceed to [**Phase 2: Deploy**](../deploy/) to create the SOFS cluster role.
