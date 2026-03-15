# Contributing

Thank you for contributing to **azurelocal-sofs-fslogix**! Please follow these guidelines to keep contributions consistent and high quality.

---

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). By participating you agree to abide by its terms.

---

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Stable, reviewed code only. Protected branch. |
| `dev` | Integration branch for in-progress work. |
| `feature/<short-description>` | New features or tool additions. |
| `fix/<short-description>` | Bug fixes. |
| `docs/<short-description>` | Documentation-only changes. |

---

## Submitting a Pull Request

1. Fork the repository (external contributors) or create a branch from `dev` (team members).
2. Make your changes, following the conventions below.
3. Ensure all linting / syntax checks pass locally (see [Validation](#validation)).
4. Open a PR against the `dev` branch with a clear title and description.
5. At least one approving review is required before merging.

---

## Folder Conventions

Each automation-tool folder (`powershell/`, `azure-cli/`, `bicep/`, `arm/`, `terraform/`, `ansible/`) should:

- Contain its own `README.md` explaining what the scripts/templates do and how to run them.
- Include an example parameters file (`.example` extension) so credentials are never committed.
- Follow the naming conventions for its ecosystem (see below).

---

## Naming Conventions

### PowerShell
- Scripts: `Verb-Noun.ps1` (approved verbs only — `Get-Verb` to check).
- Functions: `Verb-Noun` inside scripts or modules.
- Variables: `$PascalCase`.

### Azure CLI / Bash
- Script files: `kebab-case.sh`.
- Variables: `UPPER_SNAKE_CASE` for environment variables, `lower_snake_case` for locals.

### Bicep
- Files: `camelCase.bicep` for modules, `main.bicep` for entry points.
- Parameters / variables: `camelCase`.
- Resources: `camelCase` symbolic names.

### ARM (JSON)
- Follow the [ARM template best practices](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/best-practices).
- Use `parameters`, `variables`, and `outputs` sections consistently.

### Terraform
- Files: `snake_case.tf`.
- Resource names: `snake_case`.
- Variable names: `snake_case`.

### Ansible
- Playbooks: `kebab-case.yml`.
- Variables: `snake_case`.
- Role names: `snake_case`.

---

## Validation

Before opening a PR, verify your changes locally:

### PowerShell
```powershell
# Syntax check all scripts
Get-ChildItem -Path ./powershell -Filter *.ps1 -Recurse |
    ForEach-Object { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors); $errors }

# PSScriptAnalyzer (install once: Install-Module PSScriptAnalyzer)
Invoke-ScriptAnalyzer -Path ./powershell -Recurse
```

### Azure CLI / Bash
```bash
# ShellCheck (install: apt/brew install shellcheck)
shellcheck azure-cli/*.sh
```

### Bicep
```bash
az bicep build --file bicep/main.bicep
```

### ARM
```bash
az deployment group validate \
  --resource-group <rg> \
  --template-file arm/azuredeploy.json \
  --parameters arm/azuredeploy.parameters.example.json
```

### Terraform
```bash
cd terraform
terraform fmt -check -recursive
terraform validate
```

### Ansible
```bash
ansible-lint ansible/playbooks/
```

---

## Security

- **Never commit secrets, passwords, or credentials.**
- Use example/placeholder values in parameter files (`.example` suffix).
- Use Azure Key Vault references or environment variables for secrets at runtime.
- Follow the [principle of least privilege](https://learn.microsoft.com/en-us/azure/security/fundamentals/identity-management-best-practices#use-role-based-access-control) when assigning RBAC roles in templates.

---

## Documentation

- Update `docs/` when adding new features or changing behaviour.
- Keep `README.md` files in each tool folder current.
- Use present-tense, imperative sentences in documentation (e.g., "Run the script" not "Running the script").
