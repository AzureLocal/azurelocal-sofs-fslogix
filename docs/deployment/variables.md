# Variables

## Overview

All deployment tools in this repository are driven by a single central configuration file: `config/variables.yml`. This file is the **single source of truth** — your architecture decisions, sizing calculations, identity settings, and infrastructure IDs are all declared here and consumed by every automation tool.

---

## Getting Started

1. Copy the example file:
    ```powershell
    cp config/variables.example.yml config/variables.yml
    ```

2. Edit `config/variables.yml` with your values

3. **Never commit `config/variables.yml`** — it is excluded by `.gitignore` because it contains environment-specific values and Key Vault references

---

## Configuration Sections

### Azure

```yaml
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
  resource_group: "rg-sofs-azl-eus-01"
  location: "eastus"
```

| Variable | Description |
|----------|-------------|
| `subscription_id` | Azure subscription for all SOFS resources |
| `resource_group` | Resource group name — created by the deployment tool if it doesn't exist |
| `location` | Azure region matching your Azure Local cluster registration |

### Key Vault

```yaml
keyvault:
  name: "kv-platform-prod"
```

The Key Vault used for secret resolution. All secrets in this file use `keyvault://` URIs — the deployment tools resolve them at runtime.

### Azure Local

```yaml
azure_local:
  cluster_name: "azl-cluster-01"
  custom_location_id: "<resource ID>"
  logical_network_id: "<resource ID>"
  gallery_image_name: "<resource ID>"
  storage_path_id: "<resource ID>"          # Single-volume deployments
  storage_path_ids:                          # Three-volume deployments
    "01": "<resource ID>"
    "02": "<resource ID>"
    "03": "<resource ID>"
```

| Variable | Description |
|----------|-------------|
| `cluster_name` | Azure Local cluster name |
| `custom_location_id` | Custom location resource ID for Arc VM placement |
| `logical_network_id` | Compute logical network resource ID for NIC creation |
| `gallery_image_name` | Gallery image resource ID (Windows Server 2025 DC Azure Edition Core Gen2) |
| `storage_path_id` | Storage path for single-volume deployments (all VMs on one volume) |
| `storage_path_ids` | Per-VM storage paths for three-volume deployments (fault isolation) |

!!! tip "storage_path_id vs. storage_path_ids"
    Use `storage_path_id` (singular) when all VMs share one host volume. Use `storage_path_ids` (plural, keyed by node number) when each VM has its own host volume for fault isolation. The deployment tools check which one is populated and behave accordingly.

### Virtual Machines

```yaml
vm:
  prefix: "sofs"
  count: 3
  processors: 4
  memory_mb: 8192
  admin_username: "sofs_admin"
  admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
  ips:
    "01": "192.168.1.201"
    "02": "192.168.1.202"
    "03": "192.168.1.203"
```

| Variable | Description |
|----------|-------------|
| `prefix` | VM name prefix — VMs are named `<prefix>-01`, `<prefix>-02`, `<prefix>-03` |
| `count` | Number of SOFS VMs (always 3 for a production cluster) |
| `processors` | vCPUs per VM (4 is standard; increase for high-density deployments) |
| `memory_mb` | RAM per VM in MB (8192 = 8 GB; increase for large S2D pools) |
| `admin_username` | Local admin username for the VMs |
| `admin_password` | Key Vault URI — resolved at runtime, never stored in plaintext |
| `ips` | Static IP assignments per VM (keyed by node number) |

### Data Disks

```yaml
data_disks:
  count: 4
  size_gb: 500
```

| Variable | Description |
|----------|-------------|
| `count` | Data disks per VM (4 is standard — feeds the S2D pool) |
| `size_gb` | Size of each data disk in GB — calculated from [Capacity Planning](../architecture/capacity-planning.md) |

!!! important "Size drives everything"
    `data_disks.size_gb` multiplied by `data_disks.count` × `vm.count` equals your total S2D pool. Make sure this aligns with your capacity planning calculations. For the 5.5 TB usable example with two-way mirror: 4 × 1024 GB × 3 VMs = 12,288 GB total pool.

### Domain

```yaml
domain:
  fqdn: "iic.local"
  netbios: "IIC"
  join_username: "svc.domainjoin"
  join_password: "keyvault://kv-platform-prod/domain-join-password"
  cluster_ou_path: "OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=iic,DC=local"
  nodes_ou_path: "OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=iic,DC=local"
```

| Variable | Description |
|----------|-------------|
| `fqdn` | Active Directory domain FQDN |
| `netbios` | NetBIOS domain name (used in share permissions: `NETBIOS\Domain Users`) |
| `join_username` | Service account for domain join operations |
| `join_password` | Key Vault URI for the domain join password |
| `cluster_ou_path` | AD OU for the cluster CNO Computer Object |
| `nodes_ou_path` | AD OU for the SOFS VM Computer Objects |

### DNS Servers

```yaml
dns_servers:
  - "10.0.1.10"
  - "10.0.1.11"
```

DNS servers for the SOFS VMs — typically your AD domain controllers.

### SOFS Configuration

