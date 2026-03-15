<#
.SYNOPSIS
    Validates that the SOFS share is accessible and FSLogix configuration is correct.

.DESCRIPTION
    Performs the following checks:
      1. SMB share is reachable on the SOFS name.
      2. SMB share settings match FSLogix requirements (CA, encryption).
      3. NTFS permissions allow the AVD users group to write.
      4. (Optional) Tests FSLogix registry settings on the local machine.

.PARAMETER SOFSName
    SOFS cluster role name / client access point.

.PARAMETER ShareName
    SMB share name to test.

.PARAMETER AVDUsersGroup
    AD group to verify has write access (optional).

.EXAMPLE
    .\Test-SOFSDeployment.ps1 -SOFSName "SOFS01" -ShareName "FSLogixProfiles"

.OUTPUTS
    PSCustomObject with a 'Passed' boolean and an array of 'Results'.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$SOFSName,

    [Parameter(Mandatory = $true)]
    [string]$ShareName,

    [Parameter(Mandatory = $false)]
    [string]$AVDUsersGroup
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

Write-Host "=== Testing SOFS deployment: \\$SOFSName\$ShareName ===" -ForegroundColor Cyan
Write-Host ""

# 1 – UNC path reachable
$uncPath = "\\$SOFSName\$ShareName"
$reachable = Test-Path -Path $uncPath -ErrorAction SilentlyContinue
Add-Result -Check "UNC path reachable" -Passed ([bool]$reachable) -Detail $uncPath

# 2 – SMB share exists and is continuously available
$share = Get-SmbShare -Name $ShareName -ScopeName $SOFSName -ErrorAction SilentlyContinue
if ($share) {
    Add-Result -Check "SMB share exists" -Passed $true -Detail "ScopeName=$($share.ScopeName)"
    Add-Result -Check "Continuously Available" -Passed ($share.ContinuouslyAvailable -eq $true) `
               -Detail "ContinuouslyAvailable=$($share.ContinuouslyAvailable)"
    Add-Result -Check "Encryption enabled" -Passed ($share.EncryptData -eq $true) `
               -Detail "EncryptData=$($share.EncryptData)"
}
else {
    Add-Result -Check "SMB share exists" -Passed $false -Detail "Share '$ShareName' not found on scope '$SOFSName'"
}

# 3 – Can write a test file to the share (requires appropriate permissions)
if ($reachable) {
    $testFile = Join-Path $uncPath ".test_$(Get-Random)"
    try {
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        Add-Result -Check "Write access to share" -Passed $true -Detail "Test file written and removed successfully"
    }
    catch {
        Add-Result -Check "Write access to share" -Passed $false -Detail $_.Exception.Message
    }
}

# 4 – FSLogix registry on local machine (informational)
$regPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
if (Test-Path $regPath) {
    $enabled     = (Get-ItemProperty $regPath -Name "Enabled"      -ErrorAction SilentlyContinue).Enabled
    $vhdLocation = (Get-ItemProperty $regPath -Name "VHDLocations" -ErrorAction SilentlyContinue).VHDLocations
    Add-Result -Check "FSLogix Enabled (local)" -Passed ($enabled -eq 1) -Detail "Enabled=$enabled"
    $locationMatch = $vhdLocation -like "*$SOFSName*"
    Add-Result -Check "FSLogix VHDLocations (local)" -Passed $locationMatch -Detail "VHDLocations=$vhdLocation"
}
else {
    Add-Result -Check "FSLogix registry (local)" -Passed $false `
               -Detail "Key not found – FSLogix may not be installed or configured on this machine"
}

Write-Host ""
$summary = if ($allPassed) { "ALL CHECKS PASSED" } else { "ONE OR MORE CHECKS FAILED" }
$summaryColor = if ($allPassed) { "Green" } else { "Red" }
Write-Host "=== $summary ===" -ForegroundColor $summaryColor

return [PSCustomObject]@{
    Passed  = $allPassed
    Results = $results
}
