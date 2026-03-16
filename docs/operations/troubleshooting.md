# Troubleshooting

## Overview

This page covers common issues encountered during SOFS deployment and operation, organized by deployment phase. For each issue, the **symptom**, **likely cause**, and **resolution** are provided.

---

## Azure Resource Provisioning (Phase 1)

### VM Creation Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `ResourceNotFound` for custom location | Custom location ID is incorrect or the Azure Local cluster is not registered | Verify `custom_location_id` in `variables.yml` matches the output of `az customlocation show` |
| `StoragePathNotFound` | Storage path ID doesn't exist or is in a different resource group | Verify `storage_path_id` / `storage_path_ids` in `variables.yml` |
| NIC creation fails with IP conflict | Static IP already in use on the network | Verify IP addresses in `variables.yml` are available — use `Test-Connection` or check DHCP leases |
| Gallery image not found | Image name or resource group is wrong | Run `az azurestackhci galleryimage list` to verify available images |

### Data Disk Attachment Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Disk size exceeds available capacity | Azure Local volume doesn't have enough free space | Check volume capacity: `Get-Volume` on the Azure Local host. Reduce `data_disk_size_gb` or expand the host volume |
| Dynamic provisioning not reducing usage | Disks are dynamically provisioned but the host volume must reserve the full allocation | This is expected — the host volume size must accommodate the maximum allocation even though actual usage grows dynamically |

---

## Anti-Affinity (Phases 3–4)

### VMs on Same Physical Node

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Two or more SOFS VMs on the same Azure Local node | Anti-affinity rule not created or not enforced | Create/verify the rule: `New-ClusterAffinityRule -Name "SOFS-AntiAffinity" -RuleType AntiAffinity -Groups "sofs-01","sofs-02","sofs-03" -Cluster "azl-cluster"` |
| Rule exists but VMs not separated | Rule was created after VMs were placed | Live migrate VMs manually: `Move-ClusterVirtualMachineRole` |
| `Get-ClusterAffinityRule` not found | Azure Local OS version doesn't include this cmdlet | Use legacy `Set-VMAntiAffinityClassNames` on each VM instead |

---

## Failover Clustering (Phase 5)

### Cluster Creation Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| DNS registration fails | Cluster CNO can't register DNS A record | Pre-create the DNS A record for the cluster name, or grant the computer account dynamic DNS update permissions |
| Access denied creating cluster | Service account lacks permissions to create AD computer objects | Pre-stage the CNO in the target OU and grant the service account Full Control over it |
| Cluster validation warnings about network | Only one network detected | Expected in single-NIC deployments — proceed if the single network is sufficient for your environment |

---

## Cloud Witness (Phase 6)

### Quorum Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Cloud witness unreachable | Storage account firewall blocking access, or incorrect key | Verify the storage account allows access from the SOFS VMs' IP range. Regenerate and re-apply the access key |
| Quorum lost with one node down | Cloud witness not configured, falling back to node majority only | Run `Set-ClusterQuorum -CloudWitness -AccountName "<name>" -AccessKey "<key>"` |
| `Set-ClusterQuorum` fails | Storage account name or key is wrong | Verify with `az storage account keys list` |

---

## Storage Spaces Direct (Phase 7)

### S2D Enable Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Enable-ClusterS2D` fails with "no eligible disks" | Data disks not visible inside VMs | Verify disks are attached: `Get-Disk` on each VM. Check that disks are Online and not initialized |
| S2D requires at minimum 3 physical disks | Fewer than 3 data disks total across the cluster | Ensure each VM has at least 1 data disk (3 VMs × 1 disk minimum). Default is 4 per VM |
| Pool creation fails | Virtual disk bus type not supported | Ensure disks are SCSI (not IDE) — Azure Local Arc VMs use SCSI by default |

### S2D Tuning

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Performance degradation in nested environment | Default S2D tuning not optimized for guest VMs | Apply guest tuning: `Set-StoragePool -AutoRebalanceFrequency 1440`, `Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters" -Name HwTimeout -Value 0x00002710 -Force` |

### Volume Creation Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Not enough capacity for requested volume size | Volume size (× data copies) exceeds pool capacity | Reduce volume size or add more data disks. Two-way mirror: usable = pool_size / 2. Three-way: usable = pool_size / 3 |
| Wrong number of data copies | Didn't specify `-NumberOfDataCopies 2` on a 3-node cluster | Default is three-way mirror on 3+ nodes. Explicitly set `-NumberOfDataCopies 2` for two-way mirror |

---

## SOFS Role (Phase 8)

