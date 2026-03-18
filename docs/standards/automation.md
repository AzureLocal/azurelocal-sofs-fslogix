# Automation Interoperability Standard

This standard ensures all deployment tools — Terraform, Bicep, ARM, PowerShell, and Ansible — can deploy a SOFS cluster in **every configuration path** from the [deployment guide](../reference/sofs-design-and-deployment-guide.md). It defines the variable contract, feature parity rules, and change propagation process.

!!! tip "Portability"
    This framework is designed for adoption across **all AzureLocal repos**. Each repo implements its own Deployment Path Matrix while following the same rules.

---

## Deployment Path Matrix

Every configurable deployment choice and each tool's support status:

| Choice | Valid Values | Terraform | Bicep | ARM | PowerShell | Ansible |
|--------|-------------|-----------|-------|-----|------------|---------|
| Host volume layout | `three_volumes` / `single_volume` | N/A (prereq) | N/A | N/A | N/A | N/A |
| Guest volume layout | `option_a` / `option_b` | Inventory var | N/A | N/A | Config var | Playbook var |
| S2D resiliency | `2` / `3` | Inventory var | N/A | N/A | Config var | Playbook var |
| Guest config engine | `powershell` / `ansible_create` / `ansible_existing` / `manual` | Supported | N/A | N/A | N/A (is engine) | N/A (is engine) |
| VM count, disk count/size | Configurable integers (2–16 VMs) | Supported | Supported | Supported | Supported | Supported |
| Domain join | AD domain + OU + credentials | Supported | Supported | Supported | Supported | Supported |
| Per-VM storage paths | Storage path resource IDs | Supported | Supported | Supported | Supported | Supported |
| Cloud Cache providers | `providers[]` array | Inventory var | N/A | N/A | Config var | Playbook var |
| FSRM quotas | Size + type per share | N/A | N/A | N/A | Config var | Playbook var |
| NTFS permission groups | AD group names | Inventory var | N/A | N/A | Config var | Playbook var |
| SMB encryption | `true` / `false` | Inventory var | N/A | N/A | Config var | Playbook var |

!!! note "Phase boundaries"
    Terraform, Bicep, and ARM handle **Phases 1–2 and Phase 4** (Azure resource provisioning + domain join). Guest OS configuration (Phases 3, 5–11) is always PowerShell or Ansible.

---

## Variable Contract

Rules that **all tools must follow**:

1. **Single source of truth** — Every deployment choice MUST exist as a variable in `config/variables.yml`.
2. **Derivability** — Tool-specific parameter files (`.tfvars`, `.bicepparam`, `parameters.json`, `inventory.yml`) MUST be derivable from the central config.
3. **Documentation** — New variables MUST be added to `variables.example.yml`, documented in [Variable Reference](../reference/variables.md), AND added to each tool's parameter file.
4. **Secrets** — Secrets MUST use `keyvault://` URI format and be resolved at runtime. Never store secrets in plain text.
5. **Naming** — All variable keys use `snake_case`. Top-level sections group related settings.

---

## Feature Parity Rules

| Scope | Rule |
|-------|------|
| **Phase 1–2 tools** | Must support identical VM, disk, NIC, cloud witness, and domain join configurations |
| **Phase 2+ tools** | Must support both guest volume layouts, both S2D resiliency levels, Cloud Cache providers, FSRM quotas, configurable permission groups, and configurable SMB settings |
| **New paths** | Adding a deployment path to ONE tool requires adding it to ALL tools in the same phase — or explicitly marking "not yet supported" in the matrix |
| **Defaults** | All tools must produce identical infrastructure when given the same `variables.yml` |

---

## Change Propagation Checklist

When adding a new variable, complete every step:

| # | Action | File(s) |
|---|--------|---------|
| 1 | Add variable with example value | `config/variables.example.yml` |
| 2 | Document variable | `docs/reference/variables.md` |
| 3 | Add to JSON Schema | `config/schema/variables.schema.json` |
| 4 | Add to Terraform variables + example | `src/terraform/variables.tf`, `terraform.tfvars.example` |
| 5 | Add to Bicep params + example | `src/bicep/main.bicep`, `main.bicepparam.example` |
| 6 | Add to ARM parameters + example | `src/arm/azuredeploy.parameters.example.json` |
| 7 | Add to Ansible inventory + example | `src/ansible/inventory/hosts.example.yml` |
| 8 | Update PowerShell scripts to read variable | `src/powershell/*.ps1` |
| 9 | Update the Deployment Path Matrix | This page |
| 10 | Update or create tests | `tests/` |
| 11 | Commit with `feat:` or `docs:` prefix | — |

---

## Idempotency & Safety Contract

All tools MUST meet these requirements:

| Requirement | Details |
|-------------|---------|
| **Re-runnable** | Running the same tool twice with the same config produces no errors and no unintended changes |
| **Dry-run support** | `-WhatIf` (PowerShell), `terraform plan` (Terraform), `what-if` (Bicep/ARM), `--check` (Ansible) |
| **Input validation** | Validate all inputs before executing any destructive operation |
| **Logging** | Write structured logs to `logs/` with timestamps |
| **Error handling** | Fail fast with clear error messages; do not leave resources in a half-configured state |

---

## Testing Contract

| Requirement | Details |
|-------------|---------|
| **Validation tests** | Each tool must have validation tests that verify the deployment matches the config |
| **Canonical validator** | `tests/Test-SOFSDeployment.ps1` is the post-deployment validation script |
| **Coverage** | Tests must cover both Option A (single volume) and Option B (three volumes) |
| **CI integration** | `lint` + `validate` checks must run on every PR via GitHub Actions |
| **Schema validation** | `config/variables.example.yml` must pass `config/schema/variables.schema.json` validation |

---

## Conditional Resource Logic

How each tool handles deployment path conditionals:

| Tool | Mechanism | Example |
|------|-----------|---------|
| **Terraform** | `count` / `for_each` with condition | `count = var.guest_volume_layout == "option_b" ? 3 : 1` |
| **Bicep** | `if` condition on resource | `resource volume '...' = if (guestVolumeLayout == 'option_b') { ... }` |
| **ARM** | `condition` property | `"condition": "[equals(parameters('guestVolumeLayout'), 'option_b')]"` |
| **PowerShell** | `switch` / `if` | `if ($config.deployment.guest_volume_layout -eq 'option_b') { ... }` |
| **Ansible** | `when:` clause | `when: guest_volume_layout == 'option_b'` |

---

## Cross-Repo Adoption

To adopt this standard in another AzureLocal repository:

1. Copy this page to `docs/standards/automation.md`
2. Replace the Deployment Path Matrix with the repo's own tool × choice matrix
3. Create a `config/variables.example.yml` following the Variable Contract
4. Add a `config/schema/variables.schema.json` for validation
5. Add a CI workflow that validates config against the schema
6. Link to this standard from the repo's `docs/standards/index.md`
