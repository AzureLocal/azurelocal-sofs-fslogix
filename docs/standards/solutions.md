# Solution Development Standards

> **Canonical reference:** [Solution Development Standard (full)](https://azurelocal.cloud/standards/solutions/solution-development-standard)  
> **Applies to:** All AzureLocal solution repositories  
> **Last Updated:** 2026-03-17

---

## Deployment Path Support

Each IaC tool must declare which deployment paths it supports. See the [Automation Interoperability Standard](automation.md) for the full Deployment Path Matrix.

| Tool | Phase 1 (Azure) | Domain Join | Guest Config (Phases 3–11) | Option A | Option B |
|------|:---:|:---:|:---:|:---:|:---:|
| **Terraform** | ✅ | ✅ | Delegates | ✅ | ✅ |
| **Bicep** | ✅ | ✅ | Delegates | ✅ | ✅ |
| **ARM** | ✅ | ✅ | Delegates | ✅ | ✅ |
| **PowerShell** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Ansible** | ✅ | ✅ | ✅ | ✅ | ✅ |

!!! warning "Delegates"
    "Delegates" means the Phase 1 tool provisions Azure resources but does not configure the guest OS. A separate tool (PowerShell or Ansible) handles Phases 3–11.

---

## Parameter File Derivation

All tool-specific parameter files MUST be derivable from `config/variables.yml`:

| Tool | Parameter File | Derivation |
|------|---------------|-----------|
| Terraform | `src/terraform/terraform.tfvars` | Map YAML sections to HCL variables |
| Bicep | `src/bicep/main.bicepparam` | Map YAML sections to Bicep parameters |
| ARM | `src/arm/azuredeploy.parameters.json` | Map YAML sections to ARM parameter schema |
| PowerShell | *(reads config directly)* | `ConvertFrom-Yaml` or shim from legacy format |
| Ansible | `src/ansible/inventory/hosts.yml` | Map YAML sections to `group_vars` |

The central config is the **single source of truth**. Tool-specific files are convenience copies that should be regenerable.

---

## Conditional Resource Support

Each tool handles deployment path branching differently:

| Tool | Mechanism | Example |
|------|-----------|---------|
| **Terraform** | `count` / `for_each` with condition | `count = var.guest_volume_layout == "option_b" ? 3 : 1` |
| **Bicep** | `if` condition on resource | `resource volume '...' = if (guestVolumeLayout == 'option_b') { ... }` |
| **ARM** | `condition` property on resource | `"condition": "[equals(parameters('guestVolumeLayout'), 'option_b')]"` |
| **PowerShell** | `switch` / `if` block | `if ($config.deployment.guest_volume_layout -eq 'option_b') { ... }` |
| **Ansible** | `when:` clause on task | `when: guest_volume_layout == 'option_b'` |

All tools must produce **identical infrastructure** when given the same configuration values, regardless of the conditional mechanism used.
