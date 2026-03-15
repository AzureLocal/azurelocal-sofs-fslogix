# Azure Key Vault Integration

How to pull secrets from Azure Key Vault in CI/CD pipelines across all three platforms.

This is the recommended approach for production — secrets live in Key Vault, not in your CI/CD platform.

## Overview

The SOFS deployment uses `keyvault://` URIs in `config/variables.yml`:

```yaml
vm:
  admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
domain:
  join_password: "keyvault://kv-platform-prod/domain-join-password"
```

PowerShell scripts resolve these at runtime. For IaC tools (Terraform, Bicep), Key Vault is referenced natively.

---

## GitHub Actions

### Option 1: Azure Key Vault action

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- uses: azure/get-keyvault-secrets@v1
  with:
    keyvault: kv-platform-prod
    secrets: 'sofs-vm-admin-password, domain-join-password'
  id: kv-secrets

- name: Use secret
  run: echo "Password retrieved"  # ${{ steps.kv-secrets.outputs.sofs-vm-admin-password }}
```

### Option 2: Az CLI in script

```yaml
- run: |
    SECRET=$(az keyvault secret show --vault-name kv-platform-prod --name sofs-vm-admin-password --query value -o tsv)
    echo "::add-mask::$SECRET"
    echo "VM_ADMIN_PASSWORD=$SECRET" >> $GITHUB_ENV
```

---

## GitLab CI

### Azure Key Vault integration (Premium)

GitLab Premium has native Key Vault integration:
**Settings → CI/CD → Variables → Add variable → Type: Azure Key Vault**

### Script-based (all tiers)

```yaml
before_script:
  - az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID
  - export VM_ADMIN_PASSWORD=$(az keyvault secret show --vault-name kv-platform-prod --name sofs-vm-admin-password --query value -o tsv)
```

---

## Azure DevOps

### Option 1: Variable group linked to Key Vault (Recommended)

See [azure-devops-variable-groups.md](azure-devops-variable-groups.md#link-variable-group-to-key-vault).

### Option 2: AzureKeyVault task

```yaml
- task: AzureKeyVault@2
  inputs:
    azureSubscription: sofs-azure-connection
    KeyVaultName: kv-platform-prod
    SecretsFilter: 'sofs-vm-admin-password,domain-join-password'
    RunAsPreJob: true
```

Secrets are available as `$(sofs-vm-admin-password)` in subsequent steps.

---

## Key Vault Access Policy

The service principal or managed identity used by your pipeline needs:

| Permission | Scope |
|------------|-------|
| `Get` | Secrets |
| `List` | Secrets (optional — only if you enumerate) |

Grant via RBAC:
```bash
# Example: IIC production Key Vault
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <service-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-sofs-azl-eus-01/providers/Microsoft.KeyVault/vaults/kv-platform-prod
```

<!-- TODO: Add Terraform Key Vault data source example -->
<!-- TODO: Add Bicep Key Vault reference example -->
