# Variables & Secrets Reference

Complete list of every secret and variable used across CI/CD pipelines for SOFS + FSLogix deployment.

## Azure Identity / Authentication

| Variable | Description | Used By | Platform Reference |
|----------|-------------|---------|-------------------|
| `AZURE_CLIENT_ID` | Service principal / app registration client ID | Terraform, Bicep, PowerShell | GitHub Secret, GitLab Variable, ADO Variable Group |
| `AZURE_CLIENT_SECRET` | Service principal client secret (use OIDC instead when possible) | Terraform, Bicep, PowerShell | GitHub Secret, GitLab Variable (masked), ADO Variable Group (secret) |
| `AZURE_TENANT_ID` | Entra ID tenant ID | All tools | GitHub Secret, GitLab Variable, ADO Variable Group |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID | All tools | GitHub Secret, GitLab Variable, ADO Variable Group |

## Terraform-Specific

| Variable | Description | Used By | Platform Reference |
|----------|-------------|---------|-------------------|
| `ARM_CLIENT_ID` | Alias for `AZURE_CLIENT_ID` (Terraform convention) | Terraform | GitHub Secret, GitLab Variable |
| `ARM_CLIENT_SECRET` | Alias for `AZURE_CLIENT_SECRET` | Terraform | GitHub Secret (masked), GitLab Variable (masked) |
| `ARM_TENANT_ID` | Alias for `AZURE_TENANT_ID` | Terraform | GitHub Secret, GitLab Variable |
| `ARM_SUBSCRIPTION_ID` | Alias for `AZURE_SUBSCRIPTION_ID` | Terraform | GitHub Secret, GitLab Variable |
| `TF_STATE_RESOURCE_GROUP` | Resource group for Terraform state storage account | Terraform | GitHub Variable, GitLab Variable, ADO Variable Group |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name for `.tfstate` | Terraform | GitHub Variable, GitLab Variable, ADO Variable Group |
| `TF_STATE_CONTAINER` | Blob container name (usually `tfstate`) | Terraform | GitHub Variable, GitLab Variable, ADO Variable Group |

## Ansible-Specific

| Variable | Description | Used By | Platform Reference |
|----------|-------------|---------|-------------------|
| `ANSIBLE_VAULT_PASSWORD` | Password for Ansible Vault encrypted files | Ansible | GitHub Secret, GitLab Variable (masked/file), ADO Variable Group (secret) |
| `WINRM_USERNAME` | Windows remote management username | Ansible | GitHub Secret, GitLab Variable |
| `WINRM_PASSWORD` | Windows remote management password | Ansible | GitHub Secret (masked), GitLab Variable (masked) |

## PowerShell-Specific

| Variable | Description | Used By | Platform Reference |
|----------|-------------|---------|-------------------|
| `VM_ADMIN_PASSWORD` | Local admin password for SOFS VMs | PowerShell, Terraform | Key Vault (`sofs-vm-admin-password`) |
| `DOMAIN_JOIN_PASSWORD` | Domain join service account password | PowerShell, Ansible | Key Vault (`domain-join-password`) |

## Key Vault Secrets

These are stored in Azure Key Vault and resolved at runtime via `keyvault://` URIs.

| Secret Name | Key Vault | Description | Consumers |
|-------------|-----------|-------------|-----------|
| `sofs-vm-admin-password` | `kv-platform-prod` | VM local admin password | PowerShell, Terraform |
| `domain-join-password` | `kv-platform-prod` | Domain join credential | PowerShell, Ansible |
| `storage-account-key` | `kv-platform-prod` | Witness storage account key | PowerShell |

## Environment-Specific Overrides

| Variable | Staging Value (example) | Production Value (example) |
|----------|------------------------|---------------------------|
| `AZURE_SUBSCRIPTION_ID` | `00000000-0000-0000-0000-000000000001` | `00000000-0000-0000-0000-000000000002` |
| Key Vault Name | `kv-platform-staging` | `kv-platform-prod` |
| Resource Group | `rg-sofs-azl-eus-staging` | `rg-sofs-azl-eus-01` |

---

See also:
- [GitHub Secrets setup](github-secrets.md)
- [GitLab Variables setup](gitlab-variables.md)
- [Azure DevOps Variable Groups](azure-devops-variable-groups.md)
- [Key Vault Integration](keyvault-integration.md)
