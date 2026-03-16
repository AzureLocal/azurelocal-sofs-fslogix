# Scale-Out File Server (SOFS) Deployment Guide
## Guest Scale Out File Server on Azure Local for AVD FSLogix Profiles

| | |
|---|---|
| **Version** | 1.0 |
| **Last Updated** | March 2026 |
| **Maintained by** | Hybrid Cloud Solutions LLC |

---

### What This Guide Covers

This guide is a **standalone, self-contained document** — it does not depend on any other files in the repository and can be followed on its own from start to finish. It walks through the complete design and deployment of a **3-node Scale-Out File Server (SOFS) guest cluster** running Storage Spaces Direct (S2D) on Azure Local, purpose-built to host FSLogix profile containers for Azure Virtual Desktop (AVD) session hosts.

The document is organized in three parts:

- **Part I — Design** covers architecture decisions you need to make before touching any infrastructure: host-layer volume layout for fault isolation (three separate volumes vs. one shared volume), storage capacity planning with raw-to-usable ratios for two-way and three-way mirrors, and guest-layer volume layout for FSLogix shares (single volume for simplicity vs. three volumes for NTFS metadata isolation and per-workload monitoring at scale).
- **Part II — Implementation** provides the full 11-phase deployment, from creating Azure Local host volumes and provisioning Arc VMs through guest cluster creation, S2D configuration, SOFS role setup, SMB share creation, NTFS permissions for FSLogix, antivirus exclusions, and final validation. Every phase includes the exact PowerShell or Azure CLI commands with explicit variable names and inline explanations — no shorthand, no implicit assumptions.
- **Part III — Reference** consolidates IP/name tables, operational notes, AVD session host configuration (FSLogix registry keys, identity model, Cloud Cache for DR), a full inventory of the repository's automation scripts with GitHub links, and related resources.

