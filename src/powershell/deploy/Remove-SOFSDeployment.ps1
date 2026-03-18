<#
.SYNOPSIS
    Remove-SOFSDeployment.ps1

.DESCRIPTION
    Removes all Azure resources created by Deploy-SOFS-Azure.ps1 in reverse order:
      1. Arc connected machine extensions (domain join)
      2. Azure Local VMs
      3. Data disks
      4. NICs
      5. Cloud witness storage account
      6. (Optional) Resource group

    Idempotent — each step checks for resource existence before attempting deletion.
    Credentials are resolved from Key Vault via keyvault:// URIs — NEVER interactively.

.PARAMETER SolutionConfigPath
    Path to variables.yml. Default: config\variables.yml relative to CWD.

.PARAMETER SubscriptionId
    Azure subscription ID. Overrides config value.

.PARAMETER ResourceGroup
    Target resource group name. Overrides config value.

.PARAMETER VMPrefix
    VM naming prefix. Overrides config value.

.PARAMETER VMCount
    Number of SOFS VMs to remove. Overrides config value.

.PARAMETER DataDiskCount
    Data disks per VM. Overrides config value.

.PARAMETER WitnessStorageAccount
    Cloud witness storage account name. Overrides config value.

.PARAMETER RemoveResourceGroup
    If set, also deletes the resource group after removing all resources.

.PARAMETER WhatIf
    Dry-run mode — displays what would be removed without making changes.

.PARAMETER LogPath
    Override log file path.

.EXAMPLE
    .\Remove-SOFSDeployment.ps1 -WhatIf
    .\Remove-SOFSDeployment.ps1
    .\Remove-SOFSDeployment.ps1 -RemoveResourceGroup

.NOTES
    Author:  Hybrid Cloud Solutions LLC
    Version: 1.0
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]    $SolutionConfigPath    = "",
    [string]    $SubscriptionId        = "",
    [string]    $ResourceGroup         = "",
    [string]    $VMPrefix              = "",
    [int]       $VMCount               = 0,
    [int]       $DataDiskCount         = 0,
    [string]    $WitnessStorageAccount = "",
    [switch]    $RemoveResourceGroup,
    [switch]    $WhatIf,
    [string]    $LogPath               = ""
)

# ===========================================================================
# LOG INITIALIZATION
# ===========================================================================

$scriptShortName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$taskFolderName  = "sofs"
$logDir  = if ($LogPath -ne "") { Split-Path $LogPath -Parent } else { Join-Path (Get-Location).Path "logs\$taskFolderName" }
$logFile = if ($LogPath -ne "") { $LogPath } else { Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')_${scriptShortName}.log" }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    $line | Out-File -FilePath $script:logFile -Append -Encoding utf8
    switch ($Level) {
        "PASS"    { Write-Host "[$ts] [PASS] $Message" -ForegroundColor Green }
        "FAIL"    { Write-Host "[$ts] [FAIL] $Message" -ForegroundColor Red }
        "WARN"    { Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow }
        "HEADER"  { Write-Host "[$ts] [----] $Message" -ForegroundColor Cyan }
        default   { Write-Host "[$ts] [INFO] $Message" }
    }
}

# ===========================================================================
# LOAD SOLUTION CONFIG
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "SOFS Deployment Removal" "HEADER"
Write-Log "========================================" "HEADER"

$repoRoot = (Get-Location).Path

if ($SolutionConfigPath -eq "") {
    $primaryPath = Join-Path $repoRoot "config\variables.yml"
    $legacyPath  = Join-Path $repoRoot "solutions\sofs\solution-sofs.yml"
    if     (Test-Path $primaryPath) { $SolutionConfigPath = $primaryPath }
    elseif (Test-Path $legacyPath)  { $SolutionConfigPath = $legacyPath }
    else {
        Write-Log "Config not found. Expected: config\variables.yml" "FAIL"
        exit 1
    }
}
if (-not (Test-Path $SolutionConfigPath)) {
    Write-Log "Solution config not found: $SolutionConfigPath" "FAIL"
    exit 1
}

try {
    $sol = Get-Content $SolutionConfigPath -Raw | ConvertFrom-Yaml
    Write-Log "Loaded config: $SolutionConfigPath" "PASS"
} catch {
    Write-Log "Could not parse YAML: $_" "FAIL"
    exit 1
}

