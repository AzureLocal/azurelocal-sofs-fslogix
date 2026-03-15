# Scale-Out File Server (SOFS) Deployment Guide
## Guest S2D Cluster on Azure Local for AVD FSLogix Profiles

---

> **Example naming:** All resource names in this guide use the *Infinite Improbability Corp* fictional company — domain `improbability.cloud`, prefix `iic`, NetBIOS `IMPROBABLE`. Replace with customer-specific values during implementation.

## Resources Required at a Glance

> **Profile storage requirement:** 5 TB usable + 10% growth = **5.5 TB**

Resiliency is applied at **two stacked layers** — a guest S2D two-way mirror inside the VMs and the Azure Local two-way mirror underneath — so raw capacity requirements multiply. Here is the full bill of materials:

| Resource | Specification |
|----------|---------------|
| **Azure Local physical nodes** | 3 minimum |
| **Raw physical disk consumed** | **~25 TB** |
| **Azure Local volume (2-way mirror, usable)** | ~12.5 TB |
| **Windows Server VMs** | 3 × (4 vCPU, 8 GB RAM) |
| **OS disk per VM** | 127 GB (dynamic) |
| **Data disks per VM** | 4 × 1 TB (dynamic), ~4 TB per VM |
| **Guest S2D resiliency** | Two-way mirror |
| **Usable FSLogix space** | **5.5 TB** |
| **Raw-to-usable ratio** | **~4.5 : 1** |

> **The capacity tax is real.** Two-way mirror at the guest layer stacked on two-way mirror at the host layer means 5.5 TB of usable profile storage consumes ~25 TB of raw physical disk. The Azure Local two-way mirror already protects against physical disk and host node failures, and the guest S2D two-way mirror adds a second resiliency layer at the VM level — defense in depth without going overboard. Make sure the customer understands the raw footprint up front and that the cluster has headroom alongside existing workloads. Data disks are dynamically provisioned, so day-one consumption will be much lower than the 25 TB ceiling — it grows as profiles are written.

---

## Architecture Overview

This guide deploys a **3-node Windows Server guest cluster** running Storage Spaces Direct (S2D) with the Scale-Out File Server (SOFS) role, hosted on an Azure Local cluster. The SOFS provides continuously available SMB shares for FSLogix profile containers used by Azure Virtual Desktop session hosts.

**Key design points:**

- 3 Windows Server 2025 Datacenter VMs — `iic-sofs-01`, `iic-sofs-02`, `iic-sofs-03` (Datacenter licensing required for S2D)
- Each VM pinned to a separate Azure Local physical node (`iic-01-n01`, `iic-01-n02`, `iic-01-n03`) via anti-affinity rules
- All VMs connected to the compute network
- **Azure Local layer:** Dedicated ~12.5 TB two-way mirror CSV volume hosts all SOFS VM disks (~25 TB raw)
- **Guest S2D layer:** Two-way mirror provides 5.5 TB usable (5 TB + 10% growth) for FSLogix profiles
- SOFS role presents a single, highly available SMB endpoint (`iic-fslogix`) to AVD session hosts

**Architecture flow:**

```
AVD Session Hosts → \\iic-fslogix\Profiles → SOFS Role (active on all 3 nodes)
                                                  ↓
                                          S2D Storage Pool
                                     (two-way mirror across 3 VMs)
                                                  ↓
                              Azure Local CSV Volume "SOFS-Storage"
                                       (two-way mirror)
```

---

## Storage Capacity Design

The customer requires **5 TB of usable FSLogix profile storage** with 10% growth headroom. Because resiliency is applied at two layers (guest S2D mirror inside the VMs, and the Azure Local two-way mirror underneath), the raw capacity requirement stacks multiplicatively.

### This Design: Guest Two-Way Mirror (Recommended)

| Layer | Calculation | Result |
|-------|-------------|--------|
| Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| Guest S2D two-way mirror | 5.5 TB × 2 copies | **11 TB** raw needed in S2D pool |
| Per-VM data disks | 4 × 1 TB per VM × 3 VMs = 12 TB pool | **1 TB each** (12 disks total, 11 TB used + overhead) |
| Azure Local volume (usable) | 3 VMs × ~4.1 TB (OS + data) | **~12.5 TB** |
| Azure Local two-way mirror (raw) | 12.5 TB × 2 copies | **~25 TB physical disk consumed** |

### For Comparison: Guest Three-Way Mirror

If maximum resiliency is required (survive 2 simultaneous guest-level failures), the numbers look like this:

| Layer | Calculation | Result |
|-------|-------------|--------|
| Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| Guest S2D three-way mirror | 5.5 TB × 3 copies | **16.5 TB** raw needed in S2D pool |
| Per-VM data disks | 4 × 1.4 TB per VM × 3 VMs = 16.8 TB pool | **1.4 TB each** (12 disks total) |
| Azure Local volume (usable) | 3 VMs × ~5.7 TB (OS + data) | **~17 TB** |
| Azure Local two-way mirror (raw) | 17 TB × 2 copies | **~34 TB physical disk consumed** |

