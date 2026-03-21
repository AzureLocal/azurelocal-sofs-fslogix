# Phase Ownership Matrix

This document maps each deployment phase to the tool responsible for executing it. All tools read from the same `config/variables.yml` and the Phase 0 preflight validates the configuration before any phase runs.

---

## 11-Phase Deployment Model

| Phase | Name | Owner Tool(s) | Description |
|:-----:|------|---------------|-------------|
| **0** | Preflight / Decision-Tree | PowerShell (`Resolve-Phase0Preflight`), Ansible (assert tasks) | Validates configuration, resolves canonical layout, emits ownership map and Cloud Cache topology |
| **1** | Azure Resources (Host) | Bicep/ARM (`main.bicep`), Terraform (`deploy-azure-resources.tf`) | Creates resource group, storage account, Key Vault references, Azure Local VM resources |
| **2** | Storage Paths (Host) | Bicep/ARM (`sofs-resources.bicep`), Terraform | Provisions Azure Local storage paths and maps VM-to-path assignments |
| **3** | Anti-Affinity | Ansible (`configure-sofs-cluster.yml`), PowerShell | Creates anti-affinity rule on the Azure Local host cluster via WinRM |
| **4** | Domain Join | (Handled by Azure Local VM provisioning) | VMs join Active Directory — prerequisite for clustering |
| **5** | Roles & Features | Ansible, PowerShell | Installs Failover-Clustering, FS-FileServer, and management tools on guest VMs |
| **6** | Failover Cluster | PowerShell (`Configure-SOFS-Cluster.ps1`), Ansible | Creates Windows Server Failover Cluster with configured resiliency |
| **7** | S2D & Volumes | PowerShell, Ansible | Enables Storage Spaces Direct, creates storage pool and virtual disks/volumes |
| **8** | SOFS Role & Shares | PowerShell, Ansible | Creates Scale-Out File Server role, access point, and SMB shares with permissions |
| **9** | SMB Encryption | PowerShell, Ansible | Configures SMB encryption on shares (SmbServerConfiguration) |
| **9b** | FSRM Quotas | PowerShell, Ansible | Installs FS-Resource-Manager, creates quota templates, applies auto-apply quotas to share paths |
| **9c** | Cloud Cache | PowerShell, Ansible | Builds CCDLocations registry value from SMB auto-providers + external providers |
| **10** | FSLogix Config | PowerShell | Outputs FSLogix profile container configuration and GPO guidance |
| **11** | Validation | PowerShell, Ansible | Verifies cluster health, node status, share accessibility |

---

## Tool Responsibilities

### Azure/Host Phases (1–2)

| Tool | Phases | Entry Point |
|------|:------:|-------------|
| **Bicep** | 1–2 | `src/bicep/main.bicep` → `sofs-resources.bicep` |
| **ARM** | 1–2 | `src/arm/azuredeploy.json` (compiled from Bicep) |
| **Terraform** | 1–2 | `src/terraform/*.tf` |

Guest-phase parameters (Phases 3–11) are declared in Bicep/ARM/Terraform as **pass-through** parameters. They are stored in deployment outputs or state but not consumed by the Azure/Host tool — they are forwarded to the guest configuration tool.

### Guest Phases (3–11)

| Tool | Phases | Entry Point |
|------|:------:|-------------|
| **PowerShell** | 0, 3–11 | `src/powershell/deploy/Configure-SOFS-Cluster.ps1` |
| **Ansible** | 0, 3–11 | `src/ansible/playbooks/configure-sofs-cluster.yml` |

Both guest tools implement the same phases with feature parity. Choose one based on your automation preference.

---

## Phase 0 Decision Tree

Phase 0 runs before any infrastructure deployment. It validates:

1. **Layout resolution** — Normalizes `option_a` → `single`, `option_b` → `triple` (legacy aliases)
2. **Resiliency vs. VM count** — Ensures `three_way` mirror has ≥ 3 VMs
3. **Storage path ambiguity** — Warns if both map and singular storage path IDs are set
4. **Cloud Cache prerequisites** — If enabled, validates that provider configuration exists
5. **Phase ownership emission** — Outputs which tool handles Azure/Host vs. Guest phases

### Cloud Cache Topology

When Cloud Cache is enabled, Phase 0 emits the provider topology:

| Mode | Condition | Behavior |
|------|-----------|----------|
| `providers_array` | `fslogix.cloud_cache.providers[]` has entries | Each provider appended to CCDLocations as `type={type},connectionString={cs}` |
| `legacy_azure_provider` | `fslogix.cloud_cache.azure_provider` is set (deprecated) | Single Azure Blob provider appended to CCDLocations |
| `disabled` | Cloud Cache not enabled | No CCDLocations generated; standard FSLogix profile path used |

---

## Pass-Through Parameter Contract

Bicep/ARM parameters annotated with `@metadata({ phase: 'guest', passThrough: true })` are:

- Declared in the Azure/Host template for parameter completeness
- Stored in deployment outputs for downstream consumption
- **Not consumed** by the Azure/Host deployment itself
- Forwarded to the guest configuration tool (PowerShell or Ansible)

See the `phaseOwnership` output in `main.bicep` for the runtime ownership map.

---

## Legacy Naming Deprecation Timeline

The migration from `option_a`/`option_b` to `single`/`triple` layout naming follows this schedule:

| Milestone | Version | Status | Description |
|-----------|---------|--------|-------------|
| Canonical values introduced | v1.0.0 | ✅ Done | `deployment.guest_layout` accepts `single` and `triple` as primary values |
| Legacy aliases supported | v1.0.0 | ✅ Done | `option_a` → `single`, `option_b` → `triple` mapped at Phase 0 with deprecation warning |
| Schema allows both | v1.0.0 | ✅ Done | `variables.schema.json` accepts canonical and legacy values via `enum` |
| Docs use canonical naming | v1.0.0 | ✅ Done | All markdown, diagrams, and examples use `single`/`triple` |
| Deprecation warning emitted | v1.0.0 | ✅ Done | PowerShell and Ansible emit `WARN` when legacy values are detected |
| Legacy aliases removed | v2.0.0 | ⬜ Planned | `option_a` and `option_b` values will be rejected; only `single`/`triple` accepted |

!!! warning "Migration action required before v2.0.0"
    If your `config/variables.yml` uses `guest_layout: "option_a"` or `guest_layout: "option_b"`, update to `single` or `triple` respectively. The v1.x compatibility shim will be removed in v2.0.0.

---

## Cross-Repository Dependencies

SOFS deployment depends on and aligns with work in these sibling repositories:

| Dependency | Repository | Issue | Relationship |
|------------|-----------|-------|-------------|
| AVD session host deployment | [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/azurelocal-avd) | #8 | AVD consumes SOFS shares; FSLogix profile path must match SOFS share UNC |
| Topology terminology alignment | [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/azurelocal-avd) | #36 | Canonical `single`/`triple` naming must match across both repos |
| Master variable registry | [AzureLocal/azurelocal-toolkit](https://github.com/AzureLocal/azurelocal-toolkit) | #4 | Variable names in `variables.yml` must align with the cross-repo registry |
| IaC maturity tracking | [AzureLocal/azurelocal-toolkit](https://github.com/AzureLocal/azurelocal-toolkit) | #5 | Phase ownership and tool parity tracked in the maturity dashboard |

SOFS issues should not be marked complete if canonical variable names or terminology mappings are unresolved in these linked dependencies.
