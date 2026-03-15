# Variable Reference

All deployment phases read from a single configuration file: `config/variables.yml`.

!!! tip
    Copy the example and fill in your values:
    ```bash
    cp config/variables.example.yml config/variables.yml
    ```
    **Never commit** `variables.yml` — it is excluded by `.gitignore`.

---

## Azure Subscription

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `subscription_id` | string | Azure subscription ID | — | Infrastructure |
| `resource_group` | string | Target Azure resource group | `rg-azurelocal-prod` | Infrastructure |
| `location` | string | Azure region | `eastus` | Infrastructure |

## Azure Local Cluster

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `cluster_name` | string | Failover cluster network name | `AZLHCI-CLUSTER` | Deploy, Configure |
| `cluster_resource_group` | string | Resource group of the Arc-registered cluster | `rg-azurelocal-prod` | Infrastructure |

## SOFS Configuration

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `sofs_name` | string | SOFS cluster role name | `SOFS01` | Deploy, Configure, Tests |
| `share_name` | string | SMB share name | `FSLogixProfiles` | Deploy, Configure, Tests |
| `share_path` | string | Path on the CSV | `C:\ClusterStorage\Volume1\FSLogixProfiles` | Deploy, Configure |

## Active Directory

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `domain_fqdn` | string | AD domain FQDN | `contoso.local` | Deploy, Configure |
| `ou_path` | string | OU for the SOFS computer object | `OU=Servers,DC=contoso,DC=local` | Deploy |

## FSLogix / AVD

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `avd_users_group` | string | AD group for FSLogix profile access | `AVD-Users` | Configure, Tests |

## Diagnostics

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `diag_storage_account` | string | Diagnostic storage account (globally unique) | `stazlhcidiag001` | Infrastructure |

## Tags

| Variable | Type | Description | Default | Phases |
|----------|------|-------------|---------|--------|
| `tags.environment` | string | Environment tag | `production` | Infrastructure |
| `tags.owner` | string | Owner tag | `platform-team` | Infrastructure |

## Ansible Connection

These are only used by `src/ansible/` playbooks.

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `ansible.winrm_transport` | string | WinRM transport | `kerberos` |
| `ansible.cert_validation` | string | Certificate validation | `ignore` |
| `ansible.sofs_nodes` | list | SOFS cluster node hostnames and IPs | — |
| `ansible.avd_session_hosts` | list | AVD session host hostnames and IPs | — |

---

## Phase Consumption Matrix

| Variable Group | :material-cloud-outline: Infrastructure | :material-server: Deploy | :material-cog: Configure | :material-check-circle: Tests |
|---------------|:---:|:---:|:---:|:---:|
| Azure Subscription | :material-check: | | | |
| Azure Local Cluster | | :material-check: | :material-check: | |
| SOFS Configuration | | :material-check: | :material-check: | :material-check: |
| Active Directory | | :material-check: | :material-check: | |
| FSLogix / AVD | | | :material-check: | :material-check: |
| Diagnostics | :material-check: | | | |
| Tags | :material-check: | | | |
| Ansible Connection | | | :material-check: | |