| | Two-Way Mirror | Three-Way Mirror |
|---|---|---|
| **Usable profile space** | 5.5 TB | 5.5 TB |
| **Data disk per VM** | 4 × 1 TB | 4 × 1.4 TB |
| **Azure Local volume** | ~12.5 TB | ~17 TB |
| **Raw physical consumed** | **~25 TB** | **~34 TB** |
| **Raw-to-usable ratio** | **~4.5 : 1** | **~6.2 : 1** |
| **Guest-level fault tolerance** | 1 failure | 2 failures |

> **Recommendation:** The two-way mirror design is used throughout this document. The Azure Local two-way mirror underneath already protects against physical disk and host node failures, making the additional three-way mirror at the guest layer hard to justify for an extra ~9 TB of raw capacity — especially for profile data that can be repopulated.

---

## Volume Layout Design: Single vs. Three Volumes

After deciding on resiliency (two-way mirror), choose how to carve the 5.5 TB of usable space into S2D volumes. Both options use the same hardware, the same S2D pool, and the same total capacity — only the volume and share layout differs.

### Option A — Single Volume (Simple)

One volume holds all FSLogix data:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `FSLogixData` | 5,632 GB (5.5 TB) | `Profiles` | Profile containers, ODFC containers, AppData |

**Pros:** Simpler to deploy, monitor, and back up. All free space is shared — no risk of one volume filling while another has headroom.
**Cons:** Cannot set per-workload quotas or monitoring thresholds. A runaway Outlook OST growing on one profile impacts the entire pool.

### Option B — Three Volumes (Granular)

Separate volumes for each FSLogix workload:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `Profiles` | 3,072 GB (3 TB) | `Profiles` | Profile containers (user data, settings) |
| `ODFC` | 1,536 GB (1.5 TB) | `ODFC` | Office Data File Containers (Outlook OST, Teams cache) |
| `AppData` | 1,024 GB (1 TB) | `AppData` | Per-user AppData redirections |
| **Total** | **5,632 GB (5.5 TB)** | | |

**Pros:** Independent monitoring, quotas, and backup schedules per workload. Isolates Outlook OST growth from profile data. Can expand individual volumes as needed.
**Cons:** More volumes and shares to manage. Free space is partitioned — one volume can fill while another has capacity remaining.

> **Recommendation:** Start with **Option A** unless the customer has a specific requirement for per-workload monitoring or ODFC separation (common in large AVD environments with 500+ users).

This guide shows both options side-by-side where the steps differ.

---

## Prerequisites

- Azure Local cluster (`iic-clus01`) with **at least 3 physical nodes** (`iic-01-n01`, `iic-01-n02`, `iic-01-n03`)
- **~25 TB of available raw physical capacity** on the Azure Local cluster for the SOFS storage volume
- Windows Server 2025 Datacenter gallery image registered on the Azure Local cluster (Datacenter is required for S2D)
- Active Directory domain environment (`improbability.cloud`)
- DNS configured for the domain

---

## Phase 1: Prepare the Azure Local Host Environment

### 1.1 — Create the Azure Local Two-Way Mirror Volume

Create a dedicated two-way mirror volume on the Azure Local cluster to host all three SOFS VM disks. This volume needs ~12.5 TB usable to hold the OS and data disks at full provisioned capacity.

```powershell
# ── Create the dedicated SOFS storage volume on Azure Local ──
# Two-way mirror: ~12.5 TB usable ≈ 25 TB raw physical capacity
New-Volume -FriendlyName "SOFS-Storage" `
           -StoragePoolFriendlyName "S2D on iic-clus01" `
           -FileSystem CSVFS_ReFS `
           -ResiliencySettingName Mirror `
           -Size 12800GB
```

> **Why two-way mirror at both layers?** Two-way mirror on Azure Local tolerates a single drive failure or a single node down. The guest S2D two-way mirror inside the VMs adds a second independent resiliency layer. Together this provides defense in depth at a ~4.5:1 raw-to-usable ratio, which is reasonable for profile data.

Verify the volume was created and is healthy:

```powershell
Get-VirtualDisk -FriendlyName "SOFS-Storage" -CimSession "iic-clus01" |
    Select-Object FriendlyName, ResiliencySettingName, Size, HealthStatus, OperationalStatus

Get-ClusterSharedVolume -Cluster "iic-clus01" |
    Where-Object { $_.SharedVolumeInfo.FriendlyVolumeName -match "SOFS-Storage" } |
    Select-Object Name, State
```

The volume will mount as a CSV — note the path (e.g., `C:\ClusterStorage\SOFS-Storage`). All three SOFS VMs and their data disks will be created on this single volume.

### 1.2 — Verify Logical Network and Prerequisites

Before creating Azure Local VMs, ensure the following are in place:

