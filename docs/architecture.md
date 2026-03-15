# Architecture Overview

## Solution Summary

This solution deploys a **Scale Out File Server (SOFS)** cluster on **Azure Local** to provide a highly available, SMB 3.x share used by **FSLogix** to store user profile containers (VHD/VHDX) for **Azure Virtual Desktop (AVD)** session hosts running on Azure Local.

---

## High-Level Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      Azure Local Cluster                  │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │           Scale Out File Server (SOFS)          │     │
│  │                                                 │     │
│  │  Node 1  ──┐                                   │     │
│  │  Node 2  ──┼──  Clustered Shared Volumes (CSV) │     │
│  │  Node N  ──┘      \\SOFS\FSLogixProfiles        │     │
│  └─────────────────────────────────────────────────┘     │
│                                                          │
│  ┌─────────────────────────────────────────────────┐     │
│  │           AVD Session Hosts (VMs)               │     │
│  │  Host 1  ──┐                                   │     │
│  │  Host 2  ──┼──  FSLogix mounts \\SOFS\...      │     │
│  │  Host N  ──┘                                   │     │
│  └─────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
           │
           │  Azure Arc / Azure Local resource provider
           ▼
    ┌─────────────┐
    │   Azure     │
    │   Portal /  │
    │   ARM / CLI │
    └─────────────┘
```

---

## Key Components

| Component | Description |
|-----------|-------------|
| **Azure Local Cluster** | Hyper-converged infrastructure running Windows Server Storage Spaces Direct |
| **Clustered Shared Volumes (CSV)** | Shared storage volumes presented to all cluster nodes |
| **Scale Out File Server (SOFS)** | Windows Server Failover Cluster role providing continuously available SMB shares |
| **FSLogix** | Microsoft profile container technology storing full user profiles as VHD/VHDX files |
| **AVD Session Hosts** | Azure Virtual Desktop virtual machines running on Azure Local |

---

## Network Considerations

- SMB traffic between AVD session hosts and SOFS should use a dedicated storage VLAN (recommended).
- Ensure ports **445 (SMB)** and **135/49152-65535 (RPC)** are open between session hosts and SOFS cluster nodes.
- Use **SMB encryption** (`Set-SmbServerConfiguration -EncryptData $true`) for data-in-transit protection.
- DNS resolution for the SOFS cluster name must be available to all session hosts.

---

## Storage Sizing Guidance

| User Count | Recommended VHD Size | CSV Capacity (estimate) |
|------------|----------------------|------------------------|
| Up to 100  | 30 GB per user       | ~3 TB usable           |
| 100 – 500  | 30 GB per user       | ~15 TB usable          |
| 500+       | 30 GB per user       | Scale horizontally     |

Adjust based on actual profile sizes observed in your environment.

---

## FSLogix Profile Container Settings

Key Group Policy / registry settings applied to session hosts:

| Setting | Value |
|---------|-------|
| `VHDLocations` | `\\<SOFS-Name>\FSLogixProfiles` |
| `Enabled` | `1` |
| `DeleteLocalProfileWhenVHDShouldApply` | `1` |
| `FlipFlopProfileDirectoryName` | `1` |
| `ProfileType` | `0` (default: single primary) |

---

## Related Resources

- [FSLogix documentation](https://learn.microsoft.com/en-us/fslogix/)
- [Scale Out File Server overview](https://learn.microsoft.com/en-us/windows-server/failover-clustering/sofs-overview)
- [Azure Local documentation](https://learn.microsoft.com/en-us/azure/azure-local/)
- [Azure Virtual Desktop on Azure Local](https://learn.microsoft.com/en-us/azure/virtual-desktop/azure-local-overview)
