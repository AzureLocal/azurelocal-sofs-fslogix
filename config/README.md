# Configuration

Central variables file — the **single source of truth** for all deployment phases.

Every variable the SOFS scripts read lives here. Secrets use `keyvault://` URIs and are
resolved at runtime — **never put actual passwords in this file**.

---

## Usage

```bash
cp variables.example.yml variables.yml
# Edit variables.yml with your environment values
```

> **Do not** commit `variables.yml` — it is excluded by `.gitignore`.

---

## Variable Reference

### azure

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `azure.subscription_id` | string | ✅ | Azure subscription ID | Deploy |
| `azure.resource_group` | string | ✅ | Target resource group for SOFS resources | Deploy |
| `azure.location` | string | ✅ | Azure region | Deploy |

### keyvault

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `keyvault.name` | string | ✅ | Key Vault name for secret resolution | Deploy, Configure |

### azure_local

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `azure_local.cluster_name` | string | ✅ | Azure Local physical cluster name | Configure |
| `azure_local.custom_location_id` | string | ✅ | ARM ID of Azure Local custom location | Deploy |
| `azure_local.logical_network_id` | string | ✅ | ARM ID of logical network for NIC placement | Deploy |
| `azure_local.gallery_image_name` | string | ✅ | Gallery image ARM ID on Azure Local | Deploy |
| `azure_local.storage_path_id` | string | | Default storage path ARM ID (fallback) | Deploy |
| `azure_local.storage_path_ids` | map | ✅ | Per-VM storage path map (`"01"`, `"02"`, ...) | Deploy |

### vm

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `vm.prefix` | string | ✅ | VM naming prefix (e.g. `sofs`) | Deploy, Configure |
| `vm.count` | int | ✅ | Number of SOFS VMs to deploy | Deploy, Configure |
| `vm.processors` | int | ✅ | vCPU count per VM | Deploy |
| `vm.memory_mb` | int | ✅ | Memory in MB per VM | Deploy |
| `vm.admin_username` | string | ✅ | VM local admin username | Deploy |
| `vm.admin_password` | string | ✅ | `keyvault://` URI for VM admin password | Deploy |
| `vm.ips` | map | ✅ | Per-VM static IPs (`"01"`, `"02"`, ...) | Deploy, Configure |

### data_disks

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `data_disks.count` | int | ✅ | Data disks per VM (for S2D pool) | Deploy |
| `data_disks.size_gb` | int | ✅ | Size per data disk in GB | Deploy |

### domain

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `domain.fqdn` | string | ✅ | Active Directory domain FQDN | Deploy, Configure |
| `domain.netbios` | string | ✅ | Domain NetBIOS name | Configure |
| `domain.join_username` | string | ✅ | Domain join service account | Deploy, Configure |
| `domain.join_password` | string | ✅ | `keyvault://` URI for domain join password | Deploy, Configure |
| `domain.cluster_ou_path` | string | ✅ | OU path for cluster computer objects | Configure |
| `domain.nodes_ou_path` | string | ✅ | OU path for SOFS node computer objects | Deploy |

### dns_servers

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `dns_servers` | list | ✅ | DNS server IPs | Deploy |

### sofs

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `sofs.name` | string | ✅ | SOFS cluster role / client access point name | Configure |
| `sofs.cluster_name` | string | ✅ | Guest failover cluster name | Configure |
| `sofs.cluster_ip` | string | ✅ | Guest failover cluster static IP | Configure |
| `sofs.share_name` | string | ✅ | FSLogix SMB share name | Configure |
| `sofs.role_enabled` | bool | | Enable SOFS role creation | Configure |
| `sofs.anti_affinity_rule_name` | string | | Anti-affinity rule name on Azure Local | Configure |

### s2d

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `s2d.volume_name` | string | ✅ | S2D volume friendly name | Configure |
| `s2d.volume_size_gb` | int | ✅ | S2D volume size in GB | Configure |
| `s2d.data_copies` | int | ✅ | Mirror data copies (2 or 3) | Configure |

### cloud_witness

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `cloud_witness.name` | string | ✅ | Cloud witness storage account name | Deploy, Configure |
| `cloud_witness.key_uri` | string | | `keyvault://` URI for witness key (optional — auto-retrieved if blank) | Configure |
| `cloud_witness.key_secret` | string | | Direct witness key secret name in Key Vault | Configure |

### guest_config_engine

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `guest_config_engine` | string | ✅ | How to configure guests: `ansible_create`, `ansible_existing`, `manual` | Orchestration |

### ansible_controller

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `ansible_controller.name` | string | | Controller VM name | Terraform |
| `ansible_controller.size` | string | | Azure VM size | Terraform |
| `ansible_controller.admin_username` | string | | Admin user for controller VM | Terraform |
| `ansible_controller.hub_subnet_id` | string | | Hub VNet subnet ARM ID | Terraform |
| `ansible_controller.hub_rg` | string | | Hub resource group | Terraform |
| `ansible_controller.existing_controller_ip` | string | | IP of existing controller (when using `ansible_existing`) | Terraform |
| `ansible_controller.existing_controller_user` | string | | SSH user for existing controller | Terraform |

### tags

| Variable | Type | Required | Description | Used By |
|----------|------|:--------:|-------------|---------|
| `tags.*` | map | | Resource tags applied to all Azure resources | Deploy |

---

## Which Phases Use Which Variables?

| Variable Section | Deploy (Phase 1) | Configure (Phase 2) | IaC / Terraform | Orchestration |
|-----------------|:---:|:---:|:---:|:---:|
| azure | ✅ | | ✅ | |
| keyvault | ✅ | ✅ | | |
| azure_local | ✅ | ✅ | ✅ | |
| vm | ✅ | ✅ | ✅ | |
| data_disks | ✅ | | ✅ | |
| domain | ✅ | ✅ | | |
| dns_servers | ✅ | | | |
| sofs | | ✅ | | |
| s2d | | ✅ | | |
| cloud_witness | ✅ | ✅ | ✅ | |
| guest_config_engine | | | ✅ | ✅ |
| ansible_controller | | | ✅ | |
| tags | ✅ | | ✅ | |

---

## Key Vault URI Format

Secrets are referenced using `keyvault://` URIs:

```
keyvault://<vault-name>/<secret-name>
```

At runtime, scripts resolve these via `Az.KeyVault` module (preferred) or `az keyvault secret show` (fallback).

**Example:**
```yaml
vm:
  admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
```