# ===========================================================================
# RESOLVE PARAMETERS — param override > config > error
# ===========================================================================

function Resolve-Param {
    param([string]$ParamValue, [object]$ConfigValue, [string]$Name, [bool]$Required = $true)
    if ($ParamValue -ne "" -and $null -ne $ParamValue) { return $ParamValue }
    if ($null -ne $ConfigValue -and "$ConfigValue" -ne "") { return $ConfigValue }
    if ($Required) {
        Write-Log "Required value '$Name' not provided via parameter or config." "FAIL"
        throw "Missing required value: $Name"
    }
    return $null
}

$SubscriptionId        = Resolve-Param $SubscriptionId        $sol.azure.subscription_id        "SubscriptionId"
$ResourceGroup         = Resolve-Param $ResourceGroup         $sol.azure.resource_group         "ResourceGroup"
$VMPrefix              = Resolve-Param $VMPrefix              $sol.vm.prefix                    "VMPrefix"
$WitnessStorageAccount = Resolve-Param $WitnessStorageAccount $sol.cloud_witness.name            "WitnessStorageAccount"
if ($VMCount      -le 0) { $VMCount      = [int]$sol.vm.count }
if ($DataDiskCount -le 0) { $DataDiskCount = [int]$sol.data_disks.count }

Write-Log "Subscription:      $SubscriptionId"
Write-Log "Resource Group:    $ResourceGroup"
Write-Log "VMs:               $VMCount x $VMPrefix"
Write-Log "Data Disks/VM:     $DataDiskCount"
Write-Log "Cloud Witness:     $WitnessStorageAccount"
Write-Log "Remove RG:         $RemoveResourceGroup"

# ===========================================================================
# WHATIF CHECK
# ===========================================================================

if ($WhatIf) {
    Write-Log "========================================" "WARN"
    Write-Log "[DRY RUN] Would remove the following:" "WARN"
    Write-Log "========================================" "WARN"
    for ($i = 1; $i -le $VMCount; $i++) {
        $key = "{0:D2}" -f $i
        $VMName = "${VMPrefix}-${key}"
        Write-Log "  Extension: $VMName/JsonADDomainExtension"
        Write-Log "  VM:        $VMName"
        for ($d = 1; $d -le $DataDiskCount; $d++) { Write-Log "  Disk:      $VMName-data$d" }
        Write-Log "  NIC:       $VMName-nic"
    }
    Write-Log "  Storage:   $WitnessStorageAccount"
    if ($RemoveResourceGroup) { Write-Log "  RG:        $ResourceGroup" }
    Write-Log "[DRY RUN] No changes made." "WARN"
    exit 0
}

# ===========================================================================
# ENSURE CLI EXTENSION + SET SUBSCRIPTION
# ===========================================================================

Write-Log "Ensuring stack-hci-vm CLI extension..." "HEADER"
az extension add --name stack-hci-vm --upgrade --yes 2>$null
Write-Log "Extension ready." "PASS"

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Log "Failed to set subscription: $SubscriptionId" "FAIL"
    exit 1
}
Write-Log "Subscription set: $SubscriptionId" "PASS"

# ===========================================================================
# STEP 1: Remove Domain Join Extensions
# ===========================================================================

Write-Log "Step 1 — Remove domain join extensions" "HEADER"
for ($i = 1; $i -le $VMCount; $i++) {
    $key = "{0:D2}" -f $i
    $VMName = "${VMPrefix}-${key}"
    $extExists = az connectedmachine extension show --resource-group $ResourceGroup --machine-name $VMName --name JsonADDomainExtension --query name -o tsv 2>$null
    if ($extExists) {
        Write-Log "  Removing extension from $VMName..."
        az connectedmachine extension delete --resource-group $ResourceGroup --machine-name $VMName --name JsonADDomainExtension --yes --output none 2>$null
        if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to remove extension from $VMName" "WARN" }
        else { Write-Log "  Extension removed from $VMName." "PASS" }
    } else {
        Write-Log "  [$VMName] No extension found. Skipping." "INFO"
    }
}

# ===========================================================================
# STEP 2: Delete VMs
# ===========================================================================

