<#
.SYNOPSIS
    Validates that the SOFS deployment is correctly configured and functional.

.DESCRIPTION
    Comprehensive post-deployment validator for all 10 SOFS scenarios.
    Performs the following checks:
      1. SMB share reachability on the SOFS access point.
      2. SMB share settings (CA, encryption, caching mode).
      3. NTFS permissions (CREATOR OWNER, Domain Users, Domain Admins, SYSTEM).
      4. Anti-affinity rule verification on the host cluster.
      5. S2D health (pool, virtual disks, physical disks).
      6. Cluster health (nodes, groups, quorum).
      7. Write access test.
      8. (Optional) FSLogix registry settings on the local machine.

    Supports both Single layout (single share) and Triple layout (three shares).

.PARAMETER SOFSAccessPoint
    SOFS client access point name (e.g., "FSLogixSOFS").

.PARAMETER ShareNames
    Array of share names to validate.
    Single layout: @("FSLogix")
    Triple layout: @("Profiles", "ODFC", "AppData")

.PARAMETER ClusterName
    Failover cluster name for S2D and cluster health checks.

.PARAMETER DomainNetBIOS
    NetBIOS domain name for NTFS permission verification (e.g., "IIC").

.PARAMETER HostClusterName
    Azure Local host cluster name for anti-affinity checks (optional).

.PARAMETER AntiAffinityRuleName
    Anti-affinity rule name to verify (default: "SOFS-AntiAffinity").

.PARAMETER ExpectedNodeCount
    Expected number of SOFS cluster nodes (default: 3). Range: 2–16.

.PARAMETER ExpectedDataCopies
    Expected S2D resiliency (2 = two-way mirror, 3 = three-way mirror).

