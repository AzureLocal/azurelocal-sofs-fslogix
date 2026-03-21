# Storage Design

Three critical design decisions determine the storage architecture for the SOFS guest cluster. Each decision is independent and results in a specific combination of host-layer layout, guest-layer resiliency, and share model.

---

## Decision 1: Host Volume Layout

The first decision is how to lay out the Azure Local host-layer CSV volumes that hold the SOFS VMs.

### Recommended: Three Volumes (One Per VM)

Create three separate Azure Local CSV volumes — one per SOFS VM. Each volume holds one VM's OS disk and data disks.

<figure markdown="span">
  ![Three Host Volumes — Base Architecture](../assets/images/sofs-arch-3vol-base.png)
  <figcaption>Three volumes: each SOFS VM on its own CSV volume</figcaption>
</figure>

| Volume | Usable Size | Raw (2-way mirror) | Contents |
|--------|-------------|---------------------|----------|
| `SOFS-Vol-01` | ~4.2 TB | ~8.4 TB | SOFS VM 1 — OS + 4 data disks |
| `SOFS-Vol-02` | ~4.2 TB | ~8.4 TB | SOFS VM 2 — OS + 4 data disks |
| `SOFS-Vol-03` | ~4.2 TB | ~8.4 TB | SOFS VM 3 — OS + 4 data disks |
| **Total** | **~12.5 TB** | **~25 TB** | |

**Why this is the right design:** If one Azure Local volume goes offline, only the SOFS VM on that volume is affected. The guest S2D cluster still has two healthy nodes — the two-way mirror continues serving profiles with zero interruption to AVD sessions. This eliminates a shared-fate dependency that would make anti-affinity rules and the entire guest cluster pointless.

### Alternative: Single Volume

One large volume holds all three VMs:

<figure markdown="span">
  ![Single Host Volume — Base Architecture](../assets/images/sofs-arch-1vol-base.png)
  <figcaption>Single volume: all SOFS VMs share one CSV volume</figcaption>
</figure>

| Volume | Usable Size | Raw (2-way mirror) | Contents |
|--------|-------------|---------------------|----------|
| `SOFS-Storage` | ~12.5 TB | ~25 TB | All 3 VMs (OS + data) |

**Use only** if the Azure Local cluster cannot accommodate three separate volumes (e.g., limited number of drives) or if simplicity outweighs the fault isolation benefit. A volume-level issue takes out the entire guest cluster.

### No Thin Provisioning

!!! danger "Do not thin-provision the host volumes"
    `New-Volume` uses fixed provisioning by default — leave it that way. Thin provisioning creates more problems than it solves for SOFS host volumes:

    - **Pool full = all volumes die.** If total writes exceed the physical pool capacity, S2D puts the pool into a degraded/read-only state. That's not one volume full — it's every SOFS VM going read-only simultaneously.
    - **Defeats fault isolation.** Three volumes on a shared thin pool are back to a shared-fate dependency on pool free space — exactly what separate volumes are designed to eliminate.
    - **Write-time allocation overhead.** Every write must find and allocate slabs from the pool. During a logon storm, that's an extra metadata operation per write. Fixed provisioning has pre-allocated extents — writes go straight to reserved space.
    - **Misleading capacity reporting.** Volumes report large free space while the underlying pool may be nearly full. Admin tools, PerfMon, and FSRM all show the logical number, not the physical reality.

    Fixed provisioning: pre-calculate sizes from [Capacity Planning](capacity-planning.md), allocate up front, monitor each volume independently.

---

## Decision 2: Guest S2D Resiliency

The second decision is the mirror level inside the guest S2D cluster.

### Recommended: Two-Way Mirror

Two data copies across the 3-node S2D pool. Tolerates 1 simultaneous VM failure.

| Metric | Value |
|--------|-------|
| Data copies | 2 |
| Usable space from 12 TB pool | ~5.5 TB |
| Raw-to-usable ratio (stacked) | ~4.5 : 1 |
| Fault tolerance | 1 VM/node failure |

### Alternative: Three-Way Mirror

Three data copies. Tolerates 2 simultaneous VM failures. Significantly higher raw capacity cost.

| Metric | Value |
|--------|-------|
| Data copies | 3 |
| Usable space from ~17 TB pool | ~5.5 TB |
| Raw-to-usable ratio (stacked) | ~6.2 : 1 |
| Fault tolerance | 2 VM/node failures |

!!! warning "Explicit `-NumberOfDataCopies 2` required"
    On a 3-node S2D cluster, the default mirror is **three-way**. You must explicitly specify `-NumberOfDataCopies 2` when creating guest volumes to use a two-way mirror. Without it, each volume consumes 50% more raw capacity than expected.

**Recommendation:** The two-way mirror is recommended for most deployments. The Azure Local two-way mirror underneath already protects against physical disk and host node failures, making the additional three-way mirror at the guest layer hard to justify — especially for profile data that can be repopulated.

### No Thin Provisioning on Guest Volumes

!!! danger "Do not thin-provision guest S2D volumes"
    The same thin-provisioning dangers apply at the guest layer. If the guest S2D pool runs out of physical space, **all** guest volumes go read-only — every FSLogix profile becomes inaccessible simultaneously. Fixed provisioning with pre-calculated sizes is the only safe approach.