```yaml
sofs:
  name: "FSLogixSOFS"
  cluster_name: "sofs-cluster"
  cluster_ip: "192.168.1.204"
  share_name: "FSLogix"
  role_enabled: true
  anti_affinity_rule_name: "SOFS-AntiAffinity"
```

| Variable | Description |
|----------|-------------|
| `name` | SOFS client access point name (the `\\name\share` prefix users connect to) |
| `cluster_name` | Windows Failover Cluster name (the CNO in AD) |
| `cluster_ip` | Static IP for the failover cluster |
| `share_name` | SMB share name (Option A: single share; Option B: configure per-share in the tool) |
| `role_enabled` | Whether the SOFS Scale-Out File Server role is enabled |
| `anti_affinity_rule_name` | Name of the anti-affinity rule in the host cluster |

### Storage Spaces Direct (S2D)

```yaml
s2d:
  volume_name: "FSLogixData"
  volume_size_gb: 2560
  data_copies: 2
```

| Variable | Description |
|----------|-------------|
| `volume_name` | Guest S2D volume name (Option A: single name; Option B: configure per-volume) |
| `volume_size_gb` | Guest S2D volume size — your usable FSLogix space target |
| `data_copies` | `NumberOfDataCopies` — **2** for two-way mirror, **3** for three-way |

!!! danger "data_copies defaults matter"
    S2D defaults to three-way mirror on a 3-node cluster. You must explicitly set `data_copies: 2` for a two-way mirror. Getting this wrong silently consumes 50% more raw capacity.

### Cloud Witness

```yaml
cloud_witness:
  name: "stsofswitnessprod01"
  key_uri: ""
  key_secret: ""
```

| Variable | Description |
|----------|-------------|
| `name` | Azure Storage Account name for the cloud witness |
| `key_uri` | Key Vault URI for the storage key (if using KV) |
| `key_secret` | Direct key value (used when KV is not available — less secure) |

### Guest Configuration Engine

```yaml
guest_config_engine: "ansible_create"
```

Controls how guest OS configuration (Phases 3–11) is executed:

| Value | Behavior |
|-------|----------|
| `ansible_create` | Deploy an Ansible controller VM and run playbooks automatically |
| `ansible_existing` | Use an existing Ansible controller (specify in `ansible_controller`) |
| `manual` | Skip guest configuration — the operator runs PowerShell scripts manually |

### Tags

```yaml
tags:
  project: "SOFS"
  environment: "production"
  workload: "FSLogix"
  solution: "sofs-azure-local"
```

Applied to all Azure resources created by the deployment tools.

---

## How Design Decisions Map to Variables

| Architecture Decision | Variables Affected |
|----------------------|-------------------|
| Three host volumes (fault isolation) | `azure_local.storage_path_ids` (populate all three) |
| Single host volume | `azure_local.storage_path_id` (populate one) |
| Two-way guest mirror | `s2d.data_copies: 2` |
| Three-way guest mirror | `s2d.data_copies: 3`, increase `data_disks.size_gb` |
| Option A (single share) | `sofs.share_name`, `s2d.volume_name`, `s2d.volume_size_gb` |
| Option B (three shares) | Configure per-share in tool-specific parameters |
| Profile sizing | `data_disks.size_gb` (derived from capacity planning) |

---

## Tool-Specific Parameter Mapping

Each automation tool reads from `config/variables.yml` and maps values to its own parameter format:

| Tool | Parameter File | Mapping |
|------|---------------|---------|
| **Terraform** | `src/terraform/terraform.tfvars` | Copy `terraform.tfvars.example`, values map 1:1 to `variables.tf` |
| **Bicep** | `src/bicep/main.bicepparam` | Copy `main.bicepparam.example`, parameter names match Bicep template |
| **ARM** | `src/arm/azuredeploy.parameters.json` | Copy `azuredeploy.parameters.example.json` |
| **PowerShell** | Reads `config/variables.yml` directly | Accepts `-ConfigPath` parameter |
| **Ansible** | `src/ansible/inventory.yml` | Host inventory + all SOFS variables in group_vars |

!!! tip "Central config, tool-specific params"
    For Terraform, Bicep, and ARM, you maintain both `config/variables.yml` (your design decisions) and the tool-specific parameter file. The PowerShell and Ansible tools read the central config directly.

---

## Key Vault Secret Resolution

Secrets are never stored in plaintext. The `keyvault://` URI format tells deployment tools to resolve the value at runtime:

```yaml
admin_password: "keyvault://kv-platform-prod/sofs-vm-admin-password"
```

**Resolution flow:**

1. Tool parses the URI → vault name: `kv-platform-prod`, secret name: `sofs-vm-admin-password`
2. Tool calls `az keyvault secret show --vault-name kv-platform-prod --name sofs-vm-admin-password`
3. Secret value is passed directly to the deployment — never written to disk

**Required secrets:**

| Secret Name | Used By |
|------------|---------|
| `sofs-vm-admin-password` | Local admin password for SOFS VMs |
| `domain-join-password` | Service account password for domain join |

---

## Next Steps

- Choose your deployment tool: [Terraform](terraform.md) | [Bicep](bicep.md) | [ARM](arm.md) | [PowerShell](powershell.md) | [Ansible](ansible.md)
- [Variable Reference](../reference/variables.md) — Complete variable reference with types and defaults
