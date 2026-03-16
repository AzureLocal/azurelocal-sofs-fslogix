# Antivirus Exclusions

## Overview

Antivirus scanning of FSLogix VHDX files and cluster processes is a common cause of profile corruption, slow logons, and S2D performance issues. Exclusions must be configured on **both** the SOFS VMs and the AVD session hosts.

!!! danger "Configure exclusions before onboarding users"
    Profile corruption caused by AV scanning VHDx files during mount/dismount is difficult to recover from. Apply these exclusions immediately after deployment.

---

## SOFS VM Exclusions

Apply on **each of the three SOFS VMs**. These protect S2D operations and profile VHDX files from real-time scanning.

### Paths

| Exclusion | Type | Reason |
|-----------|------|--------|
| `C:\ClusterStorage` | Path | All CSV volumes — contains S2D data and FSLogix VHDXs |

### File Extensions

| Exclusion | Type | Reason |
|-----------|------|--------|
| `.VHD` | Extension | Virtual hard disk files |
| `.VHDX` | Extension | Virtual hard disk files (current format) |

### Processes

| Exclusion | Type | Reason |
|-----------|------|--------|
| `clussvc.exe` | Process | Cluster Service — manages failover operations |
| `csvfs.sys` | Process | CSV File System driver — handles shared volume I/O |

### PowerShell (Microsoft Defender)

```powershell
# Run on each SOFS VM
Add-MpPreference -ExclusionPath "C:\ClusterStorage"
Add-MpPreference -ExclusionExtension ".VHD"
Add-MpPreference -ExclusionExtension ".VHDX"
Add-MpPreference -ExclusionProcess "clussvc.exe"
Add-MpPreference -ExclusionProcess "csvfs.sys"

# Verify
Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess
```

---

## AVD Session Host Exclusions

Apply on **each AVD session host**. These protect the FSLogix filter driver and profile mount operations.

### Processes

| Exclusion | Type | Reason |
|-----------|------|--------|
| `frxsvc.exe` | Process | FSLogix Profile Service — manages profile container mount/dismount |
| `frxdrv.sys` | Process | FSLogix filter driver — intercepts profile I/O |
| `frxccd.sys` | Process | FSLogix Cloud Cache driver (if Cloud Cache is enabled) |

### Paths

| Exclusion | Type | Reason |
|-----------|------|--------|
| `%ProgramFiles%\FSLogix\Apps` | Path | FSLogix application binaries |
| `%TEMP%\intlMountPoints` | Path | VHDX mount point directory — temporary mounts during logon/logoff |

### File Extensions

| Exclusion | Type | Reason |
|-----------|------|--------|
| `.VHD` | Extension | Virtual hard disk files |
| `.VHDX` | Extension | Virtual hard disk files (current format) |

### PowerShell (Microsoft Defender)

```powershell
# Run on each AVD session host
Add-MpPreference -ExclusionProcess "frxsvc.exe"
Add-MpPreference -ExclusionProcess "frxdrv.sys"
Add-MpPreference -ExclusionProcess "frxccd.sys"
Add-MpPreference -ExclusionPath "$env:ProgramFiles\FSLogix\Apps"
Add-MpPreference -ExclusionPath "$env:TEMP\intlMountPoints"
Add-MpPreference -ExclusionExtension ".VHD"
Add-MpPreference -ExclusionExtension ".VHDX"

# Verify
Get-MpPreference | Select-Object ExclusionPath, ExclusionExtension, ExclusionProcess
```

---

## Third-Party Antivirus

If using a third-party AV product (CrowdStrike, SentinelOne, Sophos, etc.), configure equivalent exclusions through that product's management console. The same paths, extensions, and processes apply regardless of the AV vendor.

---

## Summary

| Target | Paths | Extensions | Processes |
|--------|-------|------------|-----------|
| **SOFS VMs** | `C:\ClusterStorage` | `.VHD`, `.VHDX` | `clussvc.exe`, `csvfs.sys` |
| **Session hosts** | `%ProgramFiles%\FSLogix\Apps`, `%TEMP%\intlMountPoints` | `.VHD`, `.VHDX` | `frxsvc.exe`, `frxdrv.sys`, `frxccd.sys` |

---

## Related

- [FSLogix Configuration](fslogix.md) — Registry settings for profile containers
- [Validation](../deployment/validation.md) — Post-deployment verification
- [Troubleshooting](../operations/troubleshooting.md) — AV-related issues
