# Variable Standards

> **Full reference:** [Variable Reference](../reference/variables.md)  
> **Central standard:** [Variable Management Standard](https://azurelocal.cloud/docs/implementation/04-variable-management-standard)  
> **Last Updated:** 2026-03-17

---

## Overview

This repository uses a **single central configuration file** — `config/variables.yml` — as the source of truth for all deployment automation. Copy from `config/variables.example.yml` to get started.

---

## Naming Rules

| Rule | Standard | Example |
|------|----------|---------|
| Top-level sections | `snake_case` | `azure_local`, `data_disks` |
| Keys within sections | `snake_case` | `subscription_id`, `volume_size_gb` |
| Pattern | `^[a-z][a-z0-9_]*$` | — |
| Max length | 50 characters | — |
| Per-resource maps | Zero-padded string keys | `"01"`, `"02"` |
| Booleans | Descriptive names | `role_enabled: true` |
| Secrets | `keyvault://` URI format | `keyvault://kv-iic-platform/admin-password` |

---

## Config File Structure

```
config/
├── variables.example.yml        # Template with IIC examples (committed)
├── variables.yml                # Your actual config (gitignored)
└── schema/
    └── variables.schema.json    # JSON Schema for CI validation
```

---

## Key Vault Resolution

Secrets are never stored in plaintext. Use this URI format:

```yaml
credentials:
  admin_password: "keyvault://kv-iic-platform/admin-password"
```

Scripts resolve `keyvault://` URIs at runtime via `Resolve-KeyVaultRef`.

---

## CI Validation

Every PR validates `config/variables.example.yml` against `config/schema/variables.schema.json` using the `validate-config.yml` workflow. The JSON Schema enforces required sections and data types.

---

## Detailed Reference

For the complete variable catalog — every section, type, default, and deployment phase mapping — see:

- **[Variable Reference](../reference/variables.md)** — per-variable documentation
- **[Variable Management Standard](https://azurelocal.cloud/docs/implementation/04-variable-management-standard)** — org-wide governance
- **[Variable Management Suite](https://azurelocal.cloud/standards/variable-management/)** — registry, schema validation, workflows
- Key Vault secret resolution
- Tool-specific parameter mapping