```bash
# Verify your Azure CLI has the stack-hci-vm extension
az extension add --name stack-hci-vm --upgrade

# Set common variables
subscription="<Your Subscription ID>"
resource_group="rg-iic-sofs-azl-eus-01"
location="eastus"
customLocationID="<Your Custom Location Resource ID>"
storagePathId="<Your Storage Path Resource ID>"
imageName="img-iic-ws2025-dc-g2-v1"
logicalNetworkId="<Your Compute Logical Network Resource ID>"
```

You need a Windows Server 2025 Datacenter image already registered as a gallery image on your Azure Local cluster, and a logical network configured for the compute network.

---

## Phase 2: Create the 3 SOFS Node VMs

### 2.1 — Create Network Interfaces

Create a NIC for each SOFS VM on the compute logical network:

```bash
# Create NICs on the compute logical network
for i in 01 02 03; do
  az stack-hci-vm network nic create \
    --resource-group $resource_group \
    --custom-location $customLocationID \
    --location $location \
    --name "iic-sofs-${i}-nic" \
    --subnet-id $logicalNetworkId
done
```

### 2.2 — Create the VMs

```bash
# Create the 3 SOFS VMs
for i in 01 02 03; do
  az stack-hci-vm create \
    --name "iic-sofs-${i}" \
    --resource-group $resource_group \
    --custom-location $customLocationID \
    --location $location \
    --image $imageName \
    --admin-username "sofs_admin" \
    --admin-password "<YourSecurePassword>" \
    --computer-name "iic-sofs-${i}" \
    --hardware-profile memory-mb="8192" processors="4" \
    --nics "iic-sofs-${i}-nic" \
    --storage-path-id $storagePathId \
    --authentication-type all \
    --enable-agent true
done
```

### 2.3 — Create and Attach Data Disks

Each VM needs 4 × 1 TB data disks for the S2D storage pool. Create the disks and then attach them:

```bash
# Create 4 data disks per VM (12 disks total)
for i in 01 02 03; do
  for d in 1 2 3 4; do
    az stack-hci-vm disk create \
      --resource-group $resource_group \
      --custom-location $customLocationID \
      --location $location \
      --name "iic-sofs-${i}-data${d}" \
      --size-gb 1024 \
      --dynamic true \
      --storage-path-id $storagePathId
  done
done

# Attach the data disks to each VM
for i in 01 02 03; do
  az stack-hci-vm disk attach \
    --resource-group $resource_group \
    --vm-name "iic-sofs-${i}" \
    --disks "iic-sofs-${i}-data1" "iic-sofs-${i}-data2" "iic-sofs-${i}-data3" "iic-sofs-${i}-data4" \
    --yes
done
```

### 2.4 — Verify VMs and Disks

```bash
# List VMs
az stack-hci-vm list --resource-group $resource_group -o table

# Verify data disks on each VM
for i in 01 02 03; do
  echo "=== iic-sofs-${i} ==="
  az stack-hci-vm show \
    --resource-group $resource_group \
    --name "iic-sofs-${i}" \
    --query "{name:name, dataDisks:properties.storageProfile.dataDisks}"
done
```

### 2.5 — Verify VM Placement

Azure Local Arc VMs are Hyper-V VMs under the hood and appear as cluster groups in the Windows Failover Cluster. From a cluster node, confirm each VM is running on a separate physical node:

```powershell
Get-ClusterGroup -Cluster "iic-clus01" | Where-Object { $_.Name -like "iic-sofs*" } |
    Select-Object Name, OwnerNode, State
```

You should see each VM on a different node. If not, live migrate them before proceeding:

```powershell
Move-ClusterVirtualMachineRole -Name "iic-sofs-01" -Node "iic-01-n01" -Cluster "iic-clus01"
Move-ClusterVirtualMachineRole -Name "iic-sofs-02" -Node "iic-01-n02" -Cluster "iic-clus01"
Move-ClusterVirtualMachineRole -Name "iic-sofs-03" -Node "iic-01-n03" -Cluster "iic-clus01"
```

---

## Phase 3: Configure Anti-Affinity Rules

Anti-affinity rules are configured at the Windows Failover Cluster level. Azure Local Arc VMs are managed as cluster groups, so these cmdlets apply regardless of whether the VMs were created via `az stack-hci-vm` or locally. This ensures the three SOFS VMs always run on different Azure Local physical nodes so a single host failure only takes out one S2D node.

### 3.1 — Create the Anti-Affinity Rule (Azure Local / Windows Server 2025)

```powershell
# Create anti-affinity rule (DifferentNode type)
New-ClusterAffinityRule -Name "SOFS-AntiAffinity" `
                        -RuleType DifferentNode `
                        -Cluster "iic-clus01"

# Add all three SOFS VMs to the rule
Add-ClusterGroupToAffinityRule -Groups "iic-sofs-01","iic-sofs-02","iic-sofs-03" `
                               -Name "SOFS-AntiAffinity" `
                               -Cluster "iic-clus01"

# Enable the rule
Set-ClusterAffinityRule -Name "SOFS-AntiAffinity" `
                        -Enabled 1 `
                        -Cluster "iic-clus01"

# Verify the rule
Get-ClusterAffinityRule -Name "SOFS-AntiAffinity" -Cluster "iic-clus01"
```

