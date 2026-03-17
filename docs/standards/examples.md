# Examples & IIC Policy

> **Canonical reference:** [Fictional Company Policy (full)](https://azurelocal.cloud/standards/fictional-company-policy)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Policy

All examples, sample configurations, walkthroughs, and documentation across every AzureLocal repository use **one** fictional company: **Infinite Improbability Corp (IIC)**.

!!! warning "Mandatory"
    Never use `contoso`, `fabrikam`, `adventure-works`, `woodgrove`, `example.com`, or any real customer name.
    **IIC only** — in every repo, every example, every sample config.

---

## IIC Reference Card

| Attribute | Value |
|-----------|-------|
| **Full Name** | Infinite Improbability Corp |
| **Abbreviation** | IIC |
| **Domain (public)** | `improbability.cloud` / `iic.cloud` |
| **Domain (on-prem AD)** | `iic.local` |
| **NetBIOS Name** | `IMPROBABLE` |
| **Entra ID Tenant** | `improbability.onmicrosoft.com` |
| **Email Pattern** | `user@improbability.cloud` |
| **Origin** | A nod to *The Hitchhiker's Guide to the Galaxy* |

---

## SOFS Naming Patterns

### Cluster & Nodes

| Resource | Pattern | Example |
|----------|---------|---------|
| Cluster | `iic-clus<NN>` | `iic-clus01` |
| Node | `iic-<clus>-n<NN>` | `iic-01-n01` through `iic-01-n06` |
| iDRAC/BMC | `iic-<clus>-bmc<NN>` | `iic-01-bmc01` |

### Azure Resources

| Resource | Pattern | Example |
|----------|---------|---------|
| Resource Group | `rg-iic-sofs-<##>` | `rg-iic-sofs-01` |
| Key Vault | `kv-iic-<purpose>` | `kv-iic-platform` |
| Storage Account | `stiic<purpose><##>` | `stiicwitness01` |
| Log Analytics | `law-iic-<purpose>-<##>` | `law-iic-monitor-01` |

### Active Directory

| Resource | Pattern | Example |
|----------|---------|---------|
| OU path | `OU=<unit>,DC=iic,DC=local` | `OU=Servers,DC=iic,DC=local` |
| Service account | `svc.iic.<purpose>` | `svc.iic.deploy` |
| Group | `grp-iic-<purpose>` | `grp-iic-sofs-admins` |

### IP Addresses

| Network | Range | Usage |
|---------|-------|-------|
| Management | `10.0.0.0/24` | `10.0.0.11`–`10.0.0.16` (nodes) |
| Storage | `10.0.1.0/24` | `10.0.1.11`–`10.0.1.16` (RDMA/SMB) |
| Compute | `10.0.2.0/24` | VM traffic |

---

## Real Identities

These are **not** fictional — use for authorship and attribution:

| Name | Usage |
|------|-------|
| **Azure Local Cloud** | Community project, GitHub org, `azurelocal.cloud` |
| **Hybrid Cloud Solutions** | Author/maintainer LLC, script headers, copyright |

---

## Usage Examples

### In `config/variables.example.yml`

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-iic-sofs-01"
  location: "eastus"

keyvault:
  name: "kv-iic-platform"

azure_local:
  cluster_name: "iic-clus01"
  cluster_domain: "iic.local"
```

### In Documentation

> Infinite Improbability Corp's production SOFS cluster (`iic-clus01`) serves
> FSLogix profile containers for 500 AVD session hosts across six Azure Local nodes.

### In Scripts

```powershell
# Example: Connect to IIC cluster
$clusterName = "iic-clus01"
$domain = "iic.local"
$credential = Get-Secret -Vault "kv-iic-platform" -Name "svc-iic-deploy"
```

---

## Enforcement

- **PR review**: Reviewers flag any use of `contoso`, `fabrikam`, or other non-IIC names
- **Config validation**: `variables.example.yml` uses IIC naming patterns in all placeholders
- **CI**: Vale linting rules can flag non-IIC fictional company names (when configured)
