# AVD Considerations

## Overview

This SOFS exists for one purpose: to serve FSLogix profile containers to Azure Virtual Desktop (AVD) session hosts running on Azure Local. Every design decision — from storage layout to NTFS permissions — traces back to how AVD and FSLogix interact with the SOFS.

This page covers the identity model, host pool types, session host density impact, how FSLogix maps users to shares, Cloud Cache for DR, profile sizing, and network placement. None of this is SOFS configuration — it's the context you need to make the right SOFS design choices.

---

## Identity Model: AD Domain Join Is Required

On Azure Local, AVD session hosts **must be Active Directory (AD) domain-joined**. Pure Entra ID join is not supported for Azure Local Arc VMs — that option is only available for cloud-hosted Azure VMs.

This makes the identity plumbing between session hosts and SOFS shares straightforward:

| Component | Identity | Authentication to SOFS |
|-----------|----------|------------------------|
| AVD session host | AD domain member | Kerberos — native |
| User at logon | AD domain user | Kerberos TGS for SOFS access point |
| SOFS cluster | AD domain member | Kerberos — native |

Because both sides (session hosts and SOFS) are joined to the same AD domain, Kerberos authentication works automatically. No extra trust configuration, no certificate mapping, no token exchange.

**Hybrid Entra ID Join** (domain-joined + registered in Entra ID) is also supported and recommended if you want SSO to the AVD gateway via Entra ID. It does not change the SOFS authentication path — session hosts still use AD Kerberos for SMB access to `\\iic-fslogix\Profiles`.

!!! important "Plan identity before building the SOFS"
    The NTFS permissions and SMB share permissions reference AD domain groups (`Domain Users`, `Domain Admins`). If your AVD users are in a different domain, OU, or security group, adjust those group references in the [Permissions](../configuration/permissions.md) configuration.

---

## Personal vs. Pooled Host Pools

How your AVD host pool is configured directly affects SOFS design choices.

### Personal Desktops

- Each user gets a **dedicated, persistent** session host VM
- Profiles persist locally — FSLogix is still used but mostly for roaming and backup
- Larger per-user VHDXs (users accumulate data over time)
- Fewer users per host (typically 1:1)
- **Low logon storm risk** — users log in throughout the day, not all at once
- Design impact: Option A (single share) is almost always sufficient

### Pooled Desktops

- Users share a pool of **non-persistent** session hosts
- FSLogix is **critical** — the profile VHDX is the only persistent user state
- Smaller per-user VHDXs but much higher I/O churn (profile load/unload on every session)
- Many users per host (20–50 per VM is typical)
- **High logon storm risk** — shift changes, morning starts, and maintenance windows create massive concurrent I/O
- Design impact: Option B (split shares) becomes important at scale to isolate NTFS metadata contention

### Impact on SOFS Design

| Factor | Personal | Pooled |
|--------|----------|--------|
| FSLogix criticality | Nice-to-have (local profile exists) | Mission-critical (no local state) |
| Per-user VHDX size | 30–50 GB typical | 10–30 GB typical |
| Concurrent logon I/O | Low (staggered) | High (storm) |
| Recommended share model | Option A | Option A (<500 users) or Option B (500+) |
| Capacity planning driver | VHDX size × users | IOPS during logon storms |

---

## Session Host Density and Logon Storms

The number of users per session host directly drives the I/O pressure on the SOFS during logon storms.

**Typical densities:**

- **Light workers** (web browsing, document editing): 30–50 users per session host
- **Knowledge workers** (Outlook, Teams, Excel): 15–25 users per session host
- **Power users** (data analysis, development): 5–10 users per session host

**Why this matters for SOFS design:**

When 50 users on a single session host log in within a 5-minute window, the SOFS must simultaneously:

1. Authenticate 50 Kerberos sessions
2. Create or mount 50 VHDX files
3. Expand NTFS metadata for 50 concurrent directory operations
4. Serve profile data reads for 50 desktops loading Start Menu, taskbar, and application settings

With 20 session hosts × 50 users = 1,000 concurrent logons, the SOFS sees a burst of 1,000 VHDX mount operations competing for NTFS lock time, change journal writes, and SMB credits.

