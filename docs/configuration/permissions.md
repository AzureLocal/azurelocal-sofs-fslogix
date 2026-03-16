# Permissions

## Overview

FSLogix requires a specific combination of NTFS and SMB permissions on each SOFS share. The model ensures:

- The FSLogix agent can create per-user profile folders on first logon
- Users can only access their own profile data
- Administrators have full control for troubleshooting
- SYSTEM has full access for service operations

---

## NTFS ACL Model

The following table defines the NTFS ACL applied to the root of each FSLogix share. Inheritance is disabled — these are the only entries.

| Principal | Permission | Applies To | Purpose |
|-----------|-----------|------------|---------|
| `CREATOR OWNER` | Modify | Subfolders and files only (`ContainerInherit`, `ObjectInherit`, `InheritOnly`) | Each user owns their SID folder and VHDX — can only modify their own data |
| `DOMAIN\Domain Users` | Modify | This folder only (`None`, `None`) | Allows the FSLogix agent to create the per-user SID folder on first logon |
| `DOMAIN\Domain Admins` | Full Control | This folder, subfolders, and files (`ContainerInherit`, `ObjectInherit`) | Administrative access for troubleshooting and maintenance |
| `NT AUTHORITY\SYSTEM` | Full Control | This folder, subfolders, and files (`ContainerInherit`, `ObjectInherit`) | Required for Windows services and S2D operations |

### How It Works

1. **First logon**: The FSLogix agent (`frxsvc.exe`) runs as the user, connects to `\\SOFSAccessPoint\Share`, and creates a folder named `<SID>_<Username>`.
2. **Domain Users Modify (this folder only)** lets the agent create the folder at the share root.
3. **CREATOR OWNER** applies to the new folder because the user created it — the user gets Modify on their own folder and subfolders.
4. **No other user** can access that folder because there is no inherited "read" or "list" entry for Domain Users on subfolders.

### Applying the NTFS ACL

The `Set-FSLogixNTFS` function applies the correct ACL. It is included in `Configure-SOFS-Cluster.ps1` and `Set-FSLogixShare.ps1`:

```powershell
function Set-FSLogixNTFS {
    param([string]$SharePath, [string]$Domain = "IMPROBABLE")

    $acl = Get-Acl $SharePath
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, remove inherited

    # CREATOR OWNER — Modify (subfolders and files only)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER", "Modify", "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")))

    # Domain Users — Modify (this folder only)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$Domain\Domain Users", "Modify", "None", "None", "Allow")))

    # Domain Admins — Full Control
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$Domain\Domain Admins", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    # SYSTEM — Full Control
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    Set-Acl -Path $SharePath -AclObject $acl
}
```

=== "Option A — Single Share"

    ```powershell
    Set-FSLogixNTFS -SharePath "C:\ClusterStorage\FSLogixData\Profiles"
    ```

=== "Option B — Three Shares"

    ```powershell
    Set-FSLogixNTFS -SharePath "C:\ClusterStorage\Profiles\Profiles"
    Set-FSLogixNTFS -SharePath "C:\ClusterStorage\ODFC\ODFC"
    Set-FSLogixNTFS -SharePath "C:\ClusterStorage\AppData\AppData"
    ```

!!! warning "Inheritance is disabled"
    `SetAccessRuleProtection($true, $false)` removes all inherited ACEs and disables further inheritance. This is intentional — the FSLogix permission model requires a clean ACL with only the four entries above.

---

## SMB Share Permissions

SMB share-level permissions are set when the share is created (Phase 8). They work alongside NTFS permissions — effective access is the **most restrictive** of both.

| Principal | SMB Permission | Purpose |
|-----------|---------------|---------|
| `DOMAIN\Domain Admins` | Full Access | Administrative access |
| `DOMAIN\Domain Users` | Change | Read/write access for profile operations |

### Critical Share Settings

These settings are configured at share creation and must not be changed:

| Setting | Value | Reason |
|---------|-------|--------|
| `ContinuouslyAvailable` | `$true` | Enables SMB3 transparent failover — required for SOFS |
| `CachingMode` | `None` | Disables Windows offline file caching — FSLogix manages its own |
| `ScopeName` | SOFS access point name | Associates the share with the SOFS cluster role, not a single node |
| `FolderEnumerationMode` | `AccessBased` | Access-Based Enumeration — users only see folders they can access |

### SMB Encryption

SMB encryption is recommended for in-transit protection:

```powershell
Set-SmbServerConfiguration -EncryptData $true -Force
```

!!! note "Performance impact"
    SMB encryption adds CPU overhead. On modern processors with AES-NI, the impact is minimal (~2-5% throughput reduction). For Azure Local deployments where SOFS VMs are on the same compute network as session hosts, the security benefit outweighs the performance cost.

---

## Option A vs Option B Permissions

The NTFS ACL model is identical for both options — the same four ACEs are applied to each share root. The difference is only in the number of shares:

| Option | Shares | NTFS Application |
|--------|--------|-----------------|
| **A** — Single share | `FSLogix` (or `Profiles`) | `Set-FSLogixNTFS` called once |
| **B** — Three shares | `Profiles`, `ODFC`, `AppData` | `Set-FSLogixNTFS` called three times (once per share root) |

---

## Verifying Permissions

### NTFS

```powershell
Get-Acl "\\FSLogixSOFS\FSLogix" | Format-List
```

Verify the four entries match the table above and inheritance is disabled.

### SMB

```powershell
Get-SmbShareAccess -Name "FSLogix" -CimSession "sofs-01"
```

---

## Common Permission Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| User cannot create profile on first logon | Domain Users missing Modify on share root | Re-run `Set-FSLogixNTFS` |
| User can see other users' folders | Folder Enumeration not set to AccessBased | Recreate share with `-FolderEnumerationMode AccessBased` |
| Admin cannot access user profile folders | Domain Admins ACE missing or inheritance broken | Re-run `Set-FSLogixNTFS` |
| FSLogix error "access denied" at logon | NTFS and SMB permissions conflict | Verify both layers — effective access is the most restrictive |

---

## Related

- [Validation](../deployment/validation.md) — Verify permissions post-deployment
- [FSLogix Configuration](fslogix.md) — Registry settings that reference these shares
- [Troubleshooting](../operations/troubleshooting.md) — Permission-related troubleshooting
