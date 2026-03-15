# GitLab CI/CD — Variables Configuration

How to configure CI/CD variables for SOFS deployment pipelines in GitLab.

## Project-Level Variables

Go to **Settings → CI/CD → Variables → Add variable**.

### Required Variables

| Variable | Description | Protected | Masked | Used By |
|----------|-------------|:---------:|:------:|---------|
| `ARM_CLIENT_ID` | Service principal app ID | ✅ | ❌ | Terraform |
| `ARM_CLIENT_SECRET` | Service principal secret | ✅ | ✅ | Terraform |
| `ARM_TENANT_ID` | Azure AD tenant ID | ✅ | ❌ | All |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID | ✅ | ❌ | All |
| `AZURE_CLIENT_ID` | Same SP — for az login | ✅ | ❌ | Bicep, PowerShell |
| `AZURE_CLIENT_SECRET` | SP secret | ✅ | ✅ | Bicep, PowerShell |
| `AZURE_TENANT_ID` | Azure AD tenant ID | ✅ | ❌ | Bicep, PowerShell |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID | ✅ | ❌ | Bicep, PowerShell |
| `ANSIBLE_VAULT_PASSWORD` | Vault decryption password | ✅ | ✅ | Ansible |

### Variable Settings

- **Protected**: Only available on protected branches (main). Set this for all deployment secrets.
- **Masked**: Hidden in job logs. Set this for passwords and secrets.
- **Environment scope**: Limit to specific environments (e.g., `production`).

## Group-Level Variables

If deploying across multiple projects, set shared variables at the group level:
**Group → Settings → CI/CD → Variables**

Share `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID` across projects.

## File-Type Variables

For Ansible vault passwords, you can use a **File** variable type:
1. Set variable type to **File**
2. GitLab writes the value to a temp file and sets the variable to the file path
3. Use directly: `--vault-password-file $ANSIBLE_VAULT_PASSWORD`

## Environments

For approval gates:
1. **Operate → Environments → New environment → `production`**
2. Under **Settings**, enable **Required approvals**
3. Scope sensitive variables to this environment

<!-- TODO: Add screenshot of GitLab variables panel -->
<!-- TODO: Add example of environment approval rules -->