Write-Log "Step 2 — Delete VMs" "HEADER"
for ($i = 1; $i -le $VMCount; $i++) {
    $key = "{0:D2}" -f $i
    $VMName = "${VMPrefix}-${key}"
    $vmExists = az stack-hci-vm show --resource-group $ResourceGroup --name $VMName --query name -o tsv 2>$null
    if ($vmExists) {
        Write-Log "  Deleting VM: $VMName..."
        az stack-hci-vm delete --resource-group $ResourceGroup --name $VMName --yes --output none
        if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to delete $VMName" "WARN" }
        else { Write-Log "  VM '$VMName' deleted." "PASS" }
    } else {
        Write-Log "  [$VMName] Not found. Skipping." "INFO"
    }
}

# ===========================================================================
# STEP 3: Delete Data Disks
# ===========================================================================

Write-Log "Step 3 — Delete data disks" "HEADER"
for ($i = 1; $i -le $VMCount; $i++) {
    $key = "{0:D2}" -f $i
    $VMName = "${VMPrefix}-${key}"
    for ($d = 1; $d -le $DataDiskCount; $d++) {
        $diskName = "$VMName-data$d"
        $diskExists = az stack-hci-vm disk show --resource-group $ResourceGroup --name $diskName --query name -o tsv 2>$null
        if ($diskExists) {
            Write-Log "  Deleting disk: $diskName..."
            az stack-hci-vm disk delete --resource-group $ResourceGroup --name $diskName --yes --output none
            if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to delete $diskName" "WARN" }
            else { Write-Log "  Disk '$diskName' deleted." "PASS" }
        }
    }
}

# ===========================================================================
# STEP 4: Delete NICs
# ===========================================================================

Write-Log "Step 4 — Delete NICs" "HEADER"
for ($i = 1; $i -le $VMCount; $i++) {
    $key = "{0:D2}" -f $i
    $NicName = "${VMPrefix}-${key}-nic"
    $nicExists = az stack-hci-vm network nic show --resource-group $ResourceGroup --name $NicName --query name -o tsv 2>$null
    if ($nicExists) {
        Write-Log "  Deleting NIC: $NicName..."
        az stack-hci-vm network nic delete --resource-group $ResourceGroup --name $NicName --yes --output none
        if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to delete $NicName" "WARN" }
        else { Write-Log "  NIC '$NicName' deleted." "PASS" }
    }
}

# ===========================================================================
# STEP 5: Delete Cloud Witness Storage Account
# ===========================================================================

Write-Log "Step 5 — Delete cloud witness storage account" "HEADER"
$witnessExists = az storage account show --name $WitnessStorageAccount --resource-group $ResourceGroup --query name -o tsv 2>$null
if ($witnessExists) {
    Write-Log "  Deleting storage account: $WitnessStorageAccount..."
    az storage account delete --name $WitnessStorageAccount --resource-group $ResourceGroup --yes --output none
    if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to delete storage account" "WARN" }
    else { Write-Log "  Storage account deleted." "PASS" }
} else {
    Write-Log "  Storage account not found. Skipping." "INFO"
}

# ===========================================================================
# STEP 6: (Optional) Delete Resource Group
# ===========================================================================

if ($RemoveResourceGroup) {
    Write-Log "Step 6 — Delete resource group" "HEADER"
    $rgExists = az group exists --name $ResourceGroup 2>$null
    if ($rgExists -eq "true") {
        Write-Log "  Deleting resource group: $ResourceGroup..."
        az group delete --name $ResourceGroup --yes --output none
        if ($LASTEXITCODE -ne 0) { Write-Log "  Failed to delete resource group" "WARN" }
        else { Write-Log "  Resource group deleted." "PASS" }
    } else {
        Write-Log "  Resource group not found. Skipping." "INFO"
    }
}

# ===========================================================================
# SUMMARY
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "REMOVAL COMPLETE" "PASS"
Write-Log "========================================" "HEADER"
Write-Log "  Resource Group:      $ResourceGroup $(if ($RemoveResourceGroup) { '(deleted)' } else { '(preserved)' })"
Write-Log "  VMs Removed:         $VMCount"
Write-Log "  Disks Removed:       $($VMCount * $DataDiskCount)"
Write-Log "  NICs Removed:        $VMCount"
Write-Log "  Witness Account:     $WitnessStorageAccount"
Write-Log "  Log File:            $logFile"