The companion [`azurelocal-sofs-fslogix`](https://github.com/AzureLocal/azurelocal-sofs-fslogix) repository contains automation that can execute these same steps via Terraform, Bicep, ARM templates, PowerShell scripts, and Ansible playbooks — see [Automation Scripts](#automation-scripts) for a detailed breakdown of what each tool covers and which phases it automates.

---

## Table of Contents

**Part I — Design**

1. [Resources Required at a Glance](#resources-required-at-a-glance)
2. [Architecture Overview](#architecture-overview)
3. [Host Volume Layout: Fault Isolation](#host-volume-layout-fault-isolation)
4. [Storage Capacity Design](#storage-capacity-design)
5. [Guest Volume Layout: Single vs. Three FSLogix Shares](#guest-volume-layout-single-vs-three-fslogix-shares)

**Part II — Implementation**

6. [Prerequisites](#prerequisites)
7. [Phase 1: Prepare the Azure Local Host Environment](#phase-1-prepare-the-azure-local-host-environment)
8. [Phase 2: Create the 3 SOFS Node VMs](#phase-2-create-the-3-sofs-node-vms)
9. [Phase 3: Configure Anti-Affinity Rules](#phase-3-configure-anti-affinity-rules)
10. [Phase 4: Post-Deployment VM Configuration](#phase-4-post-deployment-vm-configuration)
11. [Phase 5: Install Required Roles and Features](#phase-5-install-required-roles-and-features)
12. [Phase 6: Validate and Create the Guest Failover Cluster](#phase-6-validate-and-create-the-guest-failover-cluster)
13. [Phase 7: Enable Storage Spaces Direct (S2D)](#phase-7-enable-storage-spaces-direct-s2d)
14. [Phase 8: Add the Scale-Out File Server Role](#phase-8-add-the-scale-out-file-server-role)
15. [Phase 9: Configure NTFS Permissions for FSLogix](#phase-9-configure-ntfs-permissions-for-fslogix)
16. [Phase 10: Antivirus Exclusions](#phase-10-antivirus-exclusions)
17. [Phase 11: Validation and Testing](#phase-11-validation-and-testing)

**Part III — Reference**

18. [Summary: IP and Name Reference](#summary-ip-and-name-reference)
19. [Important Notes and Considerations](#important-notes-and-considerations)
20. [Considerations for AVD Deployment](#considerations-for-avd-deployment)
21. [Automation Scripts](#automation-scripts)
22. [Related Resources](#related-resources)

---

# Part I — Design

## Resources Required at a Glance

> **Profile storage requirement:** 5 TB usable + 10% growth = **5.5 TB**

> **All capacity numbers in this document are examples** based on a 5 TB usable profile storage target. Your deployment will differ based on user count, profile sizes, and resiliency choices. Use the [Azure Local Sizer (Odin)](https://azure.github.io/odinforazurelocal/sizer/) to calculate raw capacity requirements for your specific environment.  All calculations through out this document should not be taken as fact and should be double-checked against the sizer for your specific environment.

Resiliency is applied at **two stacked layers** — a guest S2D two-way mirror inside the VMs and the Azure Local two-way mirror underneath — so raw capacity requirements multiply.

### Guest Two-Way Mirror (Recommended)

| Resource | Specification |
|----------|---------------|
| **Azure Local physical nodes** | 3 minimum |
| **Raw physical disk consumed** | **~25 TB** |
| **Azure Local host volumes (2-way mirror)** | 3 × ~4.2 TB usable (one per SOFS VM) |
| **Windows Server 2025 Datacenter: Azure Edition Core (Gen2) VMs** | 3 × (4 vCPU, 8 GB RAM) |
| **OS disk per VM** | 127 GB (dynamic) |
| **Data disks per VM** | 4 × 1 TB (dynamic), ~4 TB per VM |
| **Guest S2D resiliency** | Two-way mirror |
| **Usable FSLogix space** | **5.5 TB** |
| **Raw-to-usable ratio** | **~4.5 : 1** |

### Guest Three-Way Mirror (Maximum Resiliency)

| Resource | Specification |
|----------|---------------|
| **Azure Local physical nodes** | 3 minimum |
| **Raw physical disk consumed** | **~34 TB** |
| **Azure Local host volumes (2-way mirror)** | 3 × ~5.7 TB usable (one per SOFS VM) |
| **Windows Server 2025 Datacenter: Azure Edition Core (Gen2) VMs** | 3 × (4 vCPU, 8 GB RAM) |
| **OS disk per VM** | 127 GB (dynamic) |
| **Data disks per VM** | 4 × 1.4 TB (dynamic), ~5.6 TB per VM |
| **Guest S2D resiliency** | Three-way mirror |
| **Usable FSLogix space** | **5.5 TB** |
| **Raw-to-usable ratio** | **~6.2 : 1** |

> **The capacity tax is real.** Two-way mirror at the guest layer stacked on two-way mirror at the host layer means 5.5 TB of usable profile storage consumes ~25 TB of raw physical disk (or ~34 TB with a three-way guest mirror). The Azure Local two-way mirror already protects against physical disk and host node failures, and the guest S2D mirror adds a second resiliency layer at the VM level — defense in depth without going overboard. Make sure the customer understands the raw footprint up front and that the cluster has headroom alongside existing workloads. Data disks are dynamically provisioned, so day-one consumption will be much lower than the ceiling — it grows as profiles are written.

---

## Architecture Overview

This guide deploys a **3-node Windows Server guest cluster** running Storage Spaces Direct (S2D) with the Scale-Out File Server (SOFS) role, hosted on an Azure Local cluster. The SOFS provides continuously available SMB shares for FSLogix profile containers used by Azure Virtual Desktop session hosts.

**Key design points:**

- 3 **Windows Server 2025 Datacenter: Azure Edition Core (Gen2)** VMs — `iic-sofs-01`, `iic-sofs-02`, `iic-sofs-03` (Datacenter licensing required for S2D)
- Each VM pinned to a separate Azure Local physical node (`iic-01-n01`, `iic-01-n02`, `iic-01-n03`) via anti-affinity rules
- All VMs connected to the compute network
- **Azure Local layer (recommended):** Three separate two-way mirror CSV volumes — one per SOFS VM (~4.2 TB usable each, ~8.4 TB raw each, ~25 TB total raw). Isolating each VM on its own volume eliminates shared-fate storage failures. A single-volume alternative is available if the cluster cannot accommodate three separate volumes (see [Host Volume Layout](#host-volume-layout-fault-isolation)).
- **Guest S2D layer:** Two-way mirror provides 5.5 TB usable (5 TB + 10% growth) for FSLogix profiles
- SOFS role presents a single, highly available SMB endpoint (`iic-fslogix`) to AVD session hosts

**Architecture diagram:** Three host volumes (fault isolation) with Option B guest volumes (workload isolation).

<div align="center">
  <img src="../../assets/images/sofs-arch-3vol-option-b.png" alt="SOFS Architecture — Three Host Volumes + Option B" />
</div>

> **Why three separate host volumes?** If all three SOFS VMs sit on a single Azure Local volume, that volume is a shared-fate dependency — a volume-level issue takes out the entire guest cluster. With three volumes, a single volume failure only affects one SOFS node. The guest S2D two-way mirror continues operating on the remaining two nodes with no data loss and no interruption to AVD sessions.

---

## Host Volume Layout: Fault Isolation

After deciding on resiliency (two-way mirror), decide how to lay out the Azure Local host-layer CSV volumes that hold the SOFS VMs. This is a critical design decision for fault isolation.

### Recommended: Three Volumes (One Per VM)

Create three separate Azure Local CSV volumes — one per SOFS VM. Each volume holds one VM's OS disk and four data disks (~4.2 TB usable per volume).

| Volume | Usable Size | Raw (2-way) | Contents |
|--------|-------------|-------------|----------|
| `SOFS-Vol-01` | ~4.2 TB | ~8.4 TB | iic-sofs-01 OS + 4×1 TB data |
| `SOFS-Vol-02` | ~4.2 TB | ~8.4 TB | iic-sofs-02 OS + 4×1 TB data |
| `SOFS-Vol-03` | ~4.2 TB | ~8.4 TB | iic-sofs-03 OS + 4×1 TB data |
| **Total** | **~12.5 TB** | **~25 TB** | |

**Why this is the right design:** If one Azure Local volume goes offline, only the SOFS VM on that volume is affected. The guest S2D cluster still has two healthy nodes — the two-way mirror continues serving profiles with zero interruption to AVD sessions. This eliminates a shared-fate dependency that would make anti-affinity rules and the entire guest cluster pointless.

### Alternative: Single Volume (Simpler, Less Resilient)

One large volume holds all three VMs:

| Volume | Usable Size | Raw (2-way) | Contents |
|--------|-------------|-------------|----------|
| `SOFS-Storage` | ~12.5 TB | ~25 TB | All 3 VMs (OS + data) |

**Use only** if the Azure Local cluster cannot accommodate three separate volumes (e.g., limited number of drives) or if simplicity outweighs the fault isolation benefit. Understand that a volume-level issue takes out the entire guest cluster.

> **Recommendation:** This guide uses **three separate volumes** throughout. The single-volume alternative is noted where steps differ.

> **Do not thin-provision the host volumes.** `New-Volume` uses fixed provisioning by default — leave it that way. Thin provisioning lets you over-commit the Azure Local storage pool by allocating more logical capacity than physical space exists, but for SOFS host volumes this creates more problems than it solves:
>
> - **Pool full = all volumes die.** If total writes exceed the physical pool capacity, S2D puts the pool into a degraded/read-only state. That's not one volume full — it's every SOFS VM going read-only simultaneously.
> - **Defeats fault isolation.** Three volumes on a shared thin pool are back to a shared-fate dependency on pool free space — exactly what separate volumes are designed to eliminate.
> - **Write-time allocation overhead.** Every write must find and allocate slabs from the pool. During a logon storm, that's an extra metadata operation per write. Fixed provisioning has pre-allocated extents — writes go straight to reserved space.
> - **Misleading capacity reporting.** Volumes report large free space while the underlying pool may be nearly full. Admin tools, PerfMon, and FSRM all show the logical number, not the physical reality.
>
> Fixed provisioning: pre-calculate sizes from the [Storage Capacity Design](#storage-capacity-design), allocate up front, monitor each volume independently. The `New-Volume` commands in [Phase 1.1](#11-create-the-azure-local-two-way-mirror-volumes) use fixed provisioning intentionally.

---

## Storage Capacity Design

The customer requires **5 TB of usable FSLogix profile storage** with 10% growth headroom. Because resiliency is applied at two layers (guest S2D mirror inside the VMs, and the Azure Local two-way mirror underneath), the raw capacity requirement stacks multiplicatively.

### This Design: Guest Two-Way Mirror (Recommended)

| Layer | Calculation | Result |
|-------|-------------|--------|
| Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| Guest S2D two-way mirror | 5.5 TB × 2 copies | **11 TB** raw needed in S2D pool |
| Per-VM data disks | 4 × 1 TB per VM × 3 VMs = 12 TB pool | **1 TB each** (12 disks total, 11 TB used + overhead) |
| Azure Local volumes (usable) | 3 × ~4.2 TB (one per VM: OS + data) | **~12.5 TB total** |
| Azure Local two-way mirror (raw) | 12.5 TB × 2 copies | **~25 TB physical disk consumed** |

### For Comparison: Guest Three-Way Mirror

If maximum resiliency is required (survive 2 simultaneous guest-level failures), the numbers look like this:

| Layer | Calculation | Result |
|-------|-------------|--------|
| Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| Guest S2D three-way mirror | 5.5 TB × 3 copies | **16.5 TB** raw needed in S2D pool |
| Per-VM data disks | 4 × 1.4 TB per VM × 3 VMs = 16.8 TB pool | **1.4 TB each** (12 disks total) |
| Azure Local volumes (usable) | 3 × ~5.7 TB (one per VM) | **~17 TB total** |
| Azure Local two-way mirror (raw) | 17 TB × 2 copies | **~34 TB physical disk consumed** |

| | Two-Way Mirror | Three-Way Mirror |
|---|---|---|
| **Usable profile space** | 5.5 TB | 5.5 TB |
| **Data disk per VM** | 4 × 1 TB | 4 × 1.4 TB |
| **Azure Local volumes (total)** | ~12.5 TB (3 × ~4.2 TB) | ~17 TB (3 × ~5.7 TB) |
| **Raw physical consumed** | **~25 TB** | **~34 TB** |
| **Raw-to-usable ratio** | **~4.5 : 1** | **~6.2 : 1** |
| **Guest-level fault tolerance** | 1 failure | 2 failures |

> **Recommendation:** The two-way mirror design is used throughout this document. The Azure Local two-way mirror underneath already protects against physical disk and host node failures, making the additional three-way mirror at the guest layer hard to justify for an extra ~9 TB of raw capacity — especially for profile data that can be repopulated.

---

## Guest Volume Layout: Single vs. Three FSLogix Shares

Separately from the host-layer volume layout, decide how to carve the 5.5 TB of usable S2D space inside the guest cluster into FSLogix volumes and shares. Both options use the same hardware, the same S2D pool, and the same total capacity.

### Option A — Single Volume (Simple)

One guest S2D volume holds all FSLogix data:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `FSLogixData` | 5,632 GB (5.5 TB) | `Profiles` | Profile containers, ODFC containers, AppData |

**When to use Option A:**

- Under ~500 users with low-density session hosts (under ~30 users per VM)
- Simpler to deploy — one volume, one share, one FSLogix GPO path
- All free space is shared — no risk of one workload filling "its" volume while another has headroom
- Fewer monitoring targets and backup jobs

### Option B — Three Volumes (Granular)

Separate guest S2D volumes for each FSLogix workload:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `Profiles` | 3,072 GB (3 TB) | `Profiles` | Profile containers (user data, settings) |
| `ODFC` | 1,536 GB (1.5 TB) | `ODFC` | Office Data File Containers (Outlook OST, Teams cache) |
| `AppData` | 1,024 GB (1 TB) | `AppData` | Per-user AppData redirections |
| **Total** | **5,632 GB (5.5 TB)** | | |

**When to use Option B:**

- 500+ users or high-density session hosts (50+ users per VM)
- Environments where Outlook/Teams cache churn is a known problem

**Why Option B matters at scale:**

- **NTFS metadata isolation** — Each volume has its own MFT and change journal. Outlook OST writes hammering the ODFC change journal don't compete with profile writes for NTFS lock time on the Profiles volume.
- **Logon storm resilience** — Heavy AppData syncs (Chrome profiles, specialized apps) only slow the AppData volume. The Profiles volume stays responsive — Start Menu and Desktop load fast for everyone else.
- **FSRM quotas** — Per-volume File Server Resource Manager quotas let you hard-cap ODFC so one user's 50 GB Outlook cache can't eat into profile space. Impossible with a single volume.
- **Monitoring granularity** — Separate PerfMon counters per volume. "ODFC at 85%" is actionable. "FSLogixData at 60%" tells you nothing about what's growing.
- **Future migration path** — If you move to Azure NetApp Files or tiered storage later, pre-separated data maps cleanly to different tiers (fast tier for Profiles, cheaper tier for ODFC/AppData).

> **Recommendation:**
>
> | Environment | Choice |
> |---|---|
> | Under 500 users, low-density hosts | **Option A** |
> | 500+ users or 50+ users per session host | **Option B** |
> | When in doubt | **Option B** — the operational overhead is minimal (three shares instead of one) and the isolation benefits are significant |

This guide shows both options side-by-side where the guest-level steps differ.

---

# Part II — Implementation

## Prerequisites

### Infrastructure

- Azure Local cluster (`iic-clus01`) with **at least 3 physical nodes** (`iic-01-n01`, `iic-01-n02`, `iic-01-n03`)
- **~25 TB of available raw physical capacity** on the Azure Local cluster for the SOFS storage volume (this is for a two-way mirror at the host layer — see note below)
- **Windows Server 2025 Datacenter: Azure Edition Core (Gen2)** gallery image registered on the Azure Local cluster (marketplace SKU: `2025-datacenter-azure-edition-core`)

> **Raw capacity by host-layer resiliency:**
>
> | Host Mirror | Azure Local Volume (Usable) | Raw Physical Required |
> |-------------|----------------------------|-----------------------|
> | Two-way     | ~12.5 TB                   | **~25 TB**            |
> | Three-way   | ~12.5 TB                   | **~37.5 TB**          |
>
> This guide uses two-way mirror at the host layer. If your cluster requires three-way mirror (e.g., policy or fewer fault domains), adjust the raw capacity prerequisite to ~37.5 TB.

### Licensing

- **Windows Server 2025 Datacenter: Azure Edition Core (Gen2)** is required for Storage Spaces Direct (S2D). Each of the 3 SOFS VMs must be licensed for Datacenter.
- If your Azure Local hosts are licensed with **Windows Server Datacenter with Software Assurance** or you have an active **Azure Local subscription** that includes Windows Server guest licensing, your guest VM rights may already cover the SOFS VMs. Check with your Microsoft licensing contact — this is **not always included** and depends on how the Azure Local cluster was purchased and licensed.
- Without existing guest rights, you will need 3 additional Windows Server 2025 Datacenter licenses (or a volume licensing agreement that covers them).

### Active Directory and DNS

- Active Directory domain environment (`improbability.cloud`)
- DNS configured for the domain
- A **domain account with permissions to:**
  - Create Computer Objects in the target OU (required for the failover cluster CNO and the SOFS access point)
  - Join computers to the domain
  - Register DNS records (or pre-stage the DNS entries manually)
  - Create and manage SMB shares on the cluster
- Pre-stage the cluster CNO (`iic-sofs`) and SOFS access point (`iic-fslogix`) Computer Objects in AD if your environment restricts dynamic Computer Object creation — otherwise the account above must have `Create Computer Objects` permission on the target OU

### Tooling

- **Host volume creation** (Phase 1.1): PowerShell run directly on an **Azure Local cluster node** (or via remote PowerShell to the cluster). The `New-Volume` cmdlet is a Storage Spaces Direct operation — it does not go through Azure.
- **Azure resource provisioning** (Phases 1.2–3): Azure CLI (`az`) run from a **PowerShell** session. Install the Azure CLI and the `stack-hci-vm` extension. All commands in this guide use PowerShell variable syntax (`$variable`) and PowerShell line continuation (backtick `` ` ``), not bash.
- **Guest OS configuration** (Phases 4–11): Standard PowerShell remoting (`Enter-PSSession` / `Invoke-Command`) against the SOFS VMs from a management workstation with RSAT installed.

**Install from a management workstation (winget):**

```powershell
# Azure CLI
winget install --id Microsoft.AzureCLI --source winget

# Azure PowerShell (Az module)
winget install --id Microsoft.AzurePowerShell --source winget
```

After installing the Azure CLI, add the `stack-hci-vm` extension:

```powershell
az extension add --name stack-hci-vm --upgrade
```

> **RSAT** (Remote Server Administration Tools) is required for `Enter-PSSession`, `Invoke-Command`, and failover cluster management. Install it via Settings → Apps → Optional Features → Add a feature → search "RSAT", or:
>
> ```powershell
> Get-WindowsCapability -Name RSAT* -Online |
>     Where-Object { $_.State -ne 'Installed' } |
>     Add-WindowsCapability -Online
> ```

---

## Phase 1: Prepare the Azure Local Host Environment

### 1.1 — Create the Azure Local Two-Way Mirror Volumes

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Cluster Node](https://img.shields.io/badge/run_on-Cluster_Node-2d7d2d)

Run this on an **Azure Local cluster node** (any node in the host cluster).

Create three separate two-way mirror CSV volumes on the Azure Local cluster — one per SOFS VM. Each volume needs ~4.2 TB usable to hold one VM’s OS and data disks at full provisioned capacity.

```powershell
# ── Create three dedicated SOFS storage volumes on Azure Local ──
# One per SOFS VM for fault isolation
# Two-way mirror: ~4.2 TB usable each ≈ ~8.4 TB raw each ≈ ~25 TB total raw
$volumeNames = @("SOFS-Vol-01", "SOFS-Vol-02", "SOFS-Vol-03")

foreach ($volName in $volumeNames) {
    New-Volume -FriendlyName $volName `
               -StoragePoolFriendlyName "S2D on iic-clus01" `
               -FileSystem CSVFS_ReFS `
               -ResiliencySettingName Mirror `
               -NumberOfDataCopies 2 `
               -Size 4300GB
}
```

> **`-NumberOfDataCopies 2` is required.** On a 3-node Azure Local cluster, `-ResiliencySettingName Mirror` defaults to a three-way mirror. Without `-NumberOfDataCopies 2`, each volume would consume ~12.6 TB raw instead of ~8.4 TB — tripling your total raw footprint.

> **Why three volumes instead of one?** Each SOFS VM lives on its own CSV volume. If a single volume has an issue, only one SOFS node goes down — the guest S2D two-way mirror continues serving profiles from the remaining two nodes. A single shared volume would make anti-affinity rules meaningless because all three VMs would share the same storage fate.

Verify the volumes were created and are healthy:

```powershell
Get-VirtualDisk -CimSession "iic-clus01" |
    Where-Object { $_.FriendlyName -like "SOFS-Vol-*" } |
    Select-Object FriendlyName, ResiliencySettingName, NumberOfDataCopies, Size, HealthStatus

Get-ClusterSharedVolume -Cluster "iic-clus01" |
    Where-Object { $_.SharedVolumeInfo.FriendlyVolumeName -match "SOFS-Vol" } |
    Select-Object Name, State
```

The volumes will mount as CSVs — note the paths (e.g., `C:\ClusterStorage\SOFS-Vol-01`, `SOFS-Vol-02`, `SOFS-Vol-03`). Each SOFS VM and its data disks will be created on its dedicated volume.

### 1.2 — Create Storage Paths in Azure

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

Azure Local Arc VMs require **storage paths** — Azure resources that map to CSV paths on the cluster. Each SOFS volume needs a corresponding storage path so VMs and data disks can be placed on the correct volume.

> Storage paths can also be created in the **Azure Portal** under your Azure Local resource → **Storage paths** → **+ Create storage path**. See [Create storage path for Azure Local](https://learn.microsoft.com/azure/azure-local/manage/create-storage-path) for the portal walkthrough.

Using the Azure CLI from a **PowerShell** session:

```powershell
# ── Create storage paths — one per SOFS CSV volume ──
$subscription     = "<Your Subscription ID>"
$resourceGroup    = "rg-iic-sofs-azl-eus-01"
$location         = "eastus"
$customLocationID = "<Your Custom Location Resource ID>"

$storagePathNames = @(
    @{ Name = "sp-iic-sofs-vol-01"; Path = "C:\ClusterStorage\SOFS-Vol-01" },
    @{ Name = "sp-iic-sofs-vol-02"; Path = "C:\ClusterStorage\SOFS-Vol-02" },
    @{ Name = "sp-iic-sofs-vol-03"; Path = "C:\ClusterStorage\SOFS-Vol-03" }
)

foreach ($storagePath in $storagePathNames) {
    az stack-hci-vm storagepath create `
        --resource-group $resourceGroup `
        --custom-location $customLocationID `
        --location $location `
        --name $storagePath.Name `
        --path $storagePath.Path
}
```

After creation, capture the resource IDs — you'll need them when creating VMs and data disks in later phases:

```powershell
# Build the $storagePathIds hashtable from the newly created storage paths
$storagePathNames = @("sp-iic-sofs-vol-01", "sp-iic-sofs-vol-02", "sp-iic-sofs-vol-03")
$storagePathIds   = @{}

foreach ($spName in $storagePathNames) {
    # Extract the suffix ("01", "02", "03") from the name for the hashtable key
    $nodeId = $spName.Substring($spName.Length - 2)
    $storagePathIds[$nodeId] = az stack-hci-vm storagepath show `
        --resource-group $resourceGroup `
        --name $spName `
        --query id -o tsv
}

# Verify
$storagePathIds | Format-Table -AutoSize
```

### 1.3 — Verify Logical Network and Prerequisites

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

Before creating Azure Local VMs, ensure the following are in place. All `az` commands below are run from a **PowerShell** session:

```powershell
# Verify your Azure CLI has the stack-hci-vm extension
az extension add --name stack-hci-vm --upgrade

# Set common variables (PowerShell syntax)
$subscription     = "<Your Subscription ID>"
$resourceGroup    = "rg-iic-sofs-azl-eus-01"
$location         = "eastus"
$customLocationID = "<Your Custom Location Resource ID>"
$imageName        = "img-iic-ws2025-dc-aze-core-g2-v1"
$logicalNetworkId = "<Your Compute Logical Network Resource ID>"

# Storage path IDs — created in Phase 1.2
# If you still have the $storagePathIds hashtable from that step, reuse it.
# Otherwise, rebuild it:
$storagePathNames = @("sp-iic-sofs-vol-01", "sp-iic-sofs-vol-02", "sp-iic-sofs-vol-03")
$storagePathIds   = @{}

foreach ($spName in $storagePathNames) {
    $nodeId = $spName.Substring($spName.Length - 2)
    $storagePathIds[$nodeId] = az stack-hci-vm storagepath show `
        --resource-group $resourceGroup `
        --name $spName `
        --query id -o tsv
}
```

You need a **Windows Server 2025 Datacenter: Azure Edition Core (Gen2)** image (SKU: `2025-datacenter-azure-edition-core`) already registered as a gallery image on your Azure Local cluster, and a logical network configured for the compute network.

---

## Phase 2: Create the 3 SOFS Node VMs

### 2.1 — Create Network Interfaces

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

Create a NIC for each SOFS VM on the compute logical network:

```powershell
# Create NICs on the compute logical network
$nodeIds = @("01", "02", "03")

foreach ($nodeId in $nodeIds) {
    az stack-hci-vm network nic create `
        --resource-group $resourceGroup `
        --custom-location $customLocationID `
        --location $location `
        --name "iic-sofs-$nodeId-nic" `
        --subnet-id $logicalNetworkId
}
```

### 2.2 — Create the VMs

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

Each VM is created on its dedicated storage volume:

```powershell
# Create the 3 SOFS VMs — each on its own storage path / CSV volume
$nodeIds = @("01", "02", "03")

foreach ($nodeId in $nodeIds) {
    az stack-hci-vm create `
        --name "iic-sofs-$nodeId" `
        --resource-group $resourceGroup `
        --custom-location $customLocationID `
        --location $location `
        --image $imageName `
        --admin-username "sofs_admin" `
        --admin-password "<YourSecurePassword>" `
        --computer-name "iic-sofs-$nodeId" `
        --hardware-profile memory-mb="8192" processors="4" `
        --nics "iic-sofs-$nodeId-nic" `
        --storage-path-id $storagePathIds[$nodeId] `
        --authentication-type all `
        --enable-agent true
}
```

### 2.3 — Create and Attach Data Disks

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

Each VM needs 4 × 1 TB data disks for the S2D storage pool. Create the disks on each VM’s dedicated storage path and attach them:

```powershell
# Create 4 data disks per VM (12 disks total) — each on the VM's own storage path
$nodeIds   = @("01", "02", "03")
$diskNumbers = @(1, 2, 3, 4)

foreach ($nodeId in $nodeIds) {
    foreach ($diskNumber in $diskNumbers) {
        az stack-hci-vm disk create `
            --resource-group $resourceGroup `
            --custom-location $customLocationID `
            --location $location `
            --name "iic-sofs-$nodeId-data$diskNumber" `
            --size-gb 1024 `
            --dynamic true `
            --storage-path-id $storagePathIds[$nodeId]
    }
}

# Attach the data disks to each VM
foreach ($nodeId in $nodeIds) {
    az stack-hci-vm disk attach `
        --resource-group $resourceGroup `
        --vm-name "iic-sofs-$nodeId" `
        --disks "iic-sofs-$nodeId-data1" "iic-sofs-$nodeId-data2" "iic-sofs-$nodeId-data3" "iic-sofs-$nodeId-data4" `
        --yes
}
```

### 2.4 — Verify VMs and Disks

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI and the `stack-hci-vm` extension installed.

```powershell
# List VMs
az stack-hci-vm list --resource-group $resourceGroup -o table

# Verify data disks on each VM
$nodeIds = @("01", "02", "03")

foreach ($nodeId in $nodeIds) {
    Write-Host "=== iic-sofs-$nodeId ==="
    az stack-hci-vm show `
        --resource-group $resourceGroup `
        --name "iic-sofs-$nodeId" `
        --query "{name:name, dataDisks:properties.storageProfile.dataDisks}"
}
```

### 2.5 — Verify VM Placement

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Cluster Node](https://img.shields.io/badge/run_on-Cluster_Node-2d7d2d)

Run this on an **Azure Local cluster node**.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Cluster Node](https://img.shields.io/badge/run_on-Cluster_Node-2d7d2d)

Run this on an **Azure Local cluster node** (or a management machine with RSAT Failover Clustering tools installed).

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Cluster Node](https://img.shields.io/badge/run_on-Cluster_Node-2d7d2d)

Run this on an **Azure Local cluster node** (or a management machine with RSAT Failover Clustering tools installed).

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

The OS is already deployed as part of the Azure Local VM creation in Phase 2 (via the gallery image). The VMs must be domain-joined before proceeding to Phase 5.

### 4.1 — Domain Join the SOFS VMs

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM** (via RDP, Azure Arc remote access, or `Invoke-Command`) using the domain account specified in the Prerequisites:

```powershell
# Run on each SOFS VM — replace with your domain and OU path
$domain = "improbability.cloud"
$ouPath = "OU=Servers,OU=SOFS,DC=improbability,DC=cloud"
$credential = Get-Credential -Message "Enter domain join credentials"

Add-Computer -DomainName $domain `
             -OUPath $ouPath `
             -Credential $credential `
             -Restart -Force
```

> **Tip:** If you prefer to script this across all three VMs from a management workstation:
>
> ```powershell
> $cred = Get-Credential -Message "Domain join credentials"
> $nodes = "iic-sofs-01","iic-sofs-02","iic-sofs-03"
> foreach ($node in $nodes) {
>     Invoke-Command -ComputerName $node -ScriptBlock {
>         Add-Computer -DomainName "improbability.cloud" `
>                      -OUPath "OU=Servers,OU=SOFS,DC=improbability,DC=cloud" `
>                      -Credential $using:cred `
>                      -Restart -Force
>     }
> }
> ```

### 4.2 — Verify Domain Join and Network Configuration

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM**.

After reboot, connect to each SOFS VM and verify:

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

### 4.3 — IP Address Reference

| VM Name       | IP Address   | Role      |
|---------------|--------------|-----------|
| iic-sofs-01   | 10.42.10.21  | S2D Node  |
| iic-sofs-02   | 10.42.10.22  | S2D Node  |
| iic-sofs-03   | 10.42.10.23  | S2D Node  |

> **Note:** If the VMs were deployed with DHCP, assign static IPs or DHCP reservations before proceeding with cluster creation. All SOFS nodes must have stable, predictable IP addresses.

---

## Phase 5: Install Required Roles and Features

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **all three SOFS VMs**:

```powershell
# Install Failover Clustering, File Server, and S2D management tools
Install-WindowsFeature -Name Failover-Clustering,
                              FS-FileServer,
                              RSAT-Clustering-PowerShell,
                              RSAT-Clustering-Mgmt `
                       -IncludeManagementTools -Restart
```

### 5.1 — Firewall Considerations

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM** to verify firewall rules.

> **Scope:** The firewall rules discussed here apply **between the SOFS guest VMs** and **between the SOFS VMs and AVD session hosts** on the same compute network/VLAN. These are internal (east-west) rules. External/perimeter firewall rules for Azure Arc and Azure Local connectivity are a separate topic — refer to your Azure Local networking documentation.

Windows Firewall rules for Failover Clustering, S2D, and SMB are automatically created when the `Failover-Clustering` and `FS-FileServer` features are installed. Verify they are enabled:

```powershell
# Verify clustering firewall rules are enabled
Get-NetFirewallRule -Group "Failover Clusters" | Select-Object DisplayName, Enabled, Direction

# Verify SMB firewall rules (TCP 445) are enabled
Get-NetFirewallRule -Group "File and Printer Sharing" |
    Where-Object { $_.DisplayName -like "*SMB*" } |
    Select-Object DisplayName, Enabled, Direction
```

If your environment uses a hardened base image with Windows Firewall rules stripped, you will need the following ports open **between the three SOFS VMs**:

| Port | Protocol | Purpose |
|------|----------|---------|
| 445 | TCP | SMB (S2D replication, CSV redirected I/O, client access) |
| 5445 | TCP | SMB over QUIC (if used) |
| 5985–5986 | TCP | WinRM / PowerShell Remoting |
| 135 | TCP | RPC Endpoint Mapper (cluster communication) |
| 49152–65535 | TCP | RPC dynamic ports (cluster, S2D) |
| 3343 | UDP | Cluster network driver |

Additionally, **between SOFS VMs and AVD session hosts**:

| Port | Protocol | Purpose |
|------|----------|---------|
| 445 | TCP | SMB (FSLogix profile access via `\\iic-fslogix\Profiles`) |

---

## Phase 6: Validate and Create the Guest Failover Cluster

### 6.1 — Validate the Cluster

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs** (or a management machine with RSAT Failover Clustering tools installed).

```powershell
Test-Cluster -Node "iic-sofs-01","iic-sofs-02","iic-sofs-03" -Include "Inventory","Network","System Configuration"
```

> **Tip:** Skip the "Storage" tests since we're using S2D inside VMs, not shared SAS/FC storage. Review the validation report for any warnings.

### 6.2 — Create the Failover Cluster

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

```powershell
New-Cluster -Name "iic-sofs" `
            -Node "iic-sofs-01","iic-sofs-02","iic-sofs-03" `
            -StaticAddress "10.42.10.25" `
            -NoStorage
```

- **`-Name`**: The cluster CNO (Computer Name Object) — will be created in AD
- **`-StaticAddress`**: A free IP on the compute network for the cluster itself
- **`-NoStorage`**: Skips automatic storage enumeration (S2D will handle this)

### 6.3 — Create the Cloud Witness Storage Account

![Azure CLI](https://img.shields.io/badge/-Azure%20CLI-0078D4?logo=microsoftazure&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with Azure CLI installed.

The cloud witness needs an Azure Storage Account. Create one if it doesn’t already exist:

```powershell
# Create a storage account for the cloud witness (LRS is sufficient — the witness is tiny)
az storage account create `
    --name "stsofswitnessiic01" `
    --resource-group $resourceGroup `
    --location $location `
    --sku Standard_LRS `
    --kind StorageV2 `
    --min-tls-version TLS1_2 `
    --allow-blob-public-access false

# Retrieve the access key
$witnessKey = (az storage account keys list `
    --account-name "stsofswitnessiic01" `
    --resource-group $resourceGroup `
    --query "[0].value" -o tsv)
```

### 6.4 — Configure the Cloud Witness

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

An Azure Storage Account cloud witness is the recommended quorum model for a 3-node cluster:

```powershell
Set-ClusterQuorum -Cluster "iic-sofs" `
                  -CloudWitness `
                  -AccountName "stsofswitnessiic01" `
                  -AccessKey $witnessKey `
                  -Endpoint "core.windows.net"
```

> Alternatively, use a file share witness on an independent server (not one of the SOFS nodes). If you created the storage account outside this guide, replace `$witnessKey` with the actual key string.

---

## Phase 7: Enable Storage Spaces Direct (S2D)

### 7.1 — Clean the Data Disks

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM**.

On each SOFS VM, ensure the data disks are raw/uninitialized:

```powershell
# Run on each SOFS node — clears all non-OS disks
Get-Disk | Where-Object { $_.Number -ne 0 -and $_.IsBoot -eq $false } |
    Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
```

### 7.2 — Enable S2D

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

```powershell
Enable-ClusterStorageSpacesDirect -Cluster "iic-sofs" -Confirm:$false
```

> **Important for nested/guest S2D:** Since these are VMs, S2D treats all disks as capacity (flat — no caching tier). This is expected and correct.

### 7.3 — Apply Guest S2D Tuning (Registry)

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM**.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

```powershell
Add-ClusterScaleOutFileServerRole -Name "iic-fslogix" -Cluster "iic-sofs"
```

- **`-Name`**: This is the **client access point** — the NetBIOS/DNS name clients will connect to (e.g., `\\iic-fslogix\Profiles`). It creates a Computer Object in AD and a DNS A record.

> **AD and DNS permissions required:** The cluster CNO (`iic-sofs$`) must have permission to create a Computer Object for the SOFS access point (`iic-fslogix`) in the target OU. If your AD environment restricts this, pre-stage the `iic-fslogix` Computer Object and grant the `iic-sofs$` CNO full control over it. The command also registers a DNS A record — if dynamic DNS updates are restricted, create the A record manually before running this command.

Verify:

```powershell
Get-ClusterGroup -Cluster "iic-sofs" | Where-Object { $_.GroupType -eq "ScaleOutFileServer" }
```

### 8.2 — Create the FSLogix SMB Share(s)

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this from **any one of the SOFS VMs**.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: SOFS VM](https://img.shields.io/badge/run_on-SOFS_VM-8b5cf6)

Run this on **each SOFS VM**.

On each of the three SOFS VMs, configure Microsoft Defender (or your AV product) to exclude the S2D storage paths and VHDX files. For **Microsoft Defender**, run on each SOFS VM:

```powershell
# Exclude CSV volume paths (all ClusterStorage)
Add-MpPreference -ExclusionPath "C:\ClusterStorage"

# Exclude VHD/VHDX file extensions
Add-MpPreference -ExclusionExtension ".VHD"
Add-MpPreference -ExclusionExtension ".VHDX"

# Exclude cluster-related processes
Add-MpPreference -ExclusionProcess "clussvc.exe"
Add-MpPreference -ExclusionProcess "csvfs.sys"

# Verify exclusions
Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess
```

> If you are using a third-party AV product, configure equivalent exclusions through that product’s management console.

### 10.2 — Antivirus Exclusions on AVD Session Hosts (When Deployed)

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Session Host](https://img.shields.io/badge/run_on-Session_Host-e67e22)

Run this on **each AVD session host**.

When you deploy your AVD session hosts, FSLogix profile corruption is commonly caused by antivirus scanning. For **Microsoft Defender**, run on each session host:

```powershell
# FSLogix processes
Add-MpPreference -ExclusionProcess "frxsvc.exe"
Add-MpPreference -ExclusionProcess "frxdrv.sys"
Add-MpPreference -ExclusionProcess "frxccd.sys"

# FSLogix application path
Add-MpPreference -ExclusionPath "$env:ProgramFiles\FSLogix\Apps"

# VHDX mount points
Add-MpPreference -ExclusionPath "$env:TEMP\intlMountPoints"

# VHD/VHDX file extensions
Add-MpPreference -ExclusionExtension ".VHD"
Add-MpPreference -ExclusionExtension ".VHDX"
```

---

## Phase 11: Validation and Testing

### 11.1 — Verify SOFS Access

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** (or any machine on the compute network with RSAT tools installed).

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** with RSAT Failover Clustering tools installed.

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

![PowerShell](https://img.shields.io/badge/-PowerShell-5391FE?logo=powershell&logoColor=white) ![Run on: Mgmt Workstation](https://img.shields.io/badge/run_on-Mgmt_Workstation-6c757d)

Run this from a **management workstation** (or any Azure Local cluster node).

```powershell
# Confirm all three SOFS VMs are on separate physical nodes
Get-ClusterGroup -Cluster "iic-clus01" |
    Where-Object { $_.Name -like "iic-sofs*" } |
    Select-Object Name, OwnerNode

# Verify the rule is active
Get-ClusterAffinityRule -Name "SOFS-AntiAffinity" -Cluster "iic-clus01"
```

---

# Part III — Reference

## Summary: IP and Name Reference

### Option A — Single Volume

| Component          | Name / IP                     | Purpose                              |
|--------------------|-------------------------------|--------------------------------------|
| Azure Local Volume 1 | SOFS-Vol-01 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-01 disks (~8.4 TB raw) |
| Azure Local Volume 2 | SOFS-Vol-02 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-02 disks (~8.4 TB raw) |
| Azure Local Volume 3 | SOFS-Vol-03 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-03 disks (~8.4 TB raw) |
| SOFS VM 1          | iic-sofs-01 / 10.42.10.21    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 2          | iic-sofs-02 / 10.42.10.22    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 3          | iic-sofs-03 / 10.42.10.23    | S2D node (127 GB OS + 4×1 TB data)   |
| Guest Cluster CNO  | iic-sofs / 10.42.10.25       | Failover cluster name                |
| SOFS Access Point  | iic-fslogix                   | Client access (`\\iic-fslogix\Profiles`) |
| Guest S2D Volume   | FSLogixData (5.5 TB, 2-way mirror) | Usable profile storage          |
| Cloud Witness      | stsofswitnessiic01            | Azure Storage Account quorum witness |
| Anti-Affinity Rule | SOFS-AntiAffinity             | Keeps VMs on separate Azure Local nodes |

### Option B — Three Volumes

| Component          | Name / IP                     | Purpose                              |
|--------------------|-------------------------------|--------------------------------------|
| Azure Local Volume 1 | SOFS-Vol-01 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-01 disks (~8.4 TB raw) |
| Azure Local Volume 2 | SOFS-Vol-02 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-02 disks (~8.4 TB raw) |
| Azure Local Volume 3 | SOFS-Vol-03 (~4.2 TB, 2-way mirror) | Hosts iic-sofs-03 disks (~8.4 TB raw) |
| SOFS VM 1          | iic-sofs-01 / 10.42.10.21    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 2          | iic-sofs-02 / 10.42.10.22    | S2D node (127 GB OS + 4×1 TB data)   |
| SOFS VM 3          | iic-sofs-03 / 10.42.10.23    | S2D node (127 GB OS + 4×1 TB data)   |
| Guest Cluster CNO  | iic-sofs / 10.42.10.25       | Failover cluster name                |
| SOFS Access Point  | iic-fslogix                   | Client access (`\\iic-fslogix\<share>`) |
| Profiles Volume    | Profiles (3 TB, 2-way mirror) | Profile containers                  |
| ODFC Volume        | ODFC (1.5 TB, 2-way mirror)   | Office Data File Containers         |
| AppData Volume     | AppData (1 TB, 2-way mirror)  | Per-user AppData redirections       |
| Cloud Witness      | stsofswitnessiic01            | Azure Storage Account quorum witness |
| Anti-Affinity Rule | SOFS-AntiAffinity             | Keeps VMs on separate Azure Local nodes |

---

## Important Notes and Considerations

**Licensing:** See the [Prerequisites — Licensing](#licensing) section above. Windows Server 2025 Datacenter: Azure Edition Core (Gen2) is required for S2D, and guest VM licensing is not always included with Azure Local.

**Supportability:** Microsoft's official guidance is that S2D in guest VMs is supported on Windows Server (not Azure Local OS as the guest). Since you're running Windows Server 2025 Datacenter: Azure Edition Core (Gen2) *inside* the VMs on an Azure Local host, this is a supported configuration. Do not mix the Azure Local cluster's own S2D storage volumes with SOFS shares on the same cluster — the guest cluster approach keeps these cleanly separated.

**Network:** All SOFS VMs should be on the same compute network/VLAN as the AVD session hosts for optimal latency. If you have a dedicated storage VLAN, you could add a second NIC to each SOFS VM for intra-cluster (S2D replication) traffic, but for most deployments a single compute network NIC is sufficient.

**Capacity planning:** This design provisions 5.5 TB usable (5 TB + 10% growth) for FSLogix profiles. The guest S2D two-way mirror consumes 11 TB of the 12 TB pool (4 × 1 TB data disks × 3 VMs), spread across three Azure Local CSV volumes (~4.2 TB usable each, ~8.4 TB raw each), requiring **~25 TB of raw physical capacity** on the cluster. Data disks are dynamically provisioned so they won't consume the full allocation from day one — only as profiles are written. Monitor utilization and expand the Azure Local volumes and VM data disks if growth exceeds the 10% buffer.

**Backup and DR with FSLogix Cloud Cache:** SOFS with continuously available shares requires special backup considerations. Standard VSS-based backup tools may not work directly against the SOFS share. **FSLogix Cloud Cache works with Azure Local** — Cloud Cache operates against any SMB share, and the SOFS share is SMB. You can configure Cloud Cache on your AVD session hosts with the SOFS as the primary storage provider and an Azure Blob Storage account or Azure Files share as a secondary provider. This gives you:

- Active replication of profile data to Azure for DR without separate backup infrastructure
- User session continuity if the SOFS becomes temporarily unavailable (Cloud Cache serves from local cache)
- Up to 4 storage providers (the practical limit) in any combination of SMB and Azure Blob
- Automatic resync when a provider comes back online after an outage

Cloud Cache writes to a local cache on the session host first, then asynchronously flushes to all providers. This means even if the SOFS goes down mid-session, the user continues working from the local cache. At sign-out, Cloud Cache ensures all providers are synchronized before completing. For environments without Cloud Cache, consider a backup agent inside the guest cluster that can back up the FSLogix VHDX files on a schedule during off-hours when profiles are not mounted.

---

## Considerations for AVD Deployment

> **This section is not part of the SOFS deployment itself.** These are items to plan for when you deploy your AVD session hosts that will consume the SOFS share(s).

### How FSLogix Maps Users to Shares

Users never see a mapped drive or UNC path — the **FSLogix agent** (`frxsvc.exe`) on each session host handles everything automatically via a kernel-mode filter driver:

1. You configure `VHDLocations` (see registry keys below) pointing to `\\iic-fslogix\Profiles`.
2. At user logon, the FSLogix filter driver intercepts the profile load, connects to the share using the user's **AD Kerberos identity**, and creates (or mounts) a per-user VHDX inside a folder named `<SID>_<Username>`.
3. The driver redirects `C:\Users\<Username>` into the mounted VHDX — completely transparent to the user and all applications.

The NTFS permissions set in Phase 9 are what make this work: `Domain Users` gets Modify on the share root (so the agent can create the SID folder on first login), and `CREATOR OWNER` gets Modify on subfolders (so each user can only access their own profile data).

### Identity Model: AD Domain Join Is Required

On Azure Local, AVD session hosts **must be AD domain-joined**. Pure Entra ID join is not supported for Azure Local Arc VMs — that option is only available for cloud-hosted Azure VMs.

This means the identity plumbing between session hosts and SOFS shares is straightforward:

| Component | Identity | Auth to SOFS |
|---|---|---|
| AVD session host | AD domain member (`improbability.cloud`) | Kerberos — native |
| User at logon | AD domain user | Kerberos TGS for `\\iic-fslogix` |
| SOFS cluster | AD domain member (`improbability.cloud`) | Kerberos — native |

Because both sides (session hosts and SOFS) are joined to the same AD domain, Kerberos authentication works automatically. No extra trust configuration is needed.

**Hybrid Entra ID Join** (domain-joined + registered in Entra ID) is also supported and recommended if you want SSO to the AVD gateway via Entra ID. It does not change the SOFS authentication path — the session hosts still use AD Kerberos for SMB access.

> **Plan your session host identity model before deploying the SOFS cluster.** The NTFS permissions (Phase 9) and SMB share permissions (Phase 8) reference AD domain groups (`IMPROBABLE\Domain Users`, `IMPROBABLE\Domain Admins`). If your AVD users are in a different domain or OU, adjust those group references accordingly.

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

The repository includes automation tooling for every phase of the SOFS deployment. All source code is in the [`azurelocal-sofs-fslogix`](https://github.com/AzureLocal/azurelocal-sofs-fslogix) repository.

### Central Configuration

A single YAML configuration file drives all deployment tools. It contains every parameter across all phases — Azure subscription, Azure Local infrastructure IDs, VM sizing, domain join credentials (resolved from Key Vault), guest cluster settings, S2D volume config, and tags.

| File | Description |
|------|-------------|
| [`config/variables.example.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/config/variables.example.yml) | Example configuration — copy to `config/variables.yml` and fill in your values. Key Vault URI references are used for secrets (`admin_password`, `domain_join_password`). |

### Pre-Deployment / Prerequisites

Utility scripts for preparing the Azure environment before the main deployment. These are standalone and optional.

| Tool | Path | Description |
|------|------|-------------|
| **Bash** | [`scripts/deploy-prerequisites.sh`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/scripts/deploy-prerequisites.sh) | Creates the Azure resource group and supporting resources. Requires `SUBSCRIPTION_ID`, `RESOURCE_GROUP`, and `LOCATION` environment variables. |
| **Bash** | [`scripts/configure-arc-extensions.sh`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/scripts/configure-arc-extensions.sh) | Enables Azure Monitor Agent and Microsoft Defender for Cloud extensions on the Azure Local physical cluster nodes. |

### Phase 1 — Azure Resource Provisioning

Creates the Azure-side resources: resource group, cloud witness storage account, Arc VM placeholders, NICs, VM instances, and data disks. Four tooling options — pick one.

| Tool | Path | Description |
|------|------|-------------|
| **Terraform** | [`src/terraform/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/src/terraform) | Full IaC using `azapi` + `azurerm` providers. Creates resource group, Key Vault, cloud witness storage, NICs (with optional static IPs), Arc VMs, and data disks. Auto-generates an Ansible inventory file for Phase 2 via [`ansible-inventory.tf`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/terraform/ansible-inventory.tf). Copy [`terraform.tfvars.example`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/terraform/terraform.tfvars.example) to `terraform.tfvars` and run `terraform apply`. |
| **Bicep** | [`src/bicep/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/src/bicep) | Subscription-scope Bicep deployment. Modules: [`main.bicep`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/bicep/main.bicep) (orchestrator), [`sofs-resources.bicep`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/bicep/sofs-resources.bicep) (VMs, NICs, disks), [`witness-storage.bicep`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/bicep/witness-storage.bicep) (cloud witness). Run via [`Deploy-SOFS-Azure.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/bicep/Deploy-SOFS-Azure.ps1) wrapper or `az deployment sub create`. Copy [`main.bicepparam.example`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/bicep/main.bicepparam.example) to `main.bicepparam`. |
| **ARM** | [`src/arm/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/src/arm) | Legacy ARM JSON templates ([`azuredeploy.json`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/arm/azuredeploy.json)). Same resources as Bicep. **Bicep is recommended for new deployments** — ARM templates are maintained for environments that require JSON. Copy [`azuredeploy.parameters.example.json`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/arm/azuredeploy.parameters.example.json) to `azuredeploy.parameters.json`. |
| **PowerShell** | [`src/powershell/Deploy-SOFS-Azure.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/Deploy-SOFS-Azure.ps1) | Azure CLI wrapper script — creates resource group, cloud witness storage, NICs with static IPs, VMs, and data disks. Reads from `config/variables.yml` or accepts individual parameters. Passwords resolved from Key Vault. Use when IaC is not required. |
| **Ansible** | [`src/ansible/playbooks/deploy-azure-resources.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/deploy-azure-resources.yml) | Runs on `localhost` using Azure CLI commands. Creates the same Azure resources as the other tools. Reads from inventory variables. |

### Phase 2 — Guest Cluster Configuration (Phases 3–11 of This Guide)

Configures the SOFS guest cluster inside the VMs: anti-affinity rules, Failover Clustering and File Server role install, cluster creation, cloud witness, S2D enable/tuning, volume creation, SOFS role, SMB shares, NTFS permissions, and validation. Two main options — pick one.

| Tool | Path | Phases | Description |
|------|------|--------|-------------|
| **PowerShell** | [`src/powershell/Configure-SOFS-Cluster.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/Configure-SOFS-Cluster.ps1) | 3–11 | Comprehensive WinRM/PSRemoting-based script run from a management workstation. Idempotent — safe to re-run. Reads from `config/variables.yml` or accepts individual parameters (`-GuestClusterName`, `-GuestClusterIP`, `-SOFSAccessPoint`, `-S2DVolumeSizeGB`, etc.). |
| **Ansible** | [`src/ansible/playbooks/configure-sofs-cluster.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/configure-sofs-cluster.yml) | 5–11 | WinRM+Kerberos playbook. Installs roles/features, creates cluster, configures cloud witness, enables S2D with guest tuning, creates mirror volume, adds SOFS role, creates SMB share, sets NTFS permissions, validates. Requires `pywinrm` and `ansible.windows` collection. Does **not** handle anti-affinity rules (Phases 3–4) — those run against the Azure Local host cluster, not the guest VMs. |

### Supplemental PowerShell Scripts

These are standalone scripts for specific sub-tasks. They overlap with `Configure-SOFS-Cluster.ps1` and are useful for targeted re-runs or environments where the full script isn't needed.

| Script | Path | Phases | Description |
|--------|------|--------|-------------|
| **New-SOFSDeployment.ps1** | [`src/powershell/New-SOFSDeployment.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/New-SOFSDeployment.ps1) | 8–9 | Enables the File Server cluster role, adds the SOFS role, creates the CSV directory, and creates the FSLogix SMB share. |
| **Set-FSLogixShare.ps1** | [`src/powershell/Set-FSLogixShare.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/powershell/Set-FSLogixShare.ps1) | 9–10 | Configures NTFS and SMB share permissions for AVD users, applies SMB settings optimized for FSLogix (oplocks, leasing), and optionally sets FSLogix registry keys locally for testing. |

### Supplemental Ansible Playbooks

| Playbook | Path | Description |
|----------|------|-------------|
| **configure-sofs.yml** | [`src/ansible/playbooks/configure-sofs.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/configure-sofs.yml) | Targets SOFS nodes. Creates SMB share directory, creates the share with CA + ABE + encryption, and sets permissions. Overlaps with Phase 9 of `configure-sofs-cluster.yml`. |
| **configure-fslogix.yml** | [`src/ansible/playbooks/configure-fslogix.yml`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/src/ansible/playbooks/configure-fslogix.yml) | Targets **AVD session hosts** (not SOFS nodes). Applies FSLogix registry settings — enables profile containers, sets `VHDLocations` to the SOFS share UNC path, configures FlipFlop naming, local profile cleanup, and container size. Use this after deploying your session hosts. |

### Post-Deployment Validation

| Tool | Path | Description |
|------|------|-------------|
| **PowerShell** | [`tests/Test-SOFSDeployment.ps1`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/blob/main/tests/Test-SOFSDeployment.ps1) | Validates the full SOFS deployment — checks SMB share reachability, verifies share settings (CA, encryption), confirms NTFS permissions for AVD users, and optionally tests FSLogix registry configuration. Run from any machine that can reach the SOFS share. |

### CI/CD Pipeline Examples

The [`examples/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples) directory contains starter pipeline definitions for automating the full deployment in your CI/CD platform of choice:

| Directory | Description |
|-----------|-------------|
| [`examples/pipelines/azure-devops/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples/pipelines/azure-devops) | Azure DevOps YAML pipeline definitions |
| [`examples/pipelines/github-actions/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples/pipelines/github-actions) | GitHub Actions workflow files |
| [`examples/pipelines/gitlab/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples/pipelines/gitlab) | GitLab CI/CD pipeline definitions |
| [`examples/configs/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples/configs) | Production and staging configuration examples |
| [`examples/secrets/`](https://github.com/AzureLocal/azurelocal-sofs-fslogix/tree/main/examples/secrets) | Guidance for managing secrets via Azure DevOps variable groups, GitHub Secrets, GitLab Variables, and Key Vault integration |

> **Terraform and Bicep handle only Phase 1** (Azure resource provisioning). Guest OS cluster configuration (Phases 3–11) requires the PowerShell script or Ansible playbook — infrastructure-as-code tools cannot configure Windows Failover Clustering or S2D inside the guest OS.

---

## Related Resources

| | |
|---|---|
| **Repository** | [AzureLocal/azurelocal-sofs-fslogix](https://github.com/AzureLocal/azurelocal-sofs-fslogix) |
| **AVD Repository** | [AzureLocal/azure_avd](https://github.com/AzureLocal/azure_avd) |
| **Website** | [azurelocal.cloud](https://azurelocal.cloud) |
| **Path** | `docs/reference/sofs-deployment-guide.md` |
| **Maintained by** | Hybrid Cloud Solutions LLC |