Expected output:

```
Name                RuleType       Groups                                    Enabled
----                -----------    -------                                   -------
SOFS-AntiAffinity   DifferentNode  {iic-sofs-01, iic-sofs-02, iic-sofs-03}  1
```

### 3.2 — Alternative: Legacy AntiAffinityClassNames Method

If the `New-ClusterAffinityRule` cmdlet is not available (older builds), use the classic approach:

```powershell
$AntiAffinity = New-Object System.Collections.Specialized.StringCollection
$AntiAffinity.Add("SOFSCluster")

(Get-ClusterGroup -Name "iic-sofs-01" -Cluster "iic-clus01").AntiAffinityClassNames = $AntiAffinity
(Get-ClusterGroup -Name "iic-sofs-02" -Cluster "iic-clus01").AntiAffinityClassNames = $AntiAffinity
(Get-ClusterGroup -Name "iic-sofs-03" -Cluster "iic-clus01").AntiAffinityClassNames = $AntiAffinity

# Verify
Get-ClusterGroup -Cluster "iic-clus01" |
    Where-Object { $_.Name -like "iic-sofs*" } |
    Format-List Name, AntiAffinityClassNames
```

> **Note:** `AntiAffinityClassNames` is a *soft* rule — the cluster will *try* to keep VMs apart but will allow co-location if no other option exists (e.g., during host maintenance). The `New-ClusterAffinityRule` with `DifferentNode` is the preferred approach on Azure Local 23H2+ / Windows Server 2025.

---

## Phase 4: Post-Deployment VM Configuration

The OS is already deployed as part of the Azure Local VM creation in Phase 2 (via the gallery image). Domain join can be handled during VM creation using Azure Arc guest configuration or via a post-deployment script.

### 4.1 — Verify Domain Join and Network Configuration

Connect to each SOFS VM (via RDP or Azure Arc remote access) and verify:

```powershell
# Verify domain membership
(Get-WmiObject Win32_ComputerSystem).Domain

# Verify hostname
hostname

# Verify network — should be on the compute network with correct IP
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*" }

# Verify DNS resolution
Resolve-DnsName improbability.cloud
```

### 4.2 — IP Address Reference

| VM Name       | IP Address   | Role      |
|---------------|--------------|-----------|
| iic-sofs-01   | 10.42.10.21  | S2D Node  |
| iic-sofs-02   | 10.42.10.22  | S2D Node  |
| iic-sofs-03   | 10.42.10.23  | S2D Node  |

> **Note:** If the VMs were deployed with DHCP, assign static IPs or DHCP reservations before proceeding with cluster creation. All SOFS nodes must have stable, predictable IP addresses.

---

## Phase 5: Install Required Roles and Features

Run on **all three SOFS VMs**:

```powershell
# Install Failover Clustering, File Server, and S2D management tools
Install-WindowsFeature -Name Failover-Clustering,
                              FS-FileServer,
                              RSAT-Clustering-PowerShell,
                              RSAT-Clustering-Mgmt `
                       -IncludeManagementTools -Restart
```

---

## Phase 6: Validate and Create the Guest Failover Cluster

### 6.1 — Validate the Cluster

Run from any one of the SOFS VMs (or a management machine with RSAT):

```powershell
Test-Cluster -Node "iic-sofs-01","iic-sofs-02","iic-sofs-03" -Include "Inventory","Network","System Configuration"
```

> **Tip:** Skip the "Storage" tests since we're using S2D inside VMs, not shared SAS/FC storage. Review the validation report for any warnings.

### 6.2 — Create the Failover Cluster

```powershell
New-Cluster -Name "iic-sofs" `
            -Node "iic-sofs-01","iic-sofs-02","iic-sofs-03" `
            -StaticAddress "10.42.10.25" `
            -NoStorage
```

- **`-Name`**: The cluster CNO (Computer Name Object) — will be created in AD
- **`-StaticAddress`**: A free IP on the compute network for the cluster itself
- **`-NoStorage`**: Skips automatic storage enumeration (S2D will handle this)

### 6.3 — Configure a Cloud Witness

An Azure Storage Account cloud witness is the recommended quorum model for a 3-node cluster:

```powershell
Set-ClusterQuorum -Cluster "iic-sofs" `
                  -CloudWitness `
                  -AccountName "stsofswitnessiic01" `
                  -AccessKey "<YourStorageAccountAccessKey>" `
                  -Endpoint "core.windows.net"
```

> Alternatively, use a file share witness on an independent server (not one of the SOFS nodes).

---

## Phase 7: Enable Storage Spaces Direct (S2D)

### 7.1 — Clean the Data Disks

On each SOFS VM, ensure the data disks are raw/uninitialized:

```powershell
# Run on each SOFS node — clears all non-OS disks
Get-Disk | Where-Object { $_.Number -ne 0 -and $_.IsBoot -eq $false } |
    Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
```

### 7.2 — Enable S2D

Run from one node:

