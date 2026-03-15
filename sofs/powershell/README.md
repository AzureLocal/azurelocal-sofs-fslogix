# SOFS PowerShell Scripts

Standalone PowerShell scripts for deploying and configuring SOFS on Azure Local. These are the Phase 1 (Azure resources) and Phase 2 (guest OS config) scripts for the `powershell` guest config engine.

> These scripts can be run directly — they do not require the `Deploy-SOFS.ps1` orchestrator. Run from the **repo root** so logs write to `./logs/sofs/`.

---

## Scripts

| Script | Phase | What it does |
|---|---|---|
| `Deploy-SOFS-Azure.ps1` | Phase 1 | Creates resource group, cloud witness storage account, NICs, Arc VMs, and data disks via Azure CLI |
| `Configure-SOFS-Cluster.ps1` | Phase 2 | Configures Failover Clustering, S2D pool, SOFS role, and FSLogix SMB share via PSRemoting |

---

## Deployed Resource Inventory

> All examples use the fictional company **Infinite Improbability Corp (IIC)** — prefix `iic`, domain `improbability.cloud`, NetBIOS `IMPROBABLE`.

### Azure Resources (`Deploy-SOFS-Azure.ps1`)

| Resource | Field | Config Variable (`solution-sofs.yml`) | IIC Example |
|---|---|---|---|
| Subscription | Subscription ID | `compute_wsfc.wsfc_sofs_subscription_id` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| Azure Region | Location | `compute_wsfc.wsfc_sofs_location` | `eastus` |
| Resource Group | Name | `compute_wsfc.wsfc_sofs_resource_group` | `rg-sofs-iic-eus-01` |
| Cloud Witness | Storage Account Name | `compute_wsfc.wsfc_sofs_cloud_witness_name` | `stsofswitnessiic01` |
| Azure Local Cluster | Name | `compute_wsfc.wsfc_sofs_azl_cluster_name` | `iic-clus01` |
| Custom Location | ARM ID | `compute_wsfc.wsfc_sofs_custom_location_id` | `.../customLocations/iic-clus01-ral-cl` |
| Logical Network | ARM ID | `compute_wsfc.wsfc_sofs_logical_network_id` | `.../logicalNetworks/lnet-iic-tenant1-100` |
| OS Image | Gallery Image ARM ID | `compute_wsfc.wsfc_sofs_gallery_image_name` | `.../img-iic-ws2025-core-azedition-g2-v1` |
| VM Count | Number of VMs | `compute_wsfc.wsfc_sofs_vm_count` | `3` |
| VM Name Prefix | Prefix | `compute_wsfc.wsfc_sofs_vm_prefix` | `SOFS` → `SOFS01`, `SOFS02`, `SOFS03` |
| VM Spec | vCPUs per VM | `compute_wsfc.wsfc_sofs_vm_processors` | `4` |
| VM Spec | Memory per VM (MB) | `compute_wsfc.wsfc_sofs_vm_memory_mb` | `8192` |
| Data Disks | Count per VM | `compute_wsfc.wsfc_sofs_data_disk_count` | `4` |
| Data Disks | Size per disk (GB) | `compute_wsfc.wsfc_sofs_data_disk_size_gb` | `500` |

### VM Static IPs

| VM | Config Variable | IIC Example |
|---|---|---|
| `SOFS01` | `compute_wsfc.wsfc_sofs_vm_ips.01` | `192.168.100.201` |
| `SOFS02` | `compute_wsfc.wsfc_sofs_vm_ips.02` | `192.168.100.202` |
| `SOFS03` | `compute_wsfc.wsfc_sofs_vm_ips.03` | `192.168.100.203` |

### VM Storage Paths

