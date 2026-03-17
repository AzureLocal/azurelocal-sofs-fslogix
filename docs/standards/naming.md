# Naming & Tagging Standard

CAF (Cloud Adoption Framework) resource naming conventions and WAF (Well-Architected Framework) pillar alignment for SOFS deployments on Azure Local. Naming is **documentation-only guidance** — it is not enforced by automation.

---

## CAF Resource Naming

All Azure resources follow the pattern:

```
<resource-type>-<workload>-<environment>-<region>-<instance>
```

### Resource Naming Table

| Resource | CAF Prefix | Pattern | Example |
|----------|-----------|---------|---------|
| Resource group | `rg-` | `rg-<workload>-<platform>-<region>-<instance>` | `rg-iic-sofs-azl-eus-01` |
| Virtual machine | `vm-` | `vm-<org>-sofs-<instance>` | `vm-iic-sofs-01` |
| Network interface | `nic-` | `nic-<org>-sofs-<instance>` | `nic-iic-sofs-01` |
| Data disk | `disk-` | `disk-<org>-sofs-<instance>-data<n>` | `disk-iic-sofs-01-data1` |
| Storage account (witness) | `st` | `stsofswitness<org><instance>` | `stsofswitnessiic01` |
| Key Vault | `kv-` | `kv-<org>-<workload>-<env>-<region>-<instance>` | `kv-iic-sofs-prod-eus-01` |
| Storage path | `sp-` | `sp-<org>-sofs-csv<n>` | `sp-iic-sofs-csv01` |
| Cluster CNO | *(AD object)* | `<org>-sofs` | `iic-sofs` |
| SOFS access point | *(AD object)* | `<org>-fslogix` | `iic-fslogix` |
| Anti-affinity rule | *(cluster property)* | `SOFS-AntiAffinity` | `SOFS-AntiAffinity` |

!!! info "CAF reference"
    See [Microsoft CAF naming conventions](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) and the [abbreviation reference](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations).

---

## WAF Pillar Alignment

How the SOFS design decisions map to the Well-Architected Framework pillars:

| WAF Pillar | Design Decision | Variable / Config |
|------------|----------------|-------------------|
| **Reliability** | Three host volumes for fault isolation | `deployment.host_volume_layout` |
| **Reliability** | S2D mirror level (two-way or three-way) | `s2d.data_copies` |
| **Reliability** | Anti-affinity rules — each VM on different host | `sofs.anti_affinity_rule_name` |
| **Reliability** | Cloud witness for cluster quorum | `cloud_witness.name` |
| **Security** | Key Vault for all secrets | `keyvault.name` |
| **Security** | SMB encryption option | `sofs.smb_encryption` |
| **Security** | NTFS ACLs with CREATOR OWNER isolation | `permissions.users_group` |
| **Cost Optimization** | Two-way vs. three-way mirror raw cost tradeoff | `s2d.data_copies` |
| **Cost Optimization** | VM sizing (right-size vCPU + memory) | `vm.processors`, `vm.memory_mb` |
| **Operational Excellence** | Centralized config file, single source of truth | `config/variables.yml` |
| **Operational Excellence** | Required tags on all resources | `tags.*` |
| **Operational Excellence** | Idempotent, re-runnable automation | [Automation Standard](automation.md) |
| **Performance Efficiency** | Same-VLAN network placement | Architecture decision |
| **Performance Efficiency** | S2D HwTimeout and auto-replace tuning | Guest config (Phase 7) |

!!! info "WAF reference"
    See [Azure Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/) for the full pillar definitions and assessment tools.

---

## Tagging Standard

### Required Tags

Every Azure resource created by this repo's automation MUST have these tags:

| Tag | Description | Example |
|-----|------------|---------|
| `project` | Project identifier | `SOFS` |
| `environment` | Deployment environment | `production`, `staging`, `dev` |
| `workload` | Workload type | `FSLogix` |
| `solution` | Solution identifier | `sofs-azure-local` |

### Recommended Tags

| Tag | Description | Example |
|-----|------------|---------|
| `owner` | Team or individual responsible | `Platform Team` |
| `costCenter` | Billing cost center | `IT-12345` |
| `createdBy` | Automation tool that created the resource | `terraform`, `bicep`, `powershell` |
| `deploymentDate` | ISO 8601 date of deployment | `2026-03-17` |

### Tag Variables

Tags are defined in `config/variables.yml` under the `tags` section:

```yaml
tags:
  project: "SOFS"
  environment: "production"
  workload: "FSLogix"
  solution: "sofs-azure-local"
```

All IaC tools must read from this section and apply tags to every resource they create.