```powershell
Enable-ClusterStorageSpacesDirect -Cluster "iic-sofs" -Confirm:$false
```

> **Important for nested/guest S2D:** Since these are VMs, S2D treats all disks as capacity (flat — no caching tier). This is expected and correct.

### 7.3 — Apply Guest S2D Tuning (Registry)

On **each SOFS VM**, increase the S2D I/O timeout to handle the additional latency of running inside a VM:

```powershell
# Increase spaceport timeout (default 30 → 60 seconds)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters" `
                 -Name "HwTimeout" `
                 -Value 0x0000003C `
                 -Type DWord

# Disable automatic physical disk replacement (not applicable in VMs)
Get-StorageSubSystem Clus* |
    Set-StorageHealthSetting -Name "System.Storage.PhysicalDisk.AutoReplace.Enabled" -Value "False"
```

### 7.4 — Create the S2D Volume(s)

#### Option A — Single Volume

Create one two-way mirror volume for all FSLogix data. Sized for 5 TB usable plus 10% growth headroom (5,632 GB ≈ 5.5 TB):

```powershell
New-Volume -FriendlyName "FSLogixData" `
           -StoragePoolFriendlyName "S2D on iic-sofs" `
           -FileSystem CSVFS_ReFS `
           -ResiliencySettingName Mirror `
           -NumberOfDataCopies 2 `
           -Size 5632GB
```

#### Option B — Three Volumes

Create separate volumes for Profiles, ODFC, and AppData:

```powershell
# Profiles — 3 TB
New-Volume -FriendlyName "Profiles" `
           -StoragePoolFriendlyName "S2D on iic-sofs" `
           -FileSystem CSVFS_ReFS `
           -ResiliencySettingName Mirror `
           -NumberOfDataCopies 2 `
           -Size 3072GB

# ODFC (Office Data File Containers) — 1.5 TB
New-Volume -FriendlyName "ODFC" `
           -StoragePoolFriendlyName "S2D on iic-sofs" `
           -FileSystem CSVFS_ReFS `
           -ResiliencySettingName Mirror `
           -NumberOfDataCopies 2 `
           -Size 1536GB

# AppData — 1 TB
New-Volume -FriendlyName "AppData" `
           -StoragePoolFriendlyName "S2D on iic-sofs" `
           -FileSystem CSVFS_ReFS `
           -ResiliencySettingName Mirror `
           -NumberOfDataCopies 2 `
           -Size 1024GB
```

> **Note on `-NumberOfDataCopies 2`:** On a 3-node S2D cluster, the default mirror is three-way. You must explicitly specify `-NumberOfDataCopies 2` to force a two-way mirror. With Option A, this consumes ~11 TB of the 12 TB S2D pool (5.5 TB × 2 copies), leaving ~1 TB headroom for S2D metadata and overhead.

Verify:

```powershell
Get-Volume -CimSession "iic-sofs" | Where-Object { $_.FileSystemLabel -match "FSLogix|Profiles|ODFC|AppData" }
Get-VirtualDisk -CimSession "iic-sofs"
```

---

## Phase 8: Add the Scale-Out File Server Role

### 8.1 — Add the SOFS Cluster Role

```powershell
Add-ClusterScaleOutFileServerRole -Name "iic-fslogix" -Cluster "iic-sofs"
```

- **`-Name`**: This is the **client access point** — the NetBIOS/DNS name clients will connect to (e.g., `\\iic-fslogix\Profiles`). It creates a Computer Object in AD and a DNS A record.

Verify:

```powershell
Get-ClusterGroup -Cluster "iic-sofs" | Where-Object { $_.GroupType -eq "ScaleOutFileServer" }
```

### 8.2 — Create the FSLogix SMB Share(s)

#### Option A — Single Share

```powershell
# Identify the CSV path for the volume
$CSVPath = (Get-ClusterSharedVolume -Cluster "iic-sofs" |
    Where-Object { $_.SharedVolumeInfo.FriendlyVolumeName -match "FSLogixData" }
).SharedVolumeInfo.FriendlyVolumeName

# Create the share directory
$SharePath = "$CSVPath\Profiles"
New-Item -Path $SharePath -ItemType Directory -Force

# Create the SMB share with Continuous Availability enabled
New-SmbShare -Name "Profiles" `
             -Path $SharePath `
             -ScopeName "iic-fslogix" `
             -ContinuouslyAvailable $true `
             -CachingMode None `
             -FullAccess "IMPROBABLE\Domain Admins" `
             -ChangeAccess "IMPROBABLE\Domain Users" `
             -FolderEnumerationMode AccessBased
```

#### Option B — Three Shares

```powershell
# Helper: create a CA share on a named CSV volume
function New-SOFSShare {
    param([string]$VolumeName, [string]$ShareName)
    $csv = (Get-ClusterSharedVolume -Cluster "iic-sofs" |
        Where-Object { $_.SharedVolumeInfo.FriendlyVolumeName -match $VolumeName }
    ).SharedVolumeInfo.FriendlyVolumeName
    $path = "$csv\$ShareName"
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    New-SmbShare -Name $ShareName `
                 -Path $path `
                 -ScopeName "iic-fslogix" `
                 -ContinuouslyAvailable $true `
                 -CachingMode None `
                 -FullAccess "IMPROBABLE\Domain Admins" `
                 -ChangeAccess "IMPROBABLE\Domain Users" `
                 -FolderEnumerationMode AccessBased
}

