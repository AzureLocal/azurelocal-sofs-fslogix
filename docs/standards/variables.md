# Variable Standards

Conventions for the central configuration file and all variable naming across the repository.

---

## Central Config

The single source of truth is `config/variables.yml`. Copy from `config/variables.example.yml`.

### Format

- **YAML** with sectioned structure
- Clean, human-readable keys (no prefixes like `wsfc_sofs_`)
- 2-space indentation

### Sections

```yaml
azure:            # Azure subscription, resource group, location
keyvault:         # Key Vault name for secret resolution
azure_local:      # Azure Local cluster, custom location, networks, images, storage paths
vm:               # VM prefix, count, specs, admin creds, IPs
data_disks:       # Disk count and size for S2D pool
domain:           # AD domain config, join credentials, OU paths
dns_servers:      # DNS server list
sofs:             # SOFS role name, cluster name/IP, share name
s2d:              # Storage Spaces Direct volume config
cloud_witness:    # Cloud witness storage account
guest_config_engine:  # How to configure guests (ansible_create, ansible_existing, manual)
ansible_controller:   # Ansible controller VM details
tags:             # Resource tags
```

### Naming Rules

| Scope | Convention | Example |
|-------|-----------|---------|
| Top-level sections | `snake_case` | `azure_local`, `data_disks` |
| Keys within sections | `snake_case` | `subscription_id`, `volume_size_gb` |
| Per-VM maps | Zero-padded string keys | `"01"`, `"02"`, `"03"` |
| Booleans | Descriptive name | `role_enabled: true` |
| Secrets | `keyvault://` URI | `keyvault://kv-name/secret-name` |

---

## Key Vault References

Secrets are **never** stored as plain text in config files. Use the `keyvault://` URI format:

```yaml
vm:
  admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
domain:
  join_password: "keyvault://kv-platform-prod/domain-join-password"
```

At runtime, scripts resolve these via `Resolve-KeyVaultRef`:

1. Try `Az.KeyVault` PowerShell module (preferred)
2. Fallback to `az keyvault secret show` CLI
3. Hard fail if neither works (no interactive prompts)

---

## Compatibility

The PowerShell scripts include a **compatibility shim** that maps the new sectioned config into the legacy `compute_wsfc` / `wsfc_sofs_*` flat key format. This means:

- New `config/variables.yml` → works with all scripts
- Legacy `solution-sofs.yml` → also works (auto-detected)

The shim is transparent — downstream script logic is unchanged.

---

## Tool-Specific Parameter Files

| Tool | File | Location |
|------|------|----------|
| PowerShell | `variables.yml` | `config/` |
| Bicep | `main.bicepparam` | `infrastructure/bicep/` |
| Terraform | `terraform.tfvars` | `infrastructure/terraform/` |
| ARM | `azuredeploy.parameters.json` | `infrastructure/arm/` |
| Ansible | `inventory.yml` | `configure/ansible/inventory/` |
| Azure CLI | `.env` | `infrastructure/azure-cli/` |

All tool-specific parameter files should derive their values from the central `config/variables.yml`.
