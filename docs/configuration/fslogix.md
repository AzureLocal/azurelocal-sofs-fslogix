# FSLogix Configuration

## Overview

FSLogix Profile Containers redirect user profiles into VHD/VHDX files stored on the SOFS share. Configuration is done on AVD **session hosts** (not on the SOFS VMs) via registry keys or Group Policy.

!!! info "This page covers session host configuration"
    The SOFS shares and permissions are configured during [deployment](../deployment/powershell.md). This page covers the FSLogix agent settings on the machines that **consume** those shares.

---

## Option A — Single Share

All profile data (profile container, Office data, AppData) goes into one VHDX per user on a single share.

### Registry Keys

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\Profiles
    SizeInMBs                        REG_DWORD    30000
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
```

| Key | Value | Purpose |
|-----|-------|---------|
| `Enabled` | `1` | Activates FSLogix Profile Container |
| `VHDLocations` | `\\iic-fslogix\Profiles` | UNC path to the SOFS share |
| `SizeInMBs` | `30000` | Maximum VHDX size per user (30 GB) |
| `VolumeType` | `VHDX` | Use VHDX format (supports up to 64 TB, recommended over VHD) |
| `FlipFlopProfileDirectoryName` | `1` | Creates folders as `%username%_%sid%` instead of `%sid%_%username%` — easier to identify |

---

## Option B — Three Shares

Profile containers and Office Data File Containers (ODFC) are separated onto dedicated volumes.

### Profile Container Registry Keys

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\Profiles
    SizeInMBs                        REG_DWORD    30000
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
```

### ODFC Container Registry Keys

```
HKLM\SOFTWARE\Policies\FSLogix\ODFC
    Enabled                          REG_DWORD    1
    VHDLocations                     REG_MULTI_SZ \\iic-fslogix\ODFC
    VolumeType                       REG_SZ       VHDX
    FlipFlopProfileDirectoryName     REG_DWORD    1
    IncludeOutlookPersonalization    REG_DWORD    1
```

| Key | Value | Purpose |
|-----|-------|---------|
| `VHDLocations` | `\\iic-fslogix\ODFC` | Points to the dedicated ODFC share |
| `IncludeOutlookPersonalization` | `1` | Includes Outlook signatures, stationery, and other personalization data |

!!! note "ODFC separates Office data"
    When ODFC containers are enabled, Outlook OST files, Teams cache, and OneDrive data are stored in the ODFC VHDX instead of the profile container. This keeps profile containers smaller and allows independent sizing for each workload.

### AppData Redirection

The AppData share can be consumed via:

- **Folder Redirection GPO** — Redirect `AppData\Roaming` to `\\iic-fslogix\AppData\%USERNAME%`
- **Separate FSLogix container** — Less common; choose based on user persona

---

## Group Policy Path

FSLogix settings can be applied via Group Policy instead of direct registry edits:

```
Computer Configuration → Administrative Templates → FSLogix → Profile Containers
```

The FSLogix ADMX/ADML templates must be installed in your AD Central Store. Download from the [FSLogix download page](https://learn.microsoft.com/en-us/fslogix/overview-what-is-fslogix).

---

## Cloud Cache Configuration (Optional)

Cloud Cache replaces `VHDLocations` with `CCDLocations` to provide active replication across multiple storage providers. Use this for DR scenarios where you want profile data replicated to Azure.

```
HKLM\SOFTWARE\FSLogix\Profiles
    Enabled                          REG_DWORD    1
    CCDLocations                     REG_SZ       type=smb,name="SOFS",connectionString=\\iic-fslogix\Profiles;type=azure,name="AzureBlob",connectionString="|fslogix/<KEY-NAME>|"
    ClearCacheOnLogoff               REG_DWORD    1
    FlipFlopProfileDirectoryName     REG_DWORD    1
```

### How Cloud Cache Works

1. Writes go to a **local cache** on the session host first
2. Cloud Cache asynchronously flushes to **all configured providers** (SOFS + Azure Blob)
3. If the SOFS goes down mid-session, the user continues working from local cache
4. At sign-out, Cloud Cache ensures all providers are synchronized before completing
5. On next logon, Cloud Cache selects the provider with the most recent data

### Connection String Format

The `CCDLocations` value is a semicolon-separated list of providers:

| Provider Type | Format |
|--------------|--------|
| SMB (SOFS) | `type=smb,name="<label>",connectionString=\\<server>\<share>` |
| Azure Blob | `type=azure,name="<label>",connectionString="\|fslogix/<key-vault-key>\|"` |

!!! warning "Do not use both `VHDLocations` and `CCDLocations`"
    These are mutually exclusive. If `CCDLocations` is set, `VHDLocations` is ignored. Choose one approach.

---

## Profile Sizing

| User Type | Recommended `SizeInMBs` | Notes |
|-----------|------------------------|-------|
| Light (task workers) | 5,000–10,000 | Minimal Office use, web apps |
| Knowledge workers | 15,000–30,000 | Standard Office suite, moderate Outlook |
| Power users | 30,000–50,000 | Large mailboxes, development tools, OneDrive sync |

The default 30 GB is suitable for most knowledge workers. Monitor actual usage after deployment and adjust.

---

## Ansible Automation

The `configure-fslogix.yml` playbook applies these registry settings to AVD session hosts:

```bash
ansible-playbook -i inventory/hosts.yml \
    src/ansible/playbooks/configure-fslogix.yml
```

It sets `Enabled`, `VHDLocations`, `FlipFlopProfileDirectoryName`, container size, and local profile cleanup. See [Ansible Deployment](../deployment/ansible.md) for details.

---

## Related

- [Permissions](permissions.md) — NTFS and SMB permissions on the SOFS shares
- [AVD Considerations](../architecture/avd-considerations.md) — How FSLogix maps users to shares
- [Antivirus Exclusions](antivirus.md) — Required AV exclusions on session hosts
- [Variables Reference](../deployment/variables.md) — Central configuration that includes SOFS share names