New-SOFSShare -VolumeName "Profiles" -ShareName "Profiles"
New-SOFSShare -VolumeName "ODFC"     -ShareName "ODFC"
New-SOFSShare -VolumeName "AppData"  -ShareName "AppData"
```

> **Critical settings (both options):**
> - **`-ContinuouslyAvailable $true`** — Required for SOFS. Enables transparent failover via SMB3 persistent handles.
> - **`-CachingMode None`** — Disables offline file caching (FSLogix manages its own caching).
> - **`-ScopeName "iic-fslogix"`** — Associates the share with the SOFS cluster role, not a single node.

---

## Phase 9: Configure NTFS Permissions for FSLogix

FSLogix requires specific NTFS permissions on each profile share. The following function applies the correct ACL to a share root folder and can be called once (Option A) or three times (Option B):

```powershell
function Set-FSLogixNTFS {
    param([string]$SharePath, [string]$Domain = "IMPROBABLE")

    $acl = Get-Acl $SharePath
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, remove inherited

    # CREATOR OWNER — Modify (subfolders and files only)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER", "Modify", "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")))

    # Domain Users — Modify (this folder only) — allows creating their profile folder
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$Domain\Domain Users", "Modify", "None", "None", "Allow")))

    # Domain Admins — Full Control (this folder, subfolders, and files)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$Domain\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    # SYSTEM — Full Control
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    Set-Acl -Path $SharePath -AclObject $acl
}
```

#### Option A — Single Share

```powershell
Set-FSLogixNTFS -SharePath "C:\ClusterStorage\FSLogixData\Profiles"
```

#### Option B — Three Shares

```powershell
Set-FSLogixNTFS -SharePath "C:\ClusterStorage\Profiles\Profiles"
Set-FSLogixNTFS -SharePath "C:\ClusterStorage\ODFC\ODFC"
Set-FSLogixNTFS -SharePath "C:\ClusterStorage\AppData\AppData"
```

> **Why this structure:** Each user's FSLogix agent creates a subfolder (by SID) and a VHDX inside it. CREATOR OWNER ensures users can only modify their own profile folder. The "Modify, this folder only" entry for Domain Users lets the agent create the initial folder.

---

## Phase 10: Antivirus Exclusions

### 10.1 — Antivirus Exclusions on SOFS Nodes

On each of the three SOFS VMs, configure the following AV exclusions:

- The entire CSV volume path containing the FSLogix share(s)
- `*.VHD` and `*.VHDX` file extensions
- SMB-related processes if your AV inspects network traffic

### 10.2 — Antivirus Exclusions on AVD Session Hosts (When Deployed)

When you deploy your AVD session hosts, FSLogix profile corruption is commonly caused by antivirus scanning. Exclude:

- **Processes:** `frxsvc.exe`, `frxdrv.sys`, `frxccd.sys`
- **Paths:** `%ProgramFiles%\FSLogix\Apps\*`, the VHDX mount points (typically `%TEMP%\intlMountPoints\*`)
- **File types:** `*.VHD`, `*.VHDX`

---

## Phase 11: Validation and Testing

### 11.1 — Verify SOFS Access

From any machine on the compute network:

#### Option A — Single Share

```powershell
Test-Path "\\iic-fslogix\Profiles"

Get-SmbShare -CimSession "iic-sofs-01" -Name "Profiles" |
    Select-Object Name, ScopeName, ContinuouslyAvailable, CachingMode
```

#### Option B — Three Shares

```powershell
"Profiles","ODFC","AppData" | ForEach-Object {
    [PSCustomObject]@{ Share = $_; Accessible = (Test-Path "\\iic-fslogix\$_") }
}

Get-SmbShare -CimSession "iic-sofs-01" -Name "Profiles","ODFC","AppData" |
    Select-Object Name, ScopeName, ContinuouslyAvailable, CachingMode
```

### 11.2 — Test Failover

1. Log into an AVD session so a FSLogix profile is mounted.
2. Identify which SOFS node currently owns the connection:

```powershell
Get-SmbOpenFile -CimSession "iic-sofs-01","iic-sofs-02","iic-sofs-03" |
    Where-Object { $_.Path -like "*Profiles*" -or $_.Path -like "*ODFC*" -or $_.Path -like "*AppData*" }
```

3. Live migrate or drain the owning SOFS VM to simulate failure:

```powershell
# On the Azure Local cluster — drain the SOFS VM's host node
Suspend-ClusterNode -Name "iic-01-n01" -Cluster "iic-clus01" -Drain
```

4. Verify the user's session remains connected (SMB3 transparent failover handles the reconnection).

### 11.3 — Verify Anti-Affinity

```powershell
# Confirm all three SOFS VMs are on separate physical nodes
Get-ClusterGroup -Cluster "iic-clus01" |
    Where-Object { $_.Name -like "iic-sofs*" } |
    Select-Object Name, OwnerNode

