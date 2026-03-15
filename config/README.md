# Configuration

Central variables file — the **single source of truth** for all deployment phases.

---

## Usage

```bash
cp variables.example.yml variables.yml
# Edit variables.yml with your environment values
```

> **Do not** commit `variables.yml` — it is excluded by `.gitignore`.

---

## Variable Reference

### Azure Subscription

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `subscription_id` | string | Azure subscription ID | `00000000-...` |
| `resource_group` | string | Target Azure resource group | `rg-azurelocal-prod` |
| `location` | string | Azure region | `eastus` |

### Azure Local Cluster

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `cluster_name` | string | Failover cluster network name | `AZLHCI-CLUSTER` |
| `cluster_resource_group` | string | Resource group of the Arc-registered cluster | `rg-azurelocal-prod` |

### SOFS Configuration

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `sofs_name` | string | SOFS cluster role name | `SOFS01` |
| `share_name` | string | SMB share name | `FSLogixProfiles` |
| `share_path` | string | Path on the CSV | `C:\ClusterStorage\Volume1\FSLogixProfiles` |

### Active Directory

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `domain_fqdn` | string | AD domain FQDN | `contoso.local` |
| `ou_path` | string | OU for the SOFS computer object | `OU=Servers,DC=contoso,DC=local` |

### FSLogix / AVD

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `avd_users_group` | string | AD group for FSLogix profile access | `AVD-Users` |

### Diagnostics

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `diag_storage_account` | string | Diagnostic storage account (globally unique) | `stazlhcidiag001` |

### Tags

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `tags.environment` | string | Environment tag | `production` |
| `tags.owner` | string | Owner tag | `platform-team` |

### Ansible

| Variable | Type | Description |
|----------|------|-------------|
| `ansible.winrm_transport` | string | WinRM transport (`kerberos`, `ntlm`, `basic`) |
| `ansible.cert_validation` | string | Certificate validation (`ignore`, `validate`) |
| `ansible.sofs_nodes` | list | SOFS cluster node hostnames and IPs |
| `ansible.avd_session_hosts` | list | AVD session host hostnames and IPs |

---

## Which Phases Use Which Variables?

| Variable Group | Infrastructure (Phase 1) | Deploy (Phase 2) | Configure (Phase 3) | Tests (Phase 4) |
|---------------|:---:|:---:|:---:|:---:|
| Azure Subscription | ✅ | | | |
| Azure Local Cluster | | ✅ | ✅ | |
| SOFS Configuration | | ✅ | ✅ | ✅ |
| Active Directory | | ✅ | ✅ | |
| FSLogix / AVD | | | ✅ | ✅ |
| Diagnostics | ✅ | | | |
| Tags | ✅ | | | |
| Ansible | | | ✅ | |
