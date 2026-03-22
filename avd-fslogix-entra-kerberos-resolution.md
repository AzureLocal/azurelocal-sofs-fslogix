# FSLogix Profile Container — Entra ID Kerberos Authentication Resolution

## Document Purpose

This document records every step required to get FSLogix profile containers working with Azure Files using Microsoft Entra ID Kerberos (AADKERB) authentication in a **cloud-only identity** environment (no on-premises Active Directory). It captures the full sequence of failures, root cause analysis, and the specific fixes that ultimately resolved the issue.

**Environment**: Azure Local Cloud (`azurelocal.cloud`) — cloud-only Entra ID tenant  
**Subscription**: `3ec7d3c3-c201-4f5d-a28c-d2730c3ad6f6`  
**Tenant**: `604d3138-c7b3-481d-928f-e4a5dfb0f528`  
**Date Resolved**: March 21, 2026

---

## Table of Contents

1. [Environment Summary](#environment-summary)
2. [Initial Deployment — What Was Done](#initial-deployment--what-was-done)
3. [The Failure — Error 0x0000052E](#the-failure--error-0x0000052e)
4. [Investigation Timeline](#investigation-timeline)
5. [Root Cause — Three Missing Configuration Steps](#root-cause--three-missing-configuration-steps)
6. [Fix 1 — Admin Consent for API Permissions](#fix-1--admin-consent-for-api-permissions)
7. [Fix 2 — Cloud-Only Groups Tag on App Registration](#fix-2--cloud-only-groups-tag-on-app-registration)
8. [Fix 3 — Default Share-Level Permission](#fix-3--default-share-level-permission)
9. [Verification and Proof](#verification-and-proof)
10. [Key Learnings and Gotchas](#key-learnings-and-gotchas)
11. [Maintenance — kerb1 Key Rotation](#maintenance--kerb1-key-rotation)
12. [Complete Configuration Reference](#complete-configuration-reference)
13. [Microsoft Learn References](#microsoft-learn-references)

---

## Environment Summary

### Azure Resources

| Resource | Name | Resource Group |
|----------|------|----------------|
| Storage Account | `stazlcavdfslogixeus` | `rg-azlc-avd-storage-eus` |
| File Share | `fslogix` (1024 GB, Premium_LRS) | — |
| Session Host VM | `vmavdazl-01` (Standard_NV6ads_A10_v5) | `rg-azlc-avd-compute-eus` |
| Host Pool | `hp-azlc-avd-gpu-eus` (Personal, Persistent) | `rg-azlc-avd-core-eus` |
| Log Analytics | `law-azlc-avd-eus` | `rg-azlc-avd-ops-eus` |

### Identity

| Item | Value |
|------|-------|
| Domain | `azurelocal.cloud` (cloud-only, no on-prem AD) |
| Tenant ID | `604d3138-c7b3-481d-928f-e4a5dfb0f528` |
| Test User | `kristopher.turner@azurelocal.cloud` |
| User SID | `S-1-12-1-817207761-1111759829-1452962451-820446406` |
| Join Type | Entra ID joined (not hybrid) |

### Security Groups

| Group | Object ID | Purpose |
|-------|-----------|---------|
| `azlc-avd-fslogix-users` | `43d0ffef-8685-44cd-9153-0927b536a800` | SMB Share Contributor |
| `azlc-avd-fslogix-ops` | `5e0ecd0e-a22f-4e52-b121-cba7ce9d2007` | SMB Share Elevated Contributor |
| `azlc-avd-gpu-users` | `31c83445-b98e-4473-accc-8b9d8b8dfa81` | AVD app group access |
| `azlc-avd-vmadmins` | `2181a681-9b94-4de5-ae0f-f2f93c770ce4` | VM admin login |

---

## Initial Deployment — What Was Done

The following steps were completed in the original deployment, all of which were correct and necessary:

### 1. Storage Account and Share

```powershell
az storage account create -g rg-azlc-avd-storage-eus -n stazlcavdfslogixeus -l eastus `
    --sku Premium_LRS --kind FileStorage --https-only true --allow-blob-public-access false

az storage share-rm create --storage-account stazlcavdfslogixeus `
    -g rg-azlc-avd-storage-eus --name fslogix --quota 1024 `
    --enabled-protocols SMB --root-squash NoRootSquash
```

### 2. Enable Entra ID Kerberos (AADKERB) on Storage Account

```powershell
Set-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" `
    -EnableAzureActiveDirectoryKerberosForFile $true `
    -ActiveDirectoryDomainName "azurelocal.cloud" `
    -ActiveDirectoryDomainGuid "604d3138-c7b3-481d-928f-e4a5dfb0f528"
```

This command:
- Sets `directoryServiceOptions` to `AADKERB`
- Creates an App Registration: `[Storage Account] stazlcavdfslogixeus.file.core.windows.net`
- Creates a corresponding Service Principal
- Generates a Symmetric keyCredential (kerb1 key) on the Service Principal
- Sets `identifierUris` on the app for `host/`, `cifs/`, and `http/` SPN variants

### 3. RBAC Assignments on the File Share

```powershell
# SMB Share Contributor for users
az role assignment create --assignee "43d0ffef-8685-44cd-9153-0927b536a800" `
    --role "Storage File Data SMB Share Contributor" `
    --scope "/subscriptions/3ec7d3c3-c201-4f5d-a28c-d2730c3ad6f6/resourceGroups/rg-azlc-avd-storage-eus/providers/Microsoft.Storage/storageAccounts/stazlcavdfslogixeus/fileServices/default/fileshares/fslogix"

# SMB Share Elevated Contributor for operators
az role assignment create --assignee "5e0ecd0e-a22f-4e52-b121-cba7ce9d2007" `
    --role "Storage File Data SMB Share Elevated Contributor" `
    --scope "/subscriptions/3ec7d3c3-c201-4f5d-a28c-d2730c3ad6f6/resourceGroups/rg-azlc-avd-storage-eus/providers/Microsoft.Storage/storageAccounts/stazlcavdfslogixeus/fileServices/default/fileshares/fslogix"
```

### 4. FSLogix Registry Configuration on VM

Set via `az vm run-command invoke`:

```
HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 1
HKLM:\SOFTWARE\FSLogix\Profiles\VHDLocations = \\stazlcavdfslogixeus.file.core.windows.net\fslogix
HKLM:\SOFTWARE\FSLogix\Profiles\VolumeType = VHDX
HKLM:\SOFTWARE\FSLogix\Profiles\SizeInMBs = 30720
HKLM:\SOFTWARE\FSLogix\Profiles\FlipFlopProfileDirectoryName = 1
HKLM:\SOFTWARE\FSLogix\Profiles\DeleteLocalProfileWhenVHDShouldApply = 1
HKLM:\SOFTWARE\FSLogix\Profiles\PreventLoginWithFailure = 0
HKLM:\SOFTWARE\FSLogix\Profiles\PreventLoginWithTempProfile = 0
```

### 5. Cloud Kerberos Ticket Retrieval on VM

```
HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1
```

### 6. Host Pool RDP Properties

```
targetisaadjoined:i:1;enablerdsaadauth:i:1
```

### 7. Verified Pre-Conditions

- FSLogix services running: `frxsvc`, `frxdrv`, `frxccds`
- TCP port 445 open from VM to `stazlcavdfslogixeus.file.core.windows.net`
- User is member of `azlc-avd-fslogix-users` group
- RBAC assignments confirmed on the file share

**All of the above was correctly implemented. The issue was that three additional configuration steps — not obvious from the basic setup guide — were missing.**

---

## The Failure — Error 0x0000052E

### Symptoms

- FSLogix profile log showed: `Error 0x0000052E` and `Error 1265`
- Windows error code `0x0000052E` = `ERROR_LOGON_FAILURE` ("The user name or password is incorrect")
- Error `1265` = `ERROR_CANT_ACCESS_DOMAIN_INFO` ("The machine is not joined to a domain, or the domain trust relationship failed")
- The VHD container was never created on the share
- User received a temporary local profile on login

### What This Meant

The Entra ID Kerberos authentication flow was failing at the point where the VM attempts to obtain a Kerberos ticket to access the Azure Files share. The VM could reach the storage endpoint (TCP 445 open), but the authentication exchange was rejected.

---

## Investigation Timeline

### Attempt 1: Verify kerb1 Key Synchronization

**Hypothesis**: The kerb1 symmetric key is not properly synced to the App Registration.

**Investigation**: Checked `Get-AzADAppCredential` for the AADKERB app registration — found 0 passwordCredentials on the Application object.

**Conclusion at the time**: Assumed the kerb1 key was never synced. This was **wrong** — the key was actually on the **Service Principal** as a `keyCredential` (type: Symmetric, usage: Encrypt), not as a `passwordCredential` on the Application. This is the correct behavior when Azure creates the AADKERB configuration.

### Attempt 2: Manual kerb1 Password Sync

Tried multiple approaches to manually set the kerb1-derived password as a `passwordCredential` on the Application:

1. **Az PowerShell `New-AzADAppCredential`** — `SecretText` property is read-only; Graph API generates server-side passwords and ignores client-provided secret values
2. **Azure CLI `az ad app credential reset --password`** — Same limitation; CLI wraps Graph API which enforces server-generated passwords
3. **Graph API `PATCH /applications/{id}`** — Setting `passwordCredentials[].secretText` is rejected; `secretText` is output-only
4. **Reflection on .NET objects** — Attempted to set private backing field `_secretText` via reflection; field didn't exist in the model class

**Conclusion**: It is impossible to manually set a specific password value on an App Registration via Graph API. The password is always server-generated. **This is by design** — and the kerb1 key does NOT need to be a passwordCredential on the App. It's correctly placed as a Symmetric keyCredential on the Service Principal.

### Attempt 3: Clean AADKERB Reset

Disabled and re-enabled AADKERB to generate a fresh App Registration and Service Principal:

```powershell
# Disable
Set-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" `
    -EnableAzureActiveDirectoryKerberosForFile $false

# Delete stale app registration manually (optional)

# Re-enable
Set-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" `
    -EnableAzureActiveDirectoryKerberosForFile $true `
    -ActiveDirectoryDomainName "azurelocal.cloud" `
    -ActiveDirectoryDomainGuid "604d3138-c7b3-481d-928f-e4a5dfb0f528"
```

**Result**: New App Registration created with appId `10415207-9065-4169-9f46-132405ad439e`. Service Principal has 1 Symmetric keyCredential (kerb1). Still failed with same error — because the three missing configuration steps still weren't applied.

### Attempt 4: Microsoft Official Documentation Research (Breakthrough)

Searched and fetched the complete Microsoft Learn documentation for Azure Files Entra Kerberos authentication. Found three critical steps that were missing — all mandatory for cloud-only identity scenarios.

---

## Root Cause — Three Missing Configuration Steps

The Microsoft documentation at `https://learn.microsoft.com/azure/storage/files/storage-files-identity-auth-hybrid-identities-enable` and `https://learn.microsoft.com/en-us/entra/identity/authentication/kerberos` describe three requirements that are **not part of the basic AADKERB enable flow** and are easy to miss:

| # | Missing Step | Why It's Needed |
|---|-------------|-----------------|
| 1 | Admin consent for `openid`, `profile`, `User.Read` API permissions on the AADKERB app | The App Registration requests these Microsoft Graph delegated permissions, but without an admin consent grant, the Kerberos token exchange cannot retrieve the user's identity claims |
| 2 | Tag `kdc_enable_cloud_group_sids` on the App Registration | For cloud-only identities (no on-prem AD sync), group SIDs must be included in the Kerberos ticket. Without this tag, the storage account cannot evaluate group-based RBAC and denies access |
| 3 | `DefaultSharePermission` set on the storage account | Cloud-only identities cannot use individual NTFS-style permissions on the share. A default share-level permission must be configured as the fallback authorization mechanism |

**All three must be applied together. Any one missing will cause authentication failure.**

---

## Fix 1 — Admin Consent for API Permissions

### Problem

The AADKERB App Registration has `requiredResourceAccess` for Microsoft Graph delegated permissions (`openid`, `profile`, `User.Read`), but no `oauth2PermissionGrant` existed in the tenant. Without admin consent, the app cannot use these permissions during the Kerberos authentication flow.

### Fix

Grant tenant-wide admin consent via Microsoft Graph API:

```powershell
# Get the AADKERB app's Service Principal
$appId = "10415207-9065-4169-9f46-132405ad439e"
$spResponse = Invoke-AzRestMethod -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'"
$spId = ($spResponse.Content | ConvertFrom-Json).value[0].id

# Microsoft Graph resource Service Principal ID
$graphSpId = "5c4f8cdf-d9c0-4cb4-a6c4-ec85c327a5fe"

# Create the consent grant
$consentBody = @{
    clientId    = $spId
    consentType = "AllPrincipals"
    resourceId  = $graphSpId
    scope       = "openid profile User.Read"
} | ConvertTo-Json

Invoke-AzRestMethod -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" `
    -Payload $consentBody
```

### Verification

```powershell
$grants = Invoke-AzRestMethod -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$spId'"
# Should show: scope = "openid profile User.Read", consentType = "AllPrincipals"
```

---

## Fix 2 — Cloud-Only Groups Tag on App Registration

### Problem

For cloud-only identities (where users are not synced from on-premises AD), the Kerberos ticket does not include group SIDs by default. The storage account's RBAC assignments reference Entra ID groups, and without group SIDs in the ticket, authorization fails.

Microsoft documents this requirement specifically for cloud-only identity scenarios: the app registration must have the tag `kdc_enable_cloud_group_sids` in its manifest.

### Fix

Add the tag via Microsoft Graph API:

```powershell
$appObjectId = "6ee0ce5a-35d2-4c26-8276-d78b1b7d84be"  # Application object ID (not appId)

# Get current tags
$appResp = Invoke-AzRestMethod -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId"
$currentTags = ($appResp.Content | ConvertFrom-Json).tags
if (-not $currentTags) { $currentTags = @() }

# Add the cloud group SIDs tag
$newTags = @($currentTags) + @("kdc_enable_cloud_group_sids") | Select-Object -Unique
$tagBody = @{ tags = $newTags } | ConvertTo-Json

Invoke-AzRestMethod -Method PATCH `
    -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
    -Payload $tagBody
```

### Verification

```powershell
$appCheck = Invoke-AzRestMethod -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId?`$select=tags"
($appCheck.Content | ConvertFrom-Json).tags
# Should include: "kdc_enable_cloud_group_sids"
```

---

## Fix 3 — Default Share-Level Permission

### Problem

When using cloud-only identities with AADKERB, individual RBAC assignments on the file share are not sufficient on their own. Azure Files requires a `DefaultSharePermission` to be set on the storage account as the fallback authorization for SMB access.

Without this, even though the `azlc-avd-fslogix-users` group has `Storage File Data SMB Share Contributor` assigned, the authentication flow rejects the connection.

### Fix

Set the default share-level permission via Azure CLI:

```powershell
az storage account update `
    --name stazlcavdfslogixeus `
    --resource-group rg-azlc-avd-storage-eus `
    --default-share-permission StorageFileDataSmbShareContributor
```

Or via Az PowerShell:

```powershell
Set-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" `
    -DefaultSharePermission StorageFileDataSmbShareContributor
```

### Valid Values

| Value | Meaning |
|-------|---------|
| `StorageFileDataSmbShareReader` | Read-only |
| `StorageFileDataSmbShareContributor` | Read/write/delete (standard for FSLogix) |
| `StorageFileDataSmbShareElevatedContributor` | Read/write/delete + modify ACLs |
| `None` | No default (requires explicit share-level role for every user) |

### Verification

```powershell
$sa = Get-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" -Name "stazlcavdfslogixeus"
$sa.AzureFilesIdentityBasedAuth.DefaultSharePermission
# Should return: StorageFileDataSmbShareContributor
```

---

## Verification and Proof

After applying all three fixes and rebooting the VM:

### FSLogix Log — Successful Profile Load

```
LogonStage = '5'(Logon_Complete)
```

The FSLogix profile log showed:
- Session begin with profile container mount
- VHD attached successfully
- Folder redirections created (Desktop, Documents, etc.)
- `Mirror success` entries for profile data sync
- `LogonStage = 5` (Logon_Complete) — full success

### Profile Container on Azure Files

Share path: `\\stazlcavdfslogixeus.file.core.windows.net\fslogix`

Directory: `KristopherTurner_S-1-12-1-817207761-1111759829-1452962451-820446406`

| File | Size |
|------|------|
| `Profile_KristopherTurner.VHDX` | 196 MiB |
| `Profile_KristopherTurner.VHDX.metadata` | 272 B |

The `FlipFlopProfileDirectoryName = 1` setting produces the `UserName_SID` directory format (instead of the default `SID_UserName`).

---

## Key Learnings and Gotchas

### 1. The kerb1 Key Lives on the Service Principal, Not the App Registration

When you enable AADKERB, Azure creates:
- An **App Registration** (Application object) — holds `identifierUris`, `requiredResourceAccess`, `tags`
- A **Service Principal** — holds the actual `keyCredential` (type: Symmetric, usage: Encrypt) which IS the kerb1 key

Checking `Get-AzADAppCredential` on the Application will show 0 credentials. This is **normal**. The credential is on the Service Principal. To verify:

```powershell
$sp = Invoke-AzRestMethod -Method GET `
    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/{spObjectId}?`$select=keyCredentials"
($sp.Content | ConvertFrom-Json).keyCredentials
# Should show 1 entry: type=Symmetric, usage=Encrypt
```

### 2. You Cannot Manually Set passwordCredentials via Graph API

Microsoft Graph API enforces server-generated passwords. The `secretText` field on `passwordCredential` is output-only. There is no supported method to set a specific password value on an App Registration. Do not waste time attempting `az ad app credential reset --password`, `PATCH /applications`, or reflection hacks — they will all fail or be silently ignored.

### 3. Cloud-Only Identities Require Extra Steps

The basic AADKERB enable flow (`Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile $true`) is designed for hybrid environments where users are synced from on-prem AD. For **cloud-only** environments:

- Admin consent is not auto-granted
- Group SIDs are not included in Kerberos tickets by default
- Default share permissions are not set automatically

All three must be configured manually after enabling AADKERB.

### 4. The Enable Command Does Not Set DefaultSharePermission

`Set-AzStorageAccount -EnableAzureActiveDirectoryKerberosForFile $true` leaves `DefaultSharePermission` as `null`. This must be set separately. The documentation mentions this, but it's in a different section from the enable steps.

### 5. Conditional Access / MFA Is Not Required for This Flow

Verified: 0 Conditional Access policies exist in this tenant. If CA policies with MFA requirements existed, they could potentially interfere with the Kerberos ticket acquisition. Not a factor here, but worth checking in other environments.

### 6. App Management Policies Do Not Block This

The default app management policy was enabled in the tenant but had no restrictions on `passwordCredentials` or `keyCredentials`. Not a factor, but something to verify if you encounter credential-related issues in locked-down tenants.

---

## Maintenance — kerb1 Key Rotation

The Service Principal's Symmetric keyCredential (kerb1 key) expires periodically (default: ~6 months). Per Microsoft documentation, you must rotate it before expiry or authentication will silently fail.

**Current expiry**: May 20, 2026

### Rotation Procedure

```powershell
# Regenerate the kerb1 key on the storage account
New-AzStorageAccountKey -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" -KeyName kerb1

# Update the Service Principal credential
# The Set-AzStorageAccount re-enable flow handles this:
Set-AzStorageAccount -ResourceGroupName "rg-azlc-avd-storage-eus" `
    -Name "stazlcavdfslogixeus" `
    -EnableAzureActiveDirectoryKerberosForFile $true `
    -ActiveDirectoryDomainName "azurelocal.cloud" `
    -ActiveDirectoryDomainGuid "604d3138-c7b3-481d-928f-e4a5dfb0f528"
```

Alternatively, use the `AzFilesHybrid` PowerShell module's `Update-AzStorageAccountAuthForAES256` if available.

**Set a calendar reminder for key rotation before expiry.**

---

## Complete Configuration Reference

### Final State of Storage Account Authentication

```
DirectoryServiceOptions: AADKERB
ActiveDirectoryProperties:
  DomainName: azurelocal.cloud
  DomainGuid: 604d3138-c7b3-481d-928f-e4a5dfb0f528
DefaultSharePermission: StorageFileDataSmbShareContributor
```

### Final State of AADKERB App Registration

```
Display Name: [Storage Account] stazlcavdfslogixeus.file.core.windows.net
Application ID: 10415207-9065-4169-9f46-132405ad439e
Object ID: 6ee0ce5a-35d2-4c26-8276-d78b1b7d84be

Tags: ["kdc_enable_cloud_group_sids"]

Required Resource Access:
  - Microsoft Graph (delegated): openid, profile, User.Read

IdentifierUris:
  - api://604d3138-.../host/stazlcavdfslogixeus.file.core.windows.net
  - api://604d3138-.../cifs/stazlcavdfslogixeus.file.core.windows.net
  - api://604d3138-.../http/stazlcavdfslogixeus.file.core.windows.net
  - host/stazlcavdfslogixeus.file.core.windows.net
  - cifs/stazlcavdfslogixeus.file.core.windows.net
  - http/stazlcavdfslogixeus.file.core.windows.net
```

### Final State of Service Principal

```
Object ID: 135692c8-1895-44e2-b657-8812f446b48e
KeyCredentials: 1 (type: Symmetric, usage: Encrypt — this is the kerb1 key)
Expiry: 2026-05-20
```

### OAuth2PermissionGrant

```
Client: 135692c8-1895-44e2-b657-8812f446b48e (AADKERB SP)
Resource: 5c4f8cdf-d9c0-4cb4-a6c4-ec85c327a5fe (Microsoft Graph SP)
Scope: openid profile User.Read
ConsentType: AllPrincipals
```

### VM Registry Configuration

```
HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 1
HKLM:\SOFTWARE\FSLogix\Profiles\VHDLocations = \\stazlcavdfslogixeus.file.core.windows.net\fslogix
HKLM:\SOFTWARE\FSLogix\Profiles\VolumeType = VHDX
HKLM:\SOFTWARE\FSLogix\Profiles\SizeInMBs = 30720
HKLM:\SOFTWARE\FSLogix\Profiles\FlipFlopProfileDirectoryName = 1
HKLM:\SOFTWARE\FSLogix\Profiles\DeleteLocalProfileWhenVHDShouldApply = 1
HKLM:\SOFTWARE\FSLogix\Profiles\PreventLoginWithFailure = 0
HKLM:\SOFTWARE\FSLogix\Profiles\PreventLoginWithTempProfile = 0
HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters\CloudKerberosTicketRetrievalEnabled = 1
```

### Share RBAC

| Group | Role |
|-------|------|
| `azlc-avd-fslogix-users` | Storage File Data SMB Share Contributor |
| `azlc-avd-fslogix-ops` | Storage File Data SMB Share Elevated Contributor |

---

## Microsoft Learn References

1. [Enable Microsoft Entra Kerberos authentication for Azure Files](https://learn.microsoft.com/azure/storage/files/storage-files-identity-auth-hybrid-identities-enable) — Main AADKERB setup guide, includes admin consent and default share permission steps
2. [Microsoft Entra Kerberos authentication overview](https://learn.microsoft.com/en-us/entra/identity/authentication/kerberos) — Documents the `kdc_enable_cloud_group_sids` tag requirement for cloud-only identities
3. [Troubleshoot Azure Files SMB authentication](https://learn.microsoft.com/troubleshoot/azure/azure-storage/files/security/files-troubleshoot-smb-authentication) — Error code reference and `Debug-AzStorageAccountAuth` diagnostic tool
4. [FSLogix profile container configuration](https://learn.microsoft.com/fslogix/reference-configuration-settings) — Registry settings reference
5. [Azure Files identity-based access overview](https://learn.microsoft.com/azure/storage/files/storage-files-active-directory-overview) — Architecture overview of AADKERB vs AD DS vs Entra Domain Services