# Verify the rule is active
Get-ClusterAffinityRule -Name "SOFS-AntiAffinity" -Cluster "iic-clus01"
```

---

## Summary: IP and Name Reference

### Option A — Single Volume

| Component          | Name / IP                     | Purpose                              |
|--------------------|-------------------------------|--------------------------------------|
| Azure Local Volume | SOFS-Storage (~12.5 TB, 2-way mirror) | Hosts all SOFS VM disks (~25 TB raw) |
| SOFS VM 1          | iic-sofs-01 / 10.42.10.21    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 2          | iic-sofs-02 / 10.42.10.22    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 3          | iic-sofs-03 / 10.42.10.23    | S2D node (127 GB OS + 4×1 TB data)   |
| Guest Cluster CNO  | iic-sofs / 10.42.10.25       | Failover cluster name                |
| SOFS Access Point  | iic-fslogix                   | Client access (`\\iic-fslogix\Profiles`) |
| Guest S2D Volume   | FSLogixData (5.5 TB, 2-way mirror) | Usable profile storage          |
| Anti-Affinity Rule | SOFS-AntiAffinity             | Keeps VMs on separate Azure Local nodes |

### Option B — Three Volumes

| Component          | Name / IP                     | Purpose                              |
|--------------------|-------------------------------|--------------------------------------|
| Azure Local Volume | SOFS-Storage (~12.5 TB, 2-way mirror) | Hosts all SOFS VM disks (~25 TB raw) |
| SOFS VM 1          | iic-sofs-01 / 10.42.10.21    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 2          | iic-sofs-02 / 10.42.10.22    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 3          | iic-sofs-03 / 10.42.10.23    | S2D node (127 GB OS + 4×1 TB data)   |
| Guest Cluster CNO  | iic-sofs / 10.42.10.25       | Failover cluster name                |
| SOFS Access Point  | iic-fslogix                   | Client access (`\\iic-fslogix\<share>`) |
| Profiles Volume    | Profiles (3 TB, 2-way mirror) | Profile containers                  |
| ODFC Volume        | ODFC (1.5 TB, 2-way mirror)   | Office Data File Containers         |
| AppData Volume     | AppData (1 TB, 2-way mirror)  | Per-user AppData redirections       |
| Anti-Affinity Rule | SOFS-AntiAffinity             | Keeps VMs on separate Azure Local nodes |

---

## Important Notes and Considerations

**Licensing:** Windows Server Datacenter edition is required for S2D. Each SOFS VM needs appropriate licensing. If you're already licensing Azure Local hosts with Datacenter, your guest VM rights may cover this.

**Supportability:** Microsoft's official guidance is that S2D in guest VMs is supported on Windows Server (not Azure Local OS as the guest). Since you're running Windows Server 2025 Datacenter *inside* the VMs on an Azure Local host, this is a supported configuration. Do not mix the Azure Local cluster's own S2D storage volumes with SOFS shares on the same cluster — the guest cluster approach keeps these cleanly separated.

**Network:** All SOFS VMs should be on the same compute network/VLAN as the AVD session hosts for optimal latency. If you have a dedicated storage VLAN, you could add a second NIC to each SOFS VM for intra-cluster (S2D replication) traffic, but for most deployments a single compute network NIC is sufficient.

**Capacity planning:** This design provisions 5.5 TB usable (5 TB + 10% growth) for FSLogix profiles. The guest S2D two-way mirror consumes 11 TB of the 12 TB pool (4 × 1 TB data disks × 3 VMs), hosted on a ~12.5 TB two-way mirror Azure Local volume, requiring **~25 TB of raw physical capacity** on the cluster. Data disks are dynamically provisioned so they won't consume the full allocation from day one — only as profiles are written. Monitor utilization and expand the Azure Local volume and VM data disks if growth exceeds the 10% buffer.

**Backup and DR with FSLogix Cloud Cache:** SOFS with continuously available shares requires special backup considerations. Standard VSS-based backup tools may not work directly against the SOFS share. **FSLogix Cloud Cache works with Azure Local** — Cloud Cache operates against any SMB share, and the SOFS share is SMB. You can configure Cloud Cache on your AVD session hosts with the SOFS as the primary storage provider and an Azure Blob Storage account or Azure Files share as a secondary provider. This gives you:

- Active replication of profile data to Azure for DR without separate backup infrastructure
- User session continuity if the SOFS becomes temporarily unavailable (Cloud Cache serves from local cache)
- Up to 4 storage providers (the practical limit) in any combination of SMB and Azure Blob
- Automatic resync when a provider comes back online after an outage

Cloud Cache writes to a local cache on the session host first, then asynchronously flushes to all providers. This means even if the SOFS goes down mid-session, the user continues working from the local cache. At sign-out, Cloud Cache ensures all providers are synchronized before completing. For environments without Cloud Cache, consider a backup agent inside the guest cluster that can back up the FSLogix VHDX files on a schedule during off-hours when profiles are not mounted.

---

## Considerations for AVD Deployment

> **This section is not part of the SOFS deployment itself.** These are items to plan for when you deploy your AVD session hosts that will consume the SOFS share(s).

### Option A — Single Share FSLogix Configuration

**FSLogix Profile Container (`VHDLocations`):** On each AVD session host (or via Group Policy), point FSLogix to the SOFS share:

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\Profiles
    SizeInMBs                        REG_DWORD    30000
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
```

