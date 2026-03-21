# Variables

!!! info "This page has moved"
    The complete variable reference — including all configuration sections, single/triple layout examples, type information, defaults, and phase mapping — is now at **[Variable Reference](../reference/variables.md)**.

## Quick Start

1. Copy the example file:
    ```powershell
    cp config/variables.example.yml config/variables.yml
    ```

2. Edit `config/variables.yml` with your values

3. **Never commit `config/variables.yml`** — it is excluded by `.gitignore`

See [Variable Reference](../reference/variables.md) for every parameter, organized by YAML section with types, defaults, and deployment phase mapping.

## Next Steps

- [Variable Reference](../reference/variables.md) — Complete configuration reference
- Choose your deployment tool: [Terraform](terraform.md) | [Bicep](bicep.md) | [ARM](arm.md) | [PowerShell](powershell.md) | [Ansible](ansible.md)