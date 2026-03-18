# Cloud Cache DR Architecture

## Overview

FSLogix Cloud Cache provides a **disaster recovery (DR) overlay** for profile containers hosted on SOFS. Instead of writing profiles to a single SMB share (VHDLocations), Cloud Cache writes simultaneously to multiple providers via the **CCDLocations** registry value, giving:

- **Multi-site redundancy** — profiles are replicated to Azure Blob Storage (or a second SMB share) in near-real-time.
- **Reduced SOFS read load** — the local cache on each AVD session host absorbs read I/O.
- **Transparent failover** — if the SOFS share is unavailable, the Cloud Cache driver fails over to the next healthy provider.

## When to Use Cloud Cache

| Scenario | Recommended? |
|---|---|
| Single-site SOFS with no DR requirement | No — standard VHDLocations is simpler |
| SOFS with Azure Blob DR target | **Yes** — primary use case |
| Multi-site SOFS (active/active) | Yes — list both SMB endpoints |
| Compliance requiring off-site backup | Yes — Azure Blob provider as secondary |

## Architecture

```
AVD Session Host
  └─ FSLogix Cloud Cache Driver (frxccd.sys)
       ├─ Provider 1: type=smb  → \\FSLogixSOFS\Profiles  (SOFS primary)
       └─ Provider 2: type=azure → Azure Blob Storage      (DR target)
```

The Cloud Cache driver maintains a **local cache** (`%TEMP%\intlMountPoints`) and writes to every provider in the CCDLocations list. Reads are served from the local cache. If a provider is unreachable, writes queue locally and resync when connectivity returns.

## Configuration

### Enable Cloud Cache

In `config/variables.yml`:

```yaml
fslogix:
  cloud_cache:
    enabled: true
    providers:
      - type: "azure"
        connectionString: "DefaultEndpointsProtocol=https;AccountName=stfslogixdr;AccountKey=..."
```

### Provider Types

| Type | Description | Connection String Format |
|---|---|---|
| `smb` | SMB file share (auto-generated from SOFS shares) | `\\server\share` |
| `azure` | Azure Blob Storage account | Standard Azure Storage connection string |
| `smb2` | Secondary SMB share (manual) | `\\server2\share` |

> **Note:** SMB providers for the SOFS shares are automatically generated. Only list additional providers (Azure Blob, secondary SMB) in the `providers` array.

### CCDLocations Registry Value

The tools generate the `CCDLocations` value automatically when Cloud Cache is enabled:

```
type=smb,connectionString=\\FSLogixSOFS\Profiles;type=azure,connectionString=DefaultEndpointsProtocol=https;AccountName=stfslogixdr;...
```

- **Registry key:** `HKLM:\SOFTWARE\FSLogix\Profiles`
- **Value name:** `CCDLocations`
- **Value type:** `REG_EXPAND_SZ`
- **Applied to:** AVD session hosts (not SOFS VMs)

When Cloud Cache is enabled, the `VHDLocations` registry value is removed — the two are mutually exclusive.

## Tool Support

All five deployment tools support Cloud Cache:

| Tool | Config Source | CCDLocations Generation |
|---|---|---|
| **PowerShell** | `config/variables.yml` → `fslogix.cloud_cache` | Phase 9c in Configure-SOFS-Cluster.ps1 |
| **Ansible** | Inventory vars `sofs_cloud_cache_*` | Phase 9c in configure-sofs-cluster.yml + configure-fslogix.yml |
| **Terraform** | `cloud_cache_providers` variable | Passed to Ansible inventory template |
| **Bicep** | `cloudCacheProviders` parameter | Passed to guest config engine |
| **ARM** | `cloudCacheProviders` parameter | Compiled from Bicep |

### Provider Resolution Order

1. `providers[]` array (preferred)
2. `azure_provider` string (legacy fallback, deprecated)

## Prerequisites

1. **Azure Storage Account** — create a Standard StorageV2 account for the DR target.
2. **Network connectivity** — AVD session hosts must reach both the SOFS share and the Azure Storage endpoint.
3. **FSLogix agent** — version 2210+ recommended for Cloud Cache stability improvements.
4. **Local cache disk space** — each AVD session host needs temporary disk space for the local cache (`%TEMP%\intlMountPoints`). Size approximately = active profile count × average profile size.

## Antivirus Exclusions

When Cloud Cache is enabled, add these exclusions on AVD session hosts:

- **Processes:** `frxsvc.exe`, `frxdrv.sys`, `frxccd.sys`
- **Paths:** `%ProgramFiles%\FSLogix\Apps\*`, `%TEMP%\intlMountPoints\*`
- **File types:** `*.VHD`, `*.VHDX`

## Monitoring

Monitor Cloud Cache health via:

- **Event Log:** `Applications and Services Logs > Microsoft > FSLogix > CloudCache > Operational`
- **Key events:** Provider connection failures (Event ID 49), provider resync (Event ID 50)
- **Azure Monitor:** Forward FSLogix event logs to Log Analytics for centralized alerting
