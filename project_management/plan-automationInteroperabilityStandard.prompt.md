# Plan: Automation Interoperability Standard & Variable Framework

Create a portable automation interoperability standard ensuring all tools (Terraform, Bicep, ARM, PowerShell, Ansible) can deploy a SOFS cluster in **every configuration path** from the deployment guide — host volume layout (single vs. three), guest volume layout (Option A vs. Option B three-volume split), S2D resiliency (two-way vs. three-way), and guest config engine. Add missing variables, document CAF/WAF naming as guidance (not enforced), and design the standard for adoption across all AzureLocal repos.

---

## Phase 1: Create Automation Interoperability Standard

**New file:** `docs/standards/automation.md` — the core framework document.

**Sections:**

### 1. Deployment Path Matrix

A table mapping every configurable choice to each tool's support status:

| Choice | Values | Terraform | Bicep | ARM | PowerShell | Ansible |
|---|---|---|---|---|---|---|
| Host volume layout | `three_volumes` / `single_volume` | N/A (prereq) | N/A | N/A | N/A | N/A |
| Guest volume layout | `option_a` / `option_b` | Inventory var | N/A | N/A | Config var | Playbook var |
| S2D resiliency | `2` / `3` | Inventory var | N/A | N/A | Config var | Playbook var |
| Guest config engine | `powershell` / `ansible_create` / `ansible_existing` / `manual` | Supported | N/A | N/A | N/A (is engine) | N/A (is engine) |
| VM count, disk count/size | Configurable | Supported | Supported | Supported | Supported | Supported |
| NTFS permission groups | AD group names | Inventory var | N/A | N/A | Config var | Playbook var |
| SMB encryption | On/off | Inventory var | N/A | N/A | Config var | Playbook var |

> Terraform/Bicep/ARM = Phase 1 Azure provisioning only. Guest OS config (Phases 3–11) is PowerShell or Ansible.

### 2. Variable Contract

Rules that ALL tools must follow:

- Every deployment choice MUST exist as a variable in `config/variables.yml`
- Tool-specific parameter files (`.tfvars`, `.bicepparam`, `parameters.json`, `inventory.yml`) MUST be derivable from the central config
- New variables MUST be added to `variables.example.yml`, documented in `variables.md`, AND added to each tool's parameter file

### 3. Feature Parity Rules

- Phase 1 tools must support identical VM/disk/witness configs
- Phase 2 tools must support both guest volume layouts, both S2D resiliency levels, configurable permissions groups, and configurable SMB settings
- Adding a path to ONE tool requires adding it to ALL tools in the same phase (or explicitly marking "not yet supported" in the matrix)

### 4. Change Propagation Checklist

When adding a new variable:

1. Update `config/variables.example.yml`
2. Update `docs/reference/variables.md`
3. Update Terraform `variables.tf` + `terraform.tfvars.example`
4. Update Bicep `main.bicep` params + `main.bicepparam.example`
5. Update ARM `azuredeploy.parameters.example.json`
6. Update Ansible `inventory/hosts.example.yml`
7. Update PowerShell scripts to read new variable
8. Update the Deployment Path Matrix
9. Update or create tests
10. Commit with `feat:` or `docs:` prefix

### 5. Idempotency & Safety Contract

- All tools must be re-runnable
- All tools must support dry-run (`-WhatIf`, `terraform plan`, `--check`)
- All tools must validate inputs before executing
- All tools must log to `logs/`

### 6. Testing Contract

- Each tool must have validation tests
- `Test-SOFSDeployment.ps1` is the canonical validator
- Tests must cover both Option A and Option B
- CI must run lint + validate on every PR

### 7. Portability Note

Framework applies to all AzureLocal repos; each repo adopts with its own Deployment Path Matrix.

---

## Phase 2: Create CAF/WAF Naming & Tagging Reference

**New file:** `docs/standards/naming.md`

**Sections:**

### 1. CAF Resource Naming

Document `<resource-type>-<workload>-<environment>-<region>-<instance>` pattern with a table of every resource type this repo creates:

| Resource | CAF Prefix | Example |
|---|---|---|
| Resource group | `rg-` | `rg-iic-sofs-prod-eus-01` |
| Virtual machine | `vm-` | `vm-iic-sofs-01` |
| Network interface | `nic-` | `nic-iic-sofs-01` |
| Storage account | `st` | `stiicsolfswitnessprod01` |
| Key Vault | `kv-` | `kv-iic-sofs-prod-eus-01` |
| Data disk | `disk-` | `disk-iic-sofs-01-data1` |
| Storage path | `sp-` | `sp-iic-sofs-vol-01` |
| Cluster CNO | (AD object) | `iic-sofs` |
| SOFS access point | (AD object) | `iic-fslogix` |

Links to Microsoft CAF naming docs and abbreviation reference.

### 2. WAF Pillar Alignment

Map deployment guide design decisions to WAF pillars:

| WAF Pillar | Design Decision | Variable |
|---|---|---|
| **Reliability** | Three host volumes for fault isolation | `deployment.host_volume_layout` |
| **Reliability** | S2D mirror level | `s2d.data_copies` |
| **Reliability** | Anti-affinity rules | `sofs.anti_affinity_rule_name` |
| **Security** | Key Vault for secrets | `keyvault.*` |
| **Security** | SMB encryption | `sofs.smb_encryption` |
| **Cost** | Two-way vs. three-way mirror tradeoff | `s2d.data_copies` |
| **Operational Excellence** | Centralized config, tagging | `config/variables.yml`, `tags.*` |
| **Performance** | Same-VLAN network placement, S2D tuning | Architecture |

### 3. Tagging Standard