### SOFS Access Point Creation Fails

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Add-ClusterScaleOutFileServerRole` fails with AD error | Cluster CNO lacks permission to create computer objects | Pre-stage the SOFS access point computer object in AD and grant the cluster CNO Full Control |
| DNS A record not created | Dynamic DNS updates restricted | Manually create the A record for the SOFS access point name |
| Share creation fails — scope name not found | SOFS role not yet online | Verify: `Get-ClusterGroup \| Where-Object { $_.GroupType -eq "ScaleOutFileServer" }` — ensure it shows Online |

---

## SMB Shares and Permissions (Phase 9)

### Share Access Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Test-Path \\SOFSName\Share` returns `$false` | Share not created, DNS not resolving, or firewall blocking SMB | Check share exists (`Get-SmbShare`), verify DNS resolution (`Resolve-DnsName`), verify SMB port 445 is open |
| Users can see other users' folders | Access-Based Enumeration not enabled | Recreate share with `-FolderEnumerationMode AccessBased` |
| FSLogix "access denied" at first logon | NTFS permissions incorrect — Domain Users missing Modify on share root | Re-run `Set-FSLogixNTFS` — see [Permissions](../configuration/permissions.md) |
| Profile loads read-only | SMB ChangeAccess not granted to Domain Users | Verify: `Get-SmbShareAccess -Name "<share>"` — Domain Users needs Change |

---

## FSLogix Profile Issues

### Profile Mount Failures

| Symptom | Cause | Resolution |
|---------|-------|------------|
| FSLogix event 25 — "Failed to attach VHD" | AV scanning VHDX during mount | Apply [antivirus exclusions](../configuration/antivirus.md) on session hosts |
| FSLogix event 33 — "VHDX full" | Profile container exceeded `SizeInMBs` | Increase `SizeInMBs` in registry or expand existing VHDX: `Resize-VHD` |
| Profile loads local instead of FSLogix | `Enabled` not set to `1` or `VHDLocations` path is wrong | Verify registry: `Get-ItemProperty HKLM:\SOFTWARE\FSLogix\Profiles` |
| Slow logons (>30 seconds for profile load) | AV scanning, network latency, or oversized profiles | Apply AV exclusions, verify session hosts are on the same network as SOFS, review profile sizes |

### Cloud Cache Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Cloud Cache not syncing to Azure | `CCDLocations` connection string malformed | Verify the pipe-delimited Key Vault reference format: `"\|fslogix/<key-name>\|"` |
| Both `VHDLocations` and `CCDLocations` set | Mutually exclusive — `CCDLocations` silently overrides | Remove `VHDLocations` when using Cloud Cache |

---

## Network Issues

### SMB Connectivity

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `Test-Path` works intermittently | DNS round-robin or SOFS role failover in progress | Wait 30 seconds and retry — SMB3 transparent failover reconnects automatically |
| High latency to SOFS | Session hosts and SOFS VMs on different VLANs/subnets | Place all machines on the same compute network for optimal performance |
| SMB connections dropping | SMB2 being used instead of SMB3 | Verify: `Get-SmbConnection` — ensure dialect is 3.x. SMB3 is required for CA |

---

## Capacity Issues

### Storage Full

| Symptom | Cause | Resolution |
|---------|-------|------------|
| S2D volume full | Profile growth exceeded planned capacity | Expand host volumes, then expand VM data disks, then expand S2D volume: `Resize-VirtualDisk` + `Resize-Partition` |
| VHDX files larger than expected | Users storing large files in profile | Review profile content, consider ODFC containers (Option B) to separate Office data |
| Dynamic disks consuming full allocation | All profile space has been written to at some point | Dynamic provisioning only helps for initial deployment — once data is written, space is consumed. Plan for steady-state, not day-one |

---

## Antivirus Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Profile corruption after AV update | AV product regained control of excluded paths after update | Re-verify exclusions after every AV product update: `Get-MpPreference` |
| S2D performance degraded | AV scanning `C:\ClusterStorage` | Apply SOFS VM exclusions — see [Antivirus Exclusions](../configuration/antivirus.md) |
| Session host CPU spike during logon/logoff | AV scanning VHDX mount/dismount | Apply session host exclusions for `frxsvc.exe`, `frxdrv.sys`, and VHDX extensions |

---

## Diagnostic Commands

Quick reference for diagnostic commands run from a management workstation:

```powershell
# Cluster health
Get-ClusterNode -Cluster "sofs-cluster" | Select-Object Name, State
Get-ClusterGroup -Cluster "sofs-cluster" | Select-Object Name, State, OwnerNode

# S2D health
Get-StoragePool -CimSession "sofs-cluster" | Select-Object FriendlyName, HealthStatus
Get-VirtualDisk -CimSession "sofs-cluster" | Select-Object FriendlyName, HealthStatus, OperationalStatus
Get-PhysicalDisk -CimSession "sofs-cluster" | Select-Object FriendlyName, HealthStatus, MediaType

# SMB shares
Get-SmbShare -CimSession "sofs-01" | Where-Object { $_.ScopeName -ne "*" }
Get-SmbShareAccess -Name "FSLogix" -CimSession "sofs-01"

# Anti-affinity
Get-ClusterGroup -Cluster "azl-cluster" | Where-Object { $_.Name -like "*sofs*" } | Select-Object Name, OwnerNode

# FSLogix (on session host)
Get-ItemProperty HKLM:\SOFTWARE\FSLogix\Profiles
Get-WinEvent -LogName "Microsoft-FSLogix-Apps/Operational" -MaxEvents 20
```

---

## Related

- [Validation](../deployment/validation.md) — Post-deployment verification checklist
- [Permissions](../configuration/permissions.md) — NTFS and SMB permission model
- [Antivirus Exclusions](../configuration/antivirus.md) — Required AV exclusions
- [Capacity Planning](../architecture/capacity-planning.md) — Sizing methodology