| VM | Config Variable | IIC Example |
|---|---|---|
| `SOFS01` | `compute_wsfc.wsfc_sofs_storage_path_ids.01` | `sp-iic-clus01-m3-vmstore-prd-01` |
| `SOFS02` | `compute_wsfc.wsfc_sofs_storage_path_ids.02` | `sp-iic-clus01-m3-vmstore-prd-02` |
| `SOFS03` | `compute_wsfc.wsfc_sofs_storage_path_ids.03` | `sp-iic-clus01-m3-vmstore-prd-03` |

### Guest Failover Cluster (`Configure-SOFS-Cluster.ps1`)

| Resource | Field | Config Variable (`solution-sofs.yml`) | IIC Example |
|---|---|---|---|
| Failover Cluster | Name | `compute_wsfc.wsfc_cluster_name` | `SOFS-Cluster` |
| Failover Cluster | Static IP | `compute_wsfc.wsfc_cluster_ip` | `192.168.100.204` |
| SOFS Access Point | Role Name | `compute_wsfc.wsfc_sofs_name` | `FSLogixSOFS` |
| SOFS Access Point | Static IP | `compute_wsfc.wsfc_sofs_ip` | `192.168.100.205` |
| Anti-Affinity Rule | Rule Name | `compute_wsfc.wsfc_sofs_anti_affinity_rule_name` | `SOFS-AntiAffinity` |

### Storage Spaces Direct & SMB Share

| Resource | Field | Config Variable (`solution-sofs.yml`) | IIC Example |
|---|---|---|---|
| S2D Volume | Name | `compute_wsfc.wsfc_sofs_s2d_volume_name` | `FSLogixData` |
| S2D Volume | Size (GB) | `compute_wsfc.wsfc_sofs_s2d_volume_size_gb` | `2560` |
| S2D Volume | Mirror Copies | `compute_wsfc.wsfc_sofs_s2d_data_copies` | `2` |
| SMB Share | Share Name | `compute_wsfc.wsfc_sofs_share_name` | `FSLogix` |

### Domain & Identity

| Resource | Field | Config Variable (`solution-sofs.yml`) | IIC Example |
|---|---|---|---|
| Active Directory | Domain FQDN | `compute_wsfc.wsfc_sofs_domain_fqdn` | `ad.improbability.cloud` |
| Active Directory | NetBIOS Name | `compute_wsfc.wsfc_sofs_domain_netbios` | `IMPROBABLE` |
| Domain Join | Service Account | `compute_wsfc.wsfc_sofs_domain_join_username` | `svc.azl.local` |
| DNS | Primary Server | `compute_wsfc.wsfc_sofs_dns_servers[0]` | `192.168.100.11` |
| DNS | Secondary Server | `compute_wsfc.wsfc_sofs_dns_servers[1]` | `192.168.100.12` |
| Nodes OU | Distinguished Name | `compute_wsfc.wsfc_sofs_nodes_ou_path` | `OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=ad,DC=improbability,DC=cloud` |

### Credentials (Key Vault)

| Secret | Purpose | Config Variable (`solution-sofs.yml`) | IIC Example URI |
|---|---|---|---|
| VM Admin Username | Local admin username for SOFS VMs | `compute_wsfc.wsfc_sofs_vm_admin_username` | `keyvault://kv-iic-platform/sofs-vm-admin-username` |
| VM Admin Password | Local admin password for SOFS VMs | `compute_wsfc.wsfc_sofs_vm_admin_password` | `keyvault://kv-iic-platform/sofs-vm-admin-password` |
| Domain Join Password | Password for domain join account | `compute_wsfc.wsfc_sofs_domain_join_password` | `keyvault://kv-iic-platform/domain-join-password` |

---

## Usage

### Prerequisites

- PowerShell 7.0+
- Azure CLI (`az`) authenticated to the target subscription
- `powershell-yaml` module: `Install-Module powershell-yaml`
- Generated `solution-sofs.yml` — run from repo root: `.\tools\Generate-SolutionConfig.ps1 -Solution sofs-azure-local -Environment <env>`

### Active Directory Prerequisites

> **These must be completed by an AD admin before running Phase 1.** Domain join will fail at boot if the OUs don't exist or the service account lacks the required permissions.