---

## Decision 3: Guest Volume Layout (Share Model)

The third decision is how to carve the usable S2D space into FSLogix volumes and shares. Both options use the same hardware, the same S2D pool, and the same total capacity.

### Single layout — Single Volume (Simple)

One guest S2D volume holds all FSLogix data:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `FSLogixData` | 5,632 GB (5.5 TB) | `Profiles` | Profile containers, ODFC containers, AppData |

<figure markdown="span">
  ![Three Host Volumes + Single layout](../assets/images/sofs-arch-3vol-single.png)
  <figcaption>Three host volumes with Single layout: single FSLogix share</figcaption>
</figure>

**When to use Single layout:**

- Under ~500 users with low-density session hosts (under ~30 users per host)
- Simpler to deploy — one volume, one share, one FSLogix GPO path
- All free space is shared — no risk of one workload filling "its" volume while another has headroom
- Fewer monitoring targets and backup jobs

### Triple layout — Three Volumes (Granular)

Separate guest S2D volumes for each FSLogix workload:

| Volume | Size | Share | Contents |
|--------|------|-------|----------|
| `Profiles` | 3,072 GB (3 TB) | `Profiles` | Profile containers (user data, settings) |
| `ODFC` | 1,536 GB (1.5 TB) | `ODFC` | Office Data File Containers (Outlook OST, Teams cache) |
| `AppData` | 1,024 GB (1 TB) | `AppData` | Per-user AppData redirections |
| **Total** | **5,632 GB (5.5 TB)** | | |

<figure markdown="span">
  ![Three Host Volumes + Triple layout](../assets/images/sofs-arch-3vol-triple.png)
  <figcaption>Three host volumes with Triple layout: three FSLogix shares</figcaption>
</figure>

**When to use Triple layout:**

- 500+ users or high-density session hosts (50+ users per host)
- Environments where Outlook/Teams cache churn is a known problem

**Why Triple layout matters at scale:**

- **NTFS metadata isolation** — Each volume has its own MFT and change journal. Outlook OST writes hammering the ODFC change journal don't compete with profile writes for NTFS lock time on the Profiles volume.
- **Logon storm resilience** — Heavy AppData syncs (Chrome profiles, specialized apps) only slow the AppData volume. The Profiles volume stays responsive — Start Menu and Desktop load fast for everyone else.
- **FSRM quotas** — Per-volume File Server Resource Manager quotas let you hard-cap ODFC so one user's 50 GB Outlook cache can't eat into profile space. Impossible with a single volume.
- **Monitoring granularity** — Separate PerfMon counters per volume. "ODFC at 85%" is actionable. "FSLogixData at 60%" tells you nothing about what's growing.
- **Future migration path** — If you move to Azure NetApp Files or tiered storage later, pre-separated data maps cleanly to different tiers (fast tier for Profiles, cheaper tier for ODFC/AppData).

---

## Decision Matrix

The three decisions combine into a specific architecture. Here are the most common combinations:

### All Combinations — Single Host Volume

<figure markdown="span">
  ![Single Host Volume + Single layout](../assets/images/sofs-arch-1vol-single.png)
  <figcaption>Single host volume + Single layout: simplest deployment</figcaption>
</figure>

<br />

<figure markdown="span">
  ![Single Host Volume + Triple layout](../assets/images/sofs-arch-1vol-triple.png)
  <figcaption>Single host volume + Triple layout: share isolation without volume isolation</figcaption>
</figure>

### Recommendation by Environment

| Environment | Host Volumes | Guest Mirror | Share Model | Diagram |
|-------------|-------------|-------------|------------|---------|
| Under 50 users, personal desktops | Single or Three | Two-way | **Single layout** | `sofs-arch-1vol-option-a` |
| 50–500 users, mixed workloads | Three | Two-way | **Single layout** | `sofs-arch-3vol-option-a` |
| 500+ users, pooled session hosts | Three | Two-way | **Triple layout** | `sofs-arch-3vol-option-b` |
| Maximum resiliency required | Three | Three-way | **Triple layout** | `sofs-arch-3vol-option-b` |

---

## S2D Guest Tuning

Two registry-level tunings are required for S2D running inside VMs:

### HwTimeout Increase

The default spaceport timeout (30 seconds) is too aggressive for VM-hosted S2D. The additional I/O latency of running inside a VM (host storage → virtual disk → guest S2D) can cause spurious timeout errors under load. Increase to 60 seconds on each SOFS VM.

### Auto-Replace Disable

S2D's automatic physical disk replacement feature monitors for failing drives and replaces them transparently. Inside VMs, the "physical" disks are virtual hard disks — they don't fail in the same way. Disable auto-replace to prevent S2D from attempting to rebuild data onto a newly-attached disk that was intended as an expansion.

---

## What's Next

| Topic | Link |
|-------|------|
| Raw-to-usable capacity calculations | [Capacity Planning](capacity-planning.md) |
| Worked sizing examples at different scales | [Deployment Scenarios](scenarios.md) |
| How AVD session host density affects design choices | [AVD Considerations](avd-considerations.md) |