This is exactly the scenario where [Option B (split shares)](storage-design.md#option-b-three-volumes-granular) matters — separating Profiles, ODFC, and AppData volumes means Outlook cache writes don't compete with profile loads for NTFS metadata locks.

---

## How FSLogix Maps Users to Shares

Users never see a mapped drive or UNC path. The **FSLogix agent** (`frxsvc.exe`) on each session host handles everything via a kernel-mode filter driver:

1. Administrator configures `VHDLocations` in registry or GPO, pointing to `\\iic-fslogix\Profiles`
2. At user logon, the FSLogix filter driver intercepts the profile load
3. The driver connects to the SOFS share using the user's **AD Kerberos identity**
4. It creates (first login) or mounts (subsequent logins) a per-user VHDX inside a folder named by the user's SID: `<SID>_<Username>/Profile_<Username>.VHDX`
5. The driver redirects `C:\Users\<Username>` into the mounted VHDX — completely transparent to the user and all applications

**Why this matters for SOFS design:**

- The NTFS permissions on the share root must allow `Domain Users` to create their SID folder (Modify on this folder only)
- `CREATOR OWNER` must have Modify on subfolders so each user can write their own VHDX
- The share must be **Continuously Available** (CA) so the VHDX remains mounted during SOFS node failover
- SMB caching must be **disabled** — FSLogix manages its own caching; OS-level SMB caching causes profile corruption

See [Permissions](../configuration/permissions.md) for the complete NTFS ACL model and [FSLogix Configuration](../configuration/fslogix.md) for registry keys and GPO settings.

---

## Cloud Cache for Disaster Recovery

FSLogix Cloud Cache provides read/write replication of profile data to multiple storage providers — the SOFS as primary and an Azure or secondary SMB provider for DR.

**How it works:**

1. Cloud Cache writes to a **local cache on the session host** first
2. It then **asynchronously flushes to all configured providers** (SOFS + Azure Blob or Azure Files)
3. If the SOFS becomes unavailable, users continue working from the local cache
4. At sign-out, Cloud Cache synchronizes all providers before completing
5. When a provider comes back online, automatic resync occurs

**Why Cloud Cache matters for SOFS on Azure Local:**

- **Session continuity** — If the SOFS goes down mid-session, users don't lose work
- **DR without backup infrastructure** — Active replication to Azure replaces traditional VHDX-level backup
- **Up to 4 providers** — Any combination of SMB and Azure Blob (practical limit)
- **Works with SOFS CA shares** — Cloud Cache operates against any SMB share, including SOFS continuously available shares

**Connection string format:**

```
type=smb,name="SOFS",connectionString=\\iic-fslogix\Profiles;type=azure,name="AzureBlob",connectionString="|fslogix/<KEY-NAME>|"
```

!!! note
    Cloud Cache replaces `VHDLocations` — you use `CCDLocations` instead. See [FSLogix Configuration](../configuration/fslogix.md) for the complete registry setup.

---

## Profile Sizing Guidance

The FSLogix `SizeInMBs` registry value sets the maximum VHDX size per user. Plan this based on workload:

| User Type | Typical Profile Size | Recommended `SizeInMBs` |
|-----------|---------------------|------------------------|
| Light office worker | 5–10 GB | 15,000 (15 GB) |
| Knowledge worker with Outlook | 15–30 GB | 30,000 (30 GB) |
| Power user (Outlook + OneDrive + Teams) | 30–50 GB | 50,000 (50 GB) |

**What drives profile size:**

- **Outlook OST** — The largest single contributor. A heavy Outlook user can have a 10–20 GB OST file. With Option B, this goes into the ODFC container instead of the profile container.
- **OneDrive cache** — Files-On-Demand means only opened files consume VHDX space, but aggressive users can cache gigabytes
- **Teams cache** — Meeting recordings, chat attachments, and media thumbnails accumulate
- **Application data** — Chrome/Edge profiles, specialized application databases

Profile sizing feeds directly into [Capacity Planning](capacity-planning.md) — multiply per-user size by user count to get the usable space target.

---

## Network Placement

AVD session hosts and SOFS VMs should be on the **same compute network / VLAN** for optimal latency.

**Why same-subnet matters:**

- Profile load at logon is latency-sensitive — Start Menu and Desktop must render quickly
- Same-subnet eliminates routing hops between session hosts and SOFS
- SMB Multichannel can negotiate optimally when both endpoints are on the same L2 segment
- Logon storms generate thousands of small IOs — even microseconds of added latency multiply across concurrent users

If a dedicated storage VLAN exists, adding a second NIC to each SOFS VM for intra-cluster (S2D replication) traffic is an option, but for most deployments a single compute network NIC is sufficient.

---

## Sister Repository: AVD Session Host Deployment

The [AzureLocal/aurelocal-avd](https://github.com/AzureLocal/aurelocal-avd) repository handles AVD session host deployment on Azure Local. That repo will cross-reference back here for SOFS-based FSLogix profile storage.

The division of responsibility:

| Repository | Scope |
|------------|-------|
| **azurelocal-sofs-fslogix** (this repo) | SOFS infrastructure, SMB shares, NTFS permissions |
| **aurelocal-avd** | Session host VMs, host pools, FSLogix GPO, Cloud Cache config |

---

## Next Steps

- [Deployment Scenarios](scenarios.md) — Worked examples for 5, 200, and 2000 users
- [FSLogix Configuration](../configuration/fslogix.md) — Registry keys, GPO, Cloud Cache setup
- [Permissions](../configuration/permissions.md) — NTFS ACL model for FSLogix shares
