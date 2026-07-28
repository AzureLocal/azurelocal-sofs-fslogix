# Capacity Planning

## Overview

Capacity planning for a guest SOFS on Azure Local is different from a traditional file server because resiliency is applied at **two stacked layers** — the Azure Local host-layer mirror underneath and the guest S2D mirror inside the VMs. Raw capacity requirements multiply at each layer, making upfront math essential.

This page walks through the methodology, provides worked calculations for two-way and three-way guest mirrors, and gives you the ratios needed to size any deployment.

> [!WARNING]
> **All numbers are examples**
> The calculations below use a **5 TB usable** target (plus 10% growth headroom). Your deployment will differ based on user count, profile sizes, and resiliency choices. Use the [Azure Local Sizer (Odin)](https://azure.github.io/odinforazurelocal/sizer/) to validate raw capacity requirements for your specific environment.
>
---

## The Stacked Mirror Problem

A single usable gigabyte of FSLogix profile storage passes through two mirror layers before it becomes physical disk consumption:

```
Usable Space
    → Guest S2D Mirror (×2 or ×3 copies)
        → Per-VM Data Disks
            → Azure Local Host Volume (×2 mirror)
                → Raw Physical Disk
```

Each layer multiplies. The result is a **raw-to-usable ratio** that can surprise if you haven't done the math.

---

## Calculation Methodology

Work **bottom-up from usable space** through each layer:

| Step | Question | Formula |
|------|----------|---------|
| 1 | How much usable FSLogix space do you need? | Business requirement + growth buffer |
| 2 | How much raw S2D pool capacity does that require? | Usable × `NumberOfDataCopies` (2 or 3) |
| 3 | How many data disks per VM, and what size? | Total pool ÷ (VM count × disks per VM), rounded up |
| 4 | How large must each Azure Local host volume be? | Per-VM: OS disk + all data disks + overhead |
| 5 | How much raw physical disk does that consume? | Host volume usable × host mirror copies (typically 2) |

---

## Worked Example: Two-Way Guest Mirror (Recommended)

**Target:** 5 TB usable + 10% growth = **5.5 TB usable**

| Step | Layer | Calculation | Result |
|------|-------|-------------|--------|
| 1 | Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| 2 | Guest S2D two-way mirror | 5.5 TB × 2 copies | **11 TB** raw in S2D pool |
| 3 | Per-VM data disks | 12 TB pool ÷ 3 VMs = 4 TB/VM → 4 × 1 TB disks | **4 × 1 TB** per VM (12 disks total) |
| 4 | Azure Local volumes (usable) | 3 × ~4.2 TB (OS + data per VM) | **~12.5 TB total** |
| 5 | Azure Local two-way mirror (raw) | 12.5 TB × 2 copies | **~25 TB physical disk** |

**Raw-to-usable ratio: ~4.5 : 1**

5.5 TB of usable profile storage requires approximately 25 TB of raw physical disk on the Azure Local cluster.

---

## Worked Example: Three-Way Guest Mirror

**Target:** Same 5.5 TB usable, but with three data copies for maximum guest-level resiliency.

| Step | Layer | Calculation | Result |
|------|-------|-------------|--------|
| 1 | Usable FSLogix space | 5 TB + 10% growth | **5.5 TB** |
| 2 | Guest S2D three-way mirror | 5.5 TB × 3 copies | **16.5 TB** raw in S2D pool |
| 3 | Per-VM data disks | 16.8 TB pool ÷ 3 VMs = 5.6 TB/VM → 4 × 1.4 TB disks | **4 × 1.4 TB** per VM (12 disks total) |
| 4 | Azure Local volumes (usable) | 3 × ~5.7 TB (OS + data per VM) | **~17 TB total** |
| 5 | Azure Local two-way mirror (raw) | 17 TB × 2 copies | **~34 TB physical disk** |

**Raw-to-usable ratio: ~6.2 : 1**

The three-way mirror adds approximately **9 TB of additional raw physical disk** for the same 5.5 TB of usable space — a 36% increase over the two-way design.

---

## Comparison Table

| | Two-Way Mirror | Three-Way Mirror |
|---|---|---|
| **Usable profile space** | 5.5 TB | 5.5 TB |
| **Guest S2D pool (raw)** | 11 TB | 16.5 TB |
| **Data disk per VM** | 4 × 1 TB | 4 × 1.4 TB |
| **Azure Local volumes (total usable)** | ~12.5 TB (3 × ~4.2 TB) | ~17 TB (3 × ~5.7 TB) |
| **Raw physical disk consumed** | **~25 TB** | **~34 TB** |
| **Raw-to-usable ratio** | **~4.5 : 1** | **~6.2 : 1** |
| **Guest-level fault tolerance** | 1 node failure | 2 node failures |

---

## Which Resiliency to Choose

> [!TIP]
> **Recommendation: Two-way mirror**
> The Azure Local two-way mirror underneath already protects against physical disk and host node failures. The guest S2D two-way mirror adds a **second** resiliency layer at the VM level. A three-way mirror at the guest layer is hard to justify for an extra ~9 TB of raw capacity — especially for FSLogix profile data that can be regenerated from Cloud Cache or a secondary provider.
>
Choose **three-way** only if:

- Regulatory or compliance requirements mandate it
- The environment cannot tolerate any possibility of profile data loss during a simultaneous two-node guest failure
- The Azure Local cluster has ample raw capacity headroom

---

## Dynamic Provisioning: Day-One vs. Ceiling

Data disks are created with **dynamic provisioning** — they don't consume their full allocated size on the Azure Local host volume from day one. Consumption grows as FSLogix profiles are written.

| Metric | Day One | Full Capacity |
|--------|---------|---------------|
| Per-VM data disk allocation | 4 × 1 TB = 4 TB | 4 × 1 TB = 4 TB |
| Actual per-VM disk consumption | ~50 GB (empty S2D pool) | Up to 4 TB |
| Azure Local host volume consumed | ~200 GB (OS + empty data) | ~4.2 TB |
| Total raw physical consumed | ~1.2 TB | ~25 TB |

This means Day one cluster impact is minimal. However, **you must reserve the full ceiling capacity** on the Azure Local cluster because the data disks will grow over time and you cannot safely over-commit the host storage pool.

> [!CAUTION]
> **Do not thin-provision host volumes**
> Fixed provisioning on the Azure Local host volumes ensures each volume has its full capacity reserved. Thin provisioning lets you over-commit the storage pool — if total writes exceed physical capacity, **all** volumes go read-only simultaneously. See [Storage Design — No Thin Provisioning](storage-design.md) for the full rationale.
>
---

## Growth Headroom

The 10% growth buffer (5 TB → 5.5 TB) provides headroom for:

- New user onboarding
- Profile size creep (application updates, cache growth)
- Temporary spikes during logon storms (VHDX expansion before garbage collection)

**Monitor and expand before hitting the ceiling.** When the guest S2D volumes reach 80% utilization:

1. Expand the Azure Local host volumes (increase `New-Volume -Size`)
2. Expand the VM data disks (increase disk size in Azure portal or automation)
3. Expand the guest S2D volumes (`Resize-VirtualDisk`)

The expansion order matters — you must have host-layer capacity before the guest layer can grow.

---

## Applying This to Your Environment

To size a deployment for a different user count:

1. **Estimate usable space needed** — Start with FSLogix profile size × user count. Typical profile sizes:
    - Light office worker: 5–10 GB
    - Knowledge worker with Outlook: 15–30 GB
    - Power user (large Outlook, OneDrive, Teams): 30–50 GB
2. **Add growth headroom** — 10% minimum, 20% if rapid user growth is expected
3. **Run the stacked calculation** — Follow the step-by-step table above
4. **Validate with Azure Local Sizer** — [Azure Local Sizer (Odin)](https://azure.github.io/odinforazurelocal/sizer/) gives you physical node and disk requirements for any raw capacity target

For worked examples at different scales, see [Deployment Scenarios](scenarios.md).

---

## Next Steps

- [Storage Design](storage-design.md) — Host volume layout and guest volume layout decisions
- [Deployment Scenarios](scenarios.md) — 5-user, 200-user, and 2000-user worked examples
- [Prerequisites](../deployment/prerequisites.md) — Infrastructure and licensing requirements