.EXAMPLE
    # Single layout — single share
    .\Test-SOFSDeployment.ps1 -SOFSAccessPoint "FSLogixSOFS" -ShareNames @("FSLogix") `
        -ClusterName "sofs-cluster" -DomainNetBIOS "IIC"

.EXAMPLE
    # Triple layout — three shares
    .\Test-SOFSDeployment.ps1 -SOFSAccessPoint "FSLogixSOFS" `
        -ShareNames @("Profiles", "ODFC", "AppData") `
        -ClusterName "sofs-cluster" -DomainNetBIOS "IIC"

.OUTPUTS
    PSCustomObject with 'Passed' boolean and 'Results' array.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$SOFSAccessPoint,

    [Parameter(Mandatory)]
    [string[]]$ShareNames,

    [Parameter(Mandatory)]
    [string]$ClusterName,

    [Parameter(Mandatory)]
    [string]$DomainNetBIOS,

    [string]$HostClusterName,

    [string]$AntiAffinityRuleName = "SOFS-AntiAffinity",

    [ValidateRange(2, 16)]
    [int]$ExpectedNodeCount = 3,

    [ValidateSet(2, 3)]
    [int]$ExpectedDataCopies = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$results  = [System.Collections.Generic.List[PSCustomObject]]::new()
$allPassed = $true

function Add-Result {
    param([string]$Check, [bool]$Passed, [string]$Detail)
    $results.Add([PSCustomObject]@{
        Check  = $Check
        Passed = $Passed
        Detail = $Detail
    })
    if (-not $Passed) { $script:allPassed = $false }
    $icon = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "$icon $Check : $Detail" -ForegroundColor $color
}

$shareCount = $ShareNames.Count
$layout = if ($shareCount -eq 1) { "Single layout (single share)" } else { "Triple layout ($shareCount shares)" }

Write-Host "=== SOFS E2E Validation ===" -ForegroundColor Cyan
Write-Host "  Access Point : $SOFSAccessPoint"
Write-Host "  Layout       : $layout"
Write-Host "  Shares       : $($ShareNames -join ', ')"
Write-Host "  Cluster      : $ClusterName"
Write-Host "  Expected VMs : $ExpectedNodeCount"
Write-Host "  Resiliency   : ${ExpectedDataCopies}-way mirror"
Write-Host ""

# ============================================================================
# 1. SMB Share Checks (per share)
# ============================================================================
foreach ($shareName in $ShareNames) {
    Write-Host "--- Share: $shareName ---" -ForegroundColor Yellow

    # UNC path reachable
    $uncPath = "\\$SOFSAccessPoint\$shareName"
    $reachable = Test-Path -Path $uncPath -ErrorAction SilentlyContinue
    Add-Result -Check "[$shareName] UNC reachable" -Passed ([bool]$reachable) -Detail $uncPath

    # SMB share settings
    $share = Get-SmbShare -Name $shareName -ScopeName $SOFSAccessPoint -ErrorAction SilentlyContinue
    if ($share) {
        Add-Result -Check "[$shareName] SMB share exists" -Passed $true `
                   -Detail "ScopeName=$($share.ScopeName)"
        Add-Result -Check "[$shareName] ContinuouslyAvailable" `
                   -Passed ($share.ContinuouslyAvailable -eq $true) `
                   -Detail "CA=$($share.ContinuouslyAvailable)"
        Add-Result -Check "[$shareName] CachingMode=None" `
                   -Passed ($share.CachingMode -eq 'None') `
                   -Detail "CachingMode=$($share.CachingMode)"
        Add-Result -Check "[$shareName] Encryption" `
                   -Passed ($share.EncryptData -eq $true) `
                   -Detail "EncryptData=$($share.EncryptData)"
    }
    else {
        Add-Result -Check "[$shareName] SMB share exists" -Passed $false `
                   -Detail "Share '$shareName' not found on scope '$SOFSAccessPoint'"
    }

    # Write access test
    if ($reachable) {
        $testFile = Join-Path $uncPath ".e2e_test_$(Get-Random)"
        try {
            [System.IO.File]::WriteAllText($testFile, "e2e-validation")
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            Add-Result -Check "[$shareName] Write access" -Passed $true -Detail "OK"
        }
        catch {
            Add-Result -Check "[$shareName] Write access" -Passed $false -Detail $_.Exception.Message
        }
    }

    # NTFS permission checks
    if ($reachable) {
        try {
            $acl = Get-Acl -Path $uncPath
            $aceIdentities = $acl.Access | ForEach-Object { $_.IdentityReference.Value }

            $expectedAces = @(
                "CREATOR OWNER",
                "$DomainNetBIOS\Domain Users",
                "$DomainNetBIOS\Domain Admins",
                "NT AUTHORITY\SYSTEM"
            )
            foreach ($ace in $expectedAces) {
                $found = $aceIdentities -contains $ace
                Add-Result -Check "[$shareName] NTFS ACE: $ace" -Passed $found `
                           -Detail $(if ($found) { "Present" } else { "Missing" })
            }
        }
        catch {
            Add-Result -Check "[$shareName] NTFS permissions" -Passed $false -Detail $_.Exception.Message
        }
    }
}

# ============================================================================
# 2. Cluster Health
# ============================================================================
Write-Host "--- Cluster Health ---" -ForegroundColor Yellow

try {
    $nodes = Get-ClusterNode -Cluster $ClusterName
    Add-Result -Check "Cluster node count" `
               -Passed ($nodes.Count -eq $ExpectedNodeCount) `
               -Detail "Expected=$ExpectedNodeCount, Actual=$($nodes.Count)"

    $allUp = ($nodes | Where-Object { $_.State -ne 'Up' }).Count -eq 0
    Add-Result -Check "All cluster nodes Up" -Passed $allUp `
               -Detail ($nodes | ForEach-Object { "$($_.Name)=$($_.State)" }) -join ", "

    $quorum = Get-ClusterQuorum -Cluster $ClusterName
    $isCloud = $quorum.QuorumResource.ResourceType.Name -eq 'Cloud Witness'
    Add-Result -Check "Cloud Witness configured" -Passed $isCloud `
               -Detail "QuorumType=$($quorum.QuorumResource.ResourceType.Name)"
}
catch {
    Add-Result -Check "Cluster health" -Passed $false -Detail $_.Exception.Message
}

