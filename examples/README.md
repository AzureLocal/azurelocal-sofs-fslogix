# Examples

CI/CD pipeline examples, secrets management guides, and environment configs for SOFS + FSLogix deployments.

## Directory Layout

```
examples/
├── pipelines/
│   ├── github-actions/          # GitHub Actions workflow examples
│   │   ├── deploy-terraform.yml.example
│   │   ├── deploy-bicep.yml.example
│   │   ├── deploy-ansible.yml.example
│   │   └── deploy-powershell.yml.example
│   ├── gitlab/                  # GitLab CI pipeline examples
│   │   ├── deploy-terraform.gitlab-ci.yml.example
│   │   ├── deploy-bicep.gitlab-ci.yml.example
│   │   ├── deploy-ansible.gitlab-ci.yml.example
│   │   └── deploy-powershell.gitlab-ci.yml.example
│   └── azure-devops/            # Azure DevOps pipeline examples
│       ├── deploy-terraform.yml.example
│       ├── deploy-bicep.yml.example
│       ├── deploy-ansible.yml.example
│       └── deploy-powershell.yml.example
├── secrets/
│   ├── github-secrets.md             # GitHub repo/org secrets setup
│   ├── gitlab-variables.md           # GitLab CI/CD variables setup
│   ├── azure-devops-variable-groups.md  # Azure DevOps variable groups
│   ├── keyvault-integration.md       # Key Vault integration per platform
│   └── variables-reference.md        # Complete variables/secrets reference
└── configs/
    ├── production.yml.example         # Production environment config
    └── staging.yml.example            # Staging / lab environment config
```

## Usage

1. Pick your CI/CD platform (`pipelines/<platform>/`)
2. Copy the `.example` file for the tool you use (Terraform, Bicep, Ansible, or PowerShell)
3. Configure secrets per the guides in `secrets/`
4. Optionally use the environment configs in `configs/` as a starting point

## Documentation

Full guides in the docs site:

- [CI/CD Pipelines](../docs/guides/cicd-pipelines.md)
- [Runner & Agent Setup](../docs/guides/runner-setup.md)
- [Secrets Management](../docs/guides/secrets-management.md)
