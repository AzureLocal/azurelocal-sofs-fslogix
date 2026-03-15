# GitHub Actions — Secrets Configuration

How to configure secrets for SOFS deployment pipelines in GitHub Actions.

## Repository Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret**.

### Required Secrets

| Secret | Description | Used By |
|--------|-------------|---------|
| `ARM_CLIENT_ID` | Service principal application (client) ID | Terraform |
| `ARM_CLIENT_SECRET` | Service principal client secret | Terraform |
| `ARM_TENANT_ID` | Azure AD tenant ID | Terraform, Bicep, PowerShell |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID | Terraform |
| `AZURE_CLIENT_ID` | Same SP — used by azure/login action (OIDC) | Bicep, PowerShell |
| `AZURE_CLIENT_SECRET` | SP secret for PowerShell login | PowerShell |
| `AZURE_TENANT_ID` | Azure AD tenant ID | Bicep, PowerShell |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | Bicep, PowerShell |
| `ANSIBLE_VAULT_PASSWORD` | Ansible vault decryption password | Ansible |

### Optional Secrets

| Secret | Description | Used By |
|--------|-------------|---------|
| `WINRM_USERNAME` | WinRM username for Ansible | Ansible |
| `WINRM_PASSWORD` | WinRM password for Ansible | Ansible |

## Organization Secrets

If deploying across multiple repos, configure at the org level:
**Organization Settings → Secrets and variables → Actions**

Share `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID` across repos — they rarely change.

## OIDC / Federated Credentials (Recommended for Bicep)

Instead of storing `AZURE_CLIENT_SECRET`, use GitHub OIDC:

1. In Azure AD, create a federated credential on your app registration
2. Set the issuer to `https://token.actions.githubusercontent.com`
3. Set the subject to `repo:IIC-Org/azurelocal-sofs-fslogix:ref:refs/heads/main`
4. Remove `AZURE_CLIENT_SECRET` from secrets — no longer needed

See [docs/guides/secrets-management.md](../../docs/guides/secrets-management.md) for details.

## Environment Secrets

For production approval gates, use GitHub Environments:

1. **Settings → Environments → New environment → `production`**
2. Add required reviewers
3. Move deployment secrets here — they're only available to jobs targeting this environment

<!-- TODO: Add screenshot of GitHub secrets configuration -->
<!-- TODO: Add example of environment protection rules -->
