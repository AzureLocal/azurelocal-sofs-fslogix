# Secrets Management

How to store and reference secrets for SOFS + FSLogix CI/CD pipelines.

## Principles

1. **Never commit secrets** — `config/variables.yml` is gitignored; use `keyvault://` URIs for all sensitive values
2. **Least privilege** — service principals get only the roles they need (Key Vault Secrets User, Contributor on the resource group)
3. **Prefer OIDC / federated credentials** over client secrets where supported
4. **Rotate regularly** — Key Vault handles rotation; CI/CD platform secrets should be reviewed quarterly

## Secret Categories

| Category | Examples | Where to Store |
|----------|----------|---------------|
| Azure identity | Client ID, Tenant ID, Subscription ID | CI/CD platform variables |
| Azure credentials | Client Secret or OIDC federation | CI/CD platform secrets (masked) |
| VM passwords | Local admin, domain join | Azure Key Vault only |
| Ansible vault | Vault password | CI/CD platform secret |
| Terraform state | Storage account key (if not using MSI) | CI/CD platform secret |

## Platform Setup Guides

Detailed per-platform instructions:

- [GitHub Secrets](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/examples/secrets/github-secrets.md) — Repo secrets, org secrets, OIDC setup
- [GitLab Variables](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/examples/secrets/gitlab-variables.md) — Project/group variables, protected/masked flags
- [Azure DevOps Variable Groups](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/examples/secrets/azure-devops-variable-groups.md) — Variable groups, service connections, Key Vault linking

## Azure Key Vault Integration

For production, secrets like VM passwords and domain join credentials live in Key Vault:

```yaml
# config/variables.yml
vm:
  admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
domain:
  join_password: "keyvault://kv-platform-prod/domain-join-password"
```

Each CI/CD platform can pull these at pipeline runtime. See [Key Vault Integration](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/examples/secrets/keyvault-integration.md) for per-platform details.

## OIDC / Workload Identity Federation (Recommended)

Instead of storing a client secret, configure federated credentials:

```
Azure AD App Registration
  → Certificates & secrets
    → Federated credentials
      → Add credential
        → GitHub Actions / GitLab CI / other
```

This eliminates secret rotation for the CI/CD identity itself.

### GitHub Actions OIDC

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

No `AZURE_CLIENT_SECRET` needed.

## Complete Variables Reference

See [Variables Reference](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/examples/secrets/variables-reference.md) for a full table of every secret and variable name, which tools use it, and where to store it.

## Best Practices

- **Mask secrets in logs** — all platforms support this; GitLab and Azure DevOps do it automatically for masked/secret variables
- **Use environment scoping** — production secrets should only be available to production pipelines
- **Audit access** — Key Vault provides access logs; enable diagnostic settings to a Log Analytics workspace
- **Separate Key Vaults per environment** — `kv-platform-staging` vs `kv-platform-prod`
- **Never echo secrets** — use `::add-mask::` (GitHub), `[MaskOutput]` (GitLab), or avoid `Write-Host` for secret values

<!-- TODO: Add Key Vault diagnostic settings example -->
<!-- TODO: Add secret rotation automation example -->
