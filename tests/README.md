# Tests — Phase 4: Validation

Validate that the SOFS deployment is working correctly and FSLogix settings are configured.

---

## Scripts

| Script | Description |
|--------|-------------|
| `Test-SOFSDeployment.ps1` | Validates SMB share reachability, share settings (CA, encryption), NTFS write access, and FSLogix registry on the local machine |

---

## Quick Start

```powershell
.\tests\Test-SOFSDeployment.ps1 -SOFSName "SOFS01" -ShareName "FSLogixProfiles"
```

With optional AVD group validation:

```powershell
.\tests\Test-SOFSDeployment.ps1 `
  -SOFSName "SOFS01" `
  -ShareName "FSLogixProfiles" `
  -AVDUsersGroup "AVD-Users"
```

---

## What Gets Validated

| Check | Description |
|-------|-------------|
| **Share reachability** | Can the SMB share `\\<SOFSName>\<ShareName>` be accessed? |
| **Continuously Available** | Is the share configured with the CA flag? |
| **SMB encryption** | Is encryption enabled on the share? |
| **NTFS write access** | Can the current user write to the share path? |
| **FSLogix registry** | Are the FSLogix profile container registry keys set on this machine? |

The script returns a `PSCustomObject` with pass/fail results for each check.