# ============================================================================
# 3. S2D Health
# ============================================================================
Write-Host "--- S2D Health ---" -ForegroundColor Yellow

try {
    $pool = Get-StoragePool -CimSession $ClusterName |
            Where-Object { $_.IsPrimordial -eq $false }
    if ($pool) {
        Add-Result -Check "S2D pool healthy" `
                   -Passed ($pool.HealthStatus -eq 'Healthy') `
                   -Detail "HealthStatus=$($pool.HealthStatus)"
    }
    else {
        Add-Result -Check "S2D pool exists" -Passed $false -Detail "No non-primordial pool found"
    }

    $vdisks = Get-VirtualDisk -CimSession $ClusterName
    foreach ($vd in $vdisks) {
        Add-Result -Check "VDisk [$($vd.FriendlyName)] healthy" `
                   -Passed ($vd.HealthStatus -eq 'Healthy') `
                   -Detail "Health=$($vd.HealthStatus), Copies=$($vd.NumberOfDataCopies)"
        Add-Result -Check "VDisk [$($vd.FriendlyName)] resiliency" `
                   -Passed ($vd.NumberOfDataCopies -eq $ExpectedDataCopies) `
                   -Detail "Expected=$ExpectedDataCopies, Actual=$($vd.NumberOfDataCopies)"
    }
}
catch {
    Add-Result -Check "S2D health" -Passed $false -Detail $_.Exception.Message
}

# ============================================================================
# 4. Anti-Affinity (optional — requires HostClusterName)
# ============================================================================
if ($HostClusterName) {
    Write-Host "--- Anti-Affinity ---" -ForegroundColor Yellow

    try {
        $rule = Get-ClusterAffinityRule -Name $AntiAffinityRuleName -Cluster $HostClusterName -ErrorAction SilentlyContinue
        Add-Result -Check "Anti-affinity rule exists" `
                   -Passed ($null -ne $rule) `
                   -Detail "Rule=$AntiAffinityRuleName"

        # Check that VMs are on separate physical nodes
        $groups = Get-ClusterGroup -Cluster $HostClusterName |
                  Where-Object { $_.Name -like "*sofs*" }
        $ownerNodes = $groups | Select-Object -ExpandProperty OwnerNode -Unique
        $allSeparate = $ownerNodes.Count -eq $groups.Count
        Add-Result -Check "VMs on separate hosts" `
                   -Passed $allSeparate `
                   -Detail "$($groups.Count) VMs on $($ownerNodes.Count) distinct hosts"
    }
    catch {
        Add-Result -Check "Anti-affinity" -Passed $false -Detail $_.Exception.Message
    }
}

# ============================================================================
# 5. FSLogix Registry (informational — optional)
# ============================================================================
$regPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
if (Test-Path $regPath) {
    $enabled = (Get-ItemProperty $regPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    Add-Result -Check "FSLogix Enabled (local)" -Passed ($enabled -eq 1) -Detail "Enabled=$enabled"

    $vhdLocation = (Get-ItemProperty $regPath -Name "VHDLocations" -ErrorAction SilentlyContinue).VHDLocations
    $locationMatch = $vhdLocation -like "*$SOFSAccessPoint*"
    Add-Result -Check "FSLogix VHDLocations (local)" -Passed $locationMatch -Detail "VHDLocations=$vhdLocation"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
$passCount = ($results | Where-Object { $_.Passed }).Count
$failCount = ($results | Where-Object { -not $_.Passed }).Count
$summary = if ($allPassed) { "ALL $($results.Count) CHECKS PASSED" } else { "$failCount of $($results.Count) CHECKS FAILED" }
$summaryColor = if ($allPassed) { "Green" } else { "Red" }
Write-Host "=== $summary ===" -ForegroundColor $summaryColor

return [PSCustomObject]@{
    Passed  = $allPassed
    Results = $results
    Total   = $results.Count
    PassCount = $passCount
    FailCount = $failCount
}