#### 1. Create the OUs

Both OUs defined in the config must exist before deployment. The script uses them to place the cluster computer objects and node machine accounts during domain join.

| OU | Config Variable | IIC Example |
|---|---|---|
| Cluster objects OU | `compute_wsfc.wsfc_sofs_cluster_ou_path` | `OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=ad,DC=improbability,DC=cloud` |
| Node computer accounts OU | `compute_wsfc.wsfc_sofs_nodes_ou_path` | `OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=ad,DC=improbability,DC=cloud` |

These are often the same OU. Verify the values in `solution-sofs.yml` match what has been created in AD before proceeding.

#### 2. Grant permissions to the domain join account

The account defined in `compute_wsfc.wsfc_sofs_domain_join_username` (e.g., `svc.azl.local`) must have **delegated permissions on both OUs** listed above:

| Permission | Required for |
|---|---|
| **Create Computer objects** | Joining the SOFS VMs to the domain (node machine accounts) |
| **Delete Computer objects** | Re-joining or re-deploying nodes |
| **Write all properties** on Computer objects | Setting attributes during domain join |
| **Create Computer objects** in the cluster OU | `New-Cluster` creates the cluster name object (CNO) |
| **Full Control** on the CNO after cluster creation | The CNO must be able to create virtual computer objects (VCOs) for the SOFS role |

> **Cluster Name Object (CNO) note:** After `New-Cluster` runs, the CNO (`SOFS-Cluster$`) must have **Create Computer objects** permission on the cluster OU so it can create the SOFS access point VCO (`FSLogixSOFS$`) automatically. If this is not pre-delegated, grant it manually after cluster creation and before adding the SOFS role.

To delegate in PowerShell (run as Domain Admin):

```powershell
# Replace with your actual OU DN and domain join account
$ouDN      = "OU=SOFS-Cluster,OU=Clusters,OU=Servers,DC=ad,DC=improbability,DC=cloud"
$joinAcct  = "IMPROBABLE\svc.azl.local"

# Delegate 'Create/Delete Computer objects' to the join account on the OU
$acl = Get-Acl "AD:$ouDN"
$identity  = [System.Security.Principal.NTAccount]$joinAcct
$adRights  = [System.DirectoryServices.ActiveDirectoryRights]"CreateChild,DeleteChild"
$type      = [System.Security.AccessControl.AccessControlType]"Allow"
$schemaGuid = [guid]"bf967a86-0de6-11d0-a285-00aa003049e2"   # Computer object GUID
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($identity, $adRights, $type, $schemaGuid)
$acl.AddAccessRule($ace)
Set-Acl "AD:$ouDN" $acl
```

### Phase 1 — Deploy Azure Resources

```powershell
# Dry run
.\solutions\sofs\powershell\Deploy-SOFS-Azure.ps1 -WhatIf

# Full deploy using solution config defaults
.\solutions\sofs\powershell\Deploy-SOFS-Azure.ps1

# Override specific values
.\solutions\sofs\powershell\Deploy-SOFS-Azure.ps1 -ResourceGroup "rg-sofs-iic-eus-01" -VMCount 3
```

### Phase 2 — Configure Guest Cluster

Run this after Phase 1 completes **and** the VMs are domain-joined.

```powershell
# Dry run
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1 -WhatIf

# Full configure using solution config defaults (Kerberos auth via domain)
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1

# With explicit credential (pre-domain-join / basic auth)
.\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1 -Credential (Get-Credential) -SetTrustedHosts
```

---

## Parameters

### `Deploy-SOFS-Azure.ps1`