### Option B — Three Share FSLogix Configuration

**Profile Containers** point to the `Profiles` share:

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\Profiles
    SizeInMBs                        REG_DWORD    30000
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
```

**Office Data File Containers (ODFC)** point to the separate `ODFC` share:

```
HKLM\SOFTWARE\Policies\FSLogix\ODFC
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\ODFC
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
    IncludeOutlookPersonalization    REG_DWORD    1
```

> **Note:** When using separate ODFC containers, Outlook OST files, Teams cache, and OneDrive data are stored in the ODFC VHDX instead of inside the profile container. This keeps Profile containers smaller and allows independent sizing.

**AppData redirection** can use folder redirection GPO to `\\iic-fslogix\AppData\%USERNAME%` or a separate FSLogix container — choose based on the customer's user persona.

### GPO Path

`Computer Configuration → Administrative Templates → FSLogix → Profile Containers`

### Cloud Cache Configuration (Optional — for DR to Azure)

If using Cloud Cache instead of `VHDLocations`, configure `CCDLocations` with the SOFS as primary and an Azure provider as secondary:

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled          REG_DWORD    1
    CCDLocations     REG_SZ       type=smb,name="SOFS",connectionString=\\iic-fslogix\Profiles;type=azure,name="AzureBlob",connectionString="|fslogix/<KEY-NAME>|"
    ClearCacheOnLogoff              REG_DWORD    1
    FlipFlopProfileDirectoryName    REG_DWORD    1
```

**Network placement:** AVD session hosts should be on the same compute network/VLAN as the SOFS VMs for optimal latency. Placing the session hosts and SOFS on the same subnet eliminates routing hops and provides the best login/logoff performance.

**Profile sizing:** Plan your FSLogix max profile size (`SizeInMBs`) based on user workload. The default 30 GB is generous for most office workers. If users have heavy Outlook OST files or OneDrive cache, you may need more. Monitor actual usage after deployment and adjust.

---

## Automation Scripts

The SOFS solution includes automation for both phases of the deployment. All scripts are in the [`azurelocal-sofs-fslogix`](https://github.com/AzureLocal/azurelocal-sofs-fslogix) repository:

### Phase 1 — Azure Resource Provisioning

| Tool | Path | Description |
|------|------|-------------|
| **Terraform** | [`src/terraform/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/src/terraform) | Full IaC: resource group, Key Vault, cloud witness, Arc VMs, data disks. Auto-generates Ansible inventory. Run via `Deploy-SOFS.ps1` wrapper or `terraform apply`. |
| **Bicep** | [`src/bicep/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/src/bicep) | Subscription-scope Bicep modules for the same resources. Run via `Deploy-SOFS-Azure.ps1` wrapper. |
| **PowerShell** | [`src/powershell/Deploy-SOFS-Azure.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/Deploy-SOFS-Azure.ps1) | Az CLI wrapper — creates resource group, storage account witness, VMs, and data disks. Suitable when IaC is not required. |
| **Ansible** | [`src/ansible/playbooks/deploy-azure-resources.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/deploy-azure-resources.yml) | Playbook using `azure.azcollection` modules for the same provisioning. |

### Phase 2 — Guest Cluster Configuration (Phases 4–11 of this Guide)

| Tool | Path | Description |
|------|------|-------------|
| **PowerShell** | [`src/powershell/Configure-SOFS-Cluster.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/Configure-SOFS-Cluster.ps1) | PSRemoting-based script — runs all 11 configuration phases against the SOFS VMs. |
| **Ansible** | [`src/ansible/playbooks/configure-sofs-cluster.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/configure-sofs-cluster.yml) | WinRM+Kerberos playbook for the same configuration phases. |

> **Note:** Terraform and Bicep handle only Phase 1 (Azure resource provisioning). Guest OS cluster configuration (Phases 4–11) is handled by the PowerShell script or Ansible playbook.

---

## Related Resources

| | |
|---|---|
| **Repository** | [AzureLocal/azurelocal-sofs-fslogix](https://github.com/AzureLocal/azurelocal-sofs-fslogix) |
| **AVD Repository** | [AzureLocal/azure_avd](https://github.com/AzureLocal/azure_avd) |
| **Website** | [azurelocal.cloud](https://azurelocal.cloud) |
| **Path** | `docs/reference/sofs-deployment-guide.md` |
| **Maintained by** | Hybrid Cloud Solutions LLC |
