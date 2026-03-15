# Azure DevOps — Variable Groups & Service Connections

How to configure variables and service connections for SOFS deployment pipelines in Azure DevOps.

## Service Connections (Recommended for Bicep)

**Project Settings → Service connections → New service connection → Azure Resource Manager**

1. Select **Workload Identity federation (automatic)** or **Service principal (manual)**
2. Name it `sofs-azure-connection`
3. Scope to the target subscription / resource group
4. Reference in pipelines: `azureSubscription: sofs-azure-connection`

This is the preferred approach for Bicep and ARM pipelines — no secrets in variable groups.

## Variable Groups

**Pipelines → Library → + Variable group**

### sofs-terraform

| Variable | Value | Secret |
|----------|-------|:------:|
| `ARM_CLIENT_ID` | `<service principal app id>` | ❌ |
| `ARM_CLIENT_SECRET` | `<service principal secret>` | ✅ |
| `ARM_TENANT_ID` | `<tenant id>` | ❌ |
| `ARM_SUBSCRIPTION_ID` | `<subscription id>` | ❌ |

### sofs-powershell

| Variable | Value | Secret |
|----------|-------|:------:|
| `AZURE_CLIENT_ID` | `<service principal app id>` | ❌ |
| `AZURE_CLIENT_SECRET` | `<service principal secret>` | ✅ |
| `AZURE_TENANT_ID` | `<tenant id>` | ❌ |
| `AZURE_SUBSCRIPTION_ID` | `<subscription id>` | ❌ |

### sofs-ansible

| Variable | Value | Secret |
|----------|-------|:------:|
| `ANSIBLE_VAULT_PASSWORD` | `<vault password>` | ✅ |

## Link Variable Group to Key Vault

Instead of storing secrets in Azure DevOps, link a variable group directly to Key Vault:

1. Create variable group → toggle **Link secrets from an Azure key vault as variables**
2. Select your service connection and Key Vault (`kv-platform-prod`)
3. Choose which secrets to expose as variables
4. Secrets are fetched at pipeline runtime — never stored in Azure DevOps

## Environments

For approval gates:
1. **Pipelines → Environments → New environment → `production`**
2. Add **Approvals and checks** → Required approvers
3. Use `deployment` jobs targeting this environment in your pipeline

## Pipeline Permissions

Lock down variable groups:
1. **Library → variable group → Pipeline permissions**
2. Only allow specific pipelines to access the group

<!-- TODO: Add screenshot of variable group linked to Key Vault -->
<!-- TODO: Add example of approval gate configuration -->