| Parameter | Type | Description |
|---|---|---|
| `-SolutionConfigPath` | `string` | Path to `solution-sofs.yml` (default: `solutions/sofs/solution-sofs.yml`) |
| `-Credential` | `PSCredential` | VM admin credential — overrides Key Vault resolution |
| `-SubscriptionId` | `string` | Azure subscription ID — overrides config |
| `-ResourceGroup` | `string` | Target resource group name — overrides config |
| `-Location` | `string` | Azure region — overrides config |
| `-CustomLocationId` | `string` | Custom location ARM ID — overrides config |
| `-LogicalNetworkId` | `string` | Logical network ARM ID — overrides config |
| `-ImageName` | `string` | Gallery image name — overrides config |
| `-StoragePathId` | `string` | Default storage path ARM ID — overrides config |
| `-StoragePathIds` | `hashtable` | Per-VM storage path map `@{ "01"="..."; "02"="..." }` — overrides config |
| `-VMPrefix` | `string` | VM naming prefix — overrides config |
| `-VMCount` | `int` | Number of VMs — overrides config |
| `-VMProcessors` | `int` | vCPUs per VM — overrides config |
| `-VMMemoryMB` | `int` | Memory per VM in MB — overrides config |
| `-DataDiskCount` | `int` | Data disks per VM — overrides config |
| `-DataDiskSizeGB` | `int` | Size per data disk in GB — overrides config |
| `-WitnessStorageAccount` | `string` | Cloud witness storage account name — overrides config |
| `-VMIPs` | `hashtable` | Per-VM static IPs `@{ "01"="..."; "02"="..." }` — overrides config |
| `-WhatIf` | `switch` | Dry-run mode — shows what would be deployed |
| `-LogPath` | `string` | Override log file path |

### `Configure-SOFS-Cluster.ps1`

| Parameter | Type | Description |
|---|---|---|
| `-SolutionConfigPath` | `string` | Path to `solution-sofs.yml` (default: `solutions/sofs/solution-sofs.yml`) |
| `-Credential` | `PSCredential` | WinRM credential — overrides Key Vault resolution |
| `-TargetNode` | `string[]` | Limit to specific node names (default: all SOFS nodes) |
| `-SetTrustedHosts` | `switch` | Add SOFS VM IPs to WinRM TrustedHosts before connecting |
| `-RemoveTrustedHosts` | `switch` | Remove SOFS entries from TrustedHosts after script completes |
| `-WinRMTransport` | `string` | `kerberos` (default) or `basic` |
| `-GuestClusterName` | `string` | Failover cluster name — overrides config |
| `-GuestClusterIP` | `string` | Failover cluster IP — overrides config |
| `-SOFSAccessPoint` | `string` | SOFS role name — overrides config |
| `-FSLogixShareName` | `string` | SMB share name — overrides config |
| `-WitnessStorageAccount` | `string` | Cloud witness storage account name — overrides config |
| `-S2DVolumeName` | `string` | S2D volume name — overrides config |
| `-S2DVolumeSizeGB` | `int` | S2D volume size in GB — overrides config |
| `-S2DNumberOfDataCopies` | `int` | Mirror copies (2 or 3) — overrides config |
| `-DomainFQDN` | `string` | Domain FQDN for WinRM targets — overrides config |
| `-DomainNetBIOS` | `string` | Domain NetBIOS for permissions — overrides config |
| `-AntiAffinityRuleName` | `string` | Anti-affinity rule name — overrides config |
| `-AzureLocalClusterName` | `string` | Azure Local physical cluster name — overrides config |
| `-VMPrefix` | `string` | VM naming prefix — overrides config |
| `-VMCount` | `int` | Number of SOFS VMs — overrides config |
| `-WhatIf` | `switch` | Dry-run mode — shows what would be configured |
| `-LogPath` | `string` | Override log file path |

---

## Logs

Both scripts write logs to `./logs/sofs/` relative to the repo root:

```
logs/sofs/<YYYY-MM-DD_HHmmss>_Deploy-SOFS-Azure.log
logs/sofs/<YYYY-MM-DD_HHmmss>_Configure-SOFS-Cluster.log
```

---

*Maintained by the ProdTech team — Hybrid Cloud Solutions.*