Required tags: `project`, `environment`, `workload`, `solution`. Recommended: `owner`, `costCenter`, `createdBy`.

---

## Phase 3: Update Central Config

**File:** `config/variables.example.yml`

Add these new sections/variables:

- **`deployment:`** — `host_volume_layout` (`three_volumes` | `single_volume`), `guest_volume_layout` (`option_a` | `option_b`)
- **`host_volumes:`** — `prefix`, `resiliency` (`two_way` | `three_way`), `size_tb`, `storage_pool_name` (for reference/validation; actual provisioning is a prereq)
- **`s2d.pool_name:`** — Guest S2D storage pool friendly name
- **`s2d.volumes:`** — Option B breakdown: `profiles` (name, size_gb), `odfc` (name, size_gb), `appdata` (name, size_gb)
- **`sofs.smb_encryption:`** — Boolean
- **`sofs.caching_mode:`** — Defaults to `None`
- **`sofs.shares:`** — Option B share names: `profiles`, `odfc`, `appdata`
- **`permissions:`** — `admin_group`, `users_group`, `avd_users_group`
- **`fslogix:`** — `enabled`, `profile_size_mb`, `volume_type`, `flip_flop_name`, `delete_local_profile`, `cloud_cache.enabled`, `cloud_cache.azure_provider`
- **`data_disks.dynamic:`** — Boolean (document dynamic provisioning intent)
- **`vm.os_disk_size_gb:`** — Make OS disk size explicit (default 127)

---

## Phase 4: Rewrite Variable Reference

**File:** `docs/reference/variables.md`

- Restructure to match all sections in `variables.example.yml` with columns: **Variable**, **Type**, **Description**, **Default**, **Valid Values**, **Phases**
- Add new sections: Deployment Architecture Choices, Host Volumes, S2D Volumes (Option B), SOFS Shares (Option B), Permissions, FSLogix
- Add **Deployment Path Decision Tree** showing which variables are active based on `deployment.guest_volume_layout`:
  - `option_a` → reads `s2d.volume_name`, `s2d.volume_size_gb`, `sofs.share_name`; ignores `s2d.volumes.*`, `sofs.shares.*`
  - `option_b` → reads `s2d.volumes.*`, `sofs.shares.*`; ignores `s2d.volume_name`, `sofs.share_name`
- Expand the Phase Consumption Matrix to cover all new variable groups across Phases 1–11

---

## Phase 5: Update Standards Index & Navigation

- **`docs/standards/index.md`** — Add rows for Automation and Naming to the standards table
- **`mkdocs.yml`** — Add `Automation: standards/automation.md` and `Naming: standards/naming.md` to the Standards nav section

---

## Phase 6: Update Solutions Standard

**File:** `docs/standards/solutions.md`

- Add **Deployment Path Support** section — require each IaC tool to declare supported deployment paths per the matrix in `automation.md`
- Add **Parameter File Derivation** section — document that tool-specific parameter files must be derivable from `config/variables.yml`
- Add **Conditional Resource Support** section — how each tool handles path conditionals: Terraform `count`/`for_each`, Bicep `if`, PowerShell `switch`, Ansible `when:`

---

## Files Summary

### Create

- `docs/standards/automation.md` — Interoperability standard
- `docs/standards/naming.md` — CAF/WAF naming reference

### Update

- `config/variables.example.yml` — Add ~30 new variables for all deployment paths
- `docs/reference/variables.md` — Full rewrite with all variables + decision tree
- `docs/standards/index.md` — Add new standard pages
- `mkdocs.yml` — Add new nav entries
- `docs/standards/solutions.md` — Add deployment path, parameter derivation, conditional sections

### Reference Only (no changes)

- `docs/reference/sofs-deployment-guide.md` — Source of truth for paths
- `src/terraform/variables.tf` — Tool code updates are separate work
- `src/bicep/main.bicep` — Tool code updates are separate work

---

## Verification

1. `mkdocs build` succeeds — all new pages render, nav includes Automation and Naming under Standards
2. Every deployment path choice from the deployment guide has a corresponding variable in `variables.example.yml` and a row in `variables.md`
3. Every variable in `variables.example.yml` is documented in `variables.md` and vice versa
4. The Deployment Path Matrix in `automation.md` covers all 5 tools × all deployment choices
5. The Change Propagation Checklist references every file that needs updating
6. Every Azure resource type created by automation appears in the naming table with CAF prefix and IIC example
7. Manual read-through confirms: "If I add a new deployment option, what exactly do I update and where?" is answered unambiguously

---

## Decisions

- **CAF naming** — Documentation only. Automation will NOT auto-generate resource names; users provide names guided by conventions.
- **Standards scope** — Portable. The framework is designed for adoption by all AzureLocal sister repos.
- **Host volume variables** — Included in config for validation/reporting; actual host provisioning remains a prerequisite done outside this repo's automation.
- **Tool code changes** — OUT OF SCOPE. This plan covers standards, config schema, and variable reference. Updating each tool's scripts to consume new variables is subsequent implementation work.

---

## Further Considerations

1. **Schema validation tooling** — A CI step that validates `variables.example.yml` against a JSON Schema would catch drift automatically. *Add to roadmap Milestone 4.*
2. **Config generation helper** — A script that reads `config/variables.yml` and generates `.tfvars`, `.bicepparam`, `parameters.json`, and Ansible inventory would eliminate manual translation. Terraform's `ansible-inventory.tf` already does this for Ansible. *Add to roadmap Milestone 3.*
3. **Option B Ansible support** — The current `configure-sofs-cluster.yml` likely only handles Option A. Adding Option B requires `when:` conditionals. *Track as Milestone 3 feature parity.*
