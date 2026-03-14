<#
.SYNOPSIS
    Configures SMB share permissions and FSLogix-specific settings on the SOFS share.

.DESCRIPTION
    This script:
      1. Sets NTFS and share permissions so that AVD users can read/write their profile VHDs.
      2. Configures SMB share settings optimised for FSLogix (oplocks, leasing, etc.).
      3. Optionally applies registry settings for FSLogix on the local machine (for testing).

.PARAMETER ParametersFile
    Path to a parameters.ps1 file. See parameters.example.ps1.

.PARAMETER SOFSName
    SOFS cluster role name (client access point).

.PARAMETER ShareName
    SMB share name.

.PARAMETER SharePath
    Local path on the CSV for the SMB share.

.PARAMETER AVDUsersGroup
    Active Directory group that AVD session host users belong to.

.PARAMETER ClusterName
    Failover cluster name (used to determine a cluster node for remote commands).

.EXAMPLE
    .\Set-FSLogixShare.ps1 -ParametersFile .\parameters.ps1

.NOTES
    Requires RSAT-Clustering tools and domain admin (or delegated) credentials.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile,

    [Parameter(Mandatory = $false)]
    [string]$SOFSName,

    [Parameter(Mandatory = $false)]
    [string]$ShareName,

    [Parameter(Mandatory = $false)]
    [string]$SharePath,

    [Parameter(Mandatory = $false)]
    [string]$AVDUsersGroup,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Load parameters file
if ($ParametersFile) {
    if (-not (Test-Path $ParametersFile)) {
        throw "Parameters file not found: $ParametersFile"
    }
    . $ParametersFile
}

if (-not $SOFSName)      { $SOFSName      = $script:SOFSName }
if (-not $ShareName)     { $ShareName     = $script:ShareName }
if (-not $SharePath)     { $SharePath     = $script:SharePath }
if (-not $AVDUsersGroup) { $AVDUsersGroup = $script:AVDUsersGroup }
if (-not $ClusterName)   { $ClusterName   = $script:ClusterName }
#endregion

foreach ($param in @("SOFSName","ShareName","SharePath","AVDUsersGroup","ClusterName")) {
    if (-not (Get-Variable -Name $param -ValueOnly -ErrorAction SilentlyContinue)) {
        throw "Required parameter '$param' is not set."
    }
}

Write-Host "=== Configuring FSLogix share permissions ===" -ForegroundColor Cyan

$clusterNode = (Get-ClusterNode -Cluster $ClusterName | Select-Object -First 1).Name

Invoke-Command -ComputerName $clusterNode -ScriptBlock {
    param($ShareName, $SOFSName, $SharePath, $AVDUsersGroup)

    #region SMB share permissions
    Write-Host "Setting SMB share permissions..." -ForegroundColor Yellow
    # SilentlyContinue is intentional: 'Everyone' may not exist on new shares and the error is non-fatal.
    Revoke-SmbShareAccess -Name $ShareName -ScopeName $SOFSName -AccountName "Everyone" -Force -ErrorAction SilentlyContinue
    Grant-SmbShareAccess  -Name $ShareName -ScopeName $SOFSName -AccountName $AVDUsersGroup `
                          -AccessRight Full -Force
    Grant-SmbShareAccess  -Name $ShareName -ScopeName $SOFSName -AccountName "CREATOR OWNER" `
                          -AccessRight Full -Force
    Write-Host "  SMB permissions set." -ForegroundColor Green
    #endregion

    #region NTFS permissions (Creator Owner full control on subfolders/files)
    Write-Host "Setting NTFS permissions on $SharePath ..." -ForegroundColor Yellow
    $acl = Get-Acl -Path $SharePath

    # AVD Users – Modify on this folder, subfolders, and files
    $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $AVDUsersGroup,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
         [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($usersRule)

    # CREATOR OWNER – Full Control on subfolders/files only
    $creatorRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "CREATOR OWNER",
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
         [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::InheritOnly,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($creatorRule)

    Set-Acl -Path $SharePath -AclObject $acl
    Write-Host "  NTFS permissions set." -ForegroundColor Green
    #endregion

    #region Optimise SMB share for FSLogix
    Write-Host "Applying SMB optimisation settings..." -ForegroundColor Yellow
    Set-SmbShare -Name $ShareName -ScopeName $SOFSName `
                 -ContinuouslyAvailable $true `
                 -FolderEnumerationMode AccessBased `
                 -EncryptData $true `
                 -Confirm:$false
    Write-Host "  SMB settings applied." -ForegroundColor Green
    #endregion

} -ArgumentList $ShareName, $SOFSName, $SharePath, $AVDUsersGroup

Write-Host ""
Write-Host "=== FSLogix share configuration complete ===" -ForegroundColor Green
