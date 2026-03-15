<#
.SYNOPSIS
    Deploy-SOFS-Azure.ps1

.DESCRIPTION
    Deploys all Azure Local resources for the SOFS cluster using Azure CLI:
      - Resource Group (creates if absent)
      - Cloud Witness storage account
      - NICs on compute logical network with static IPs
      - N Azure Local VMs (Windows Server 2025 Datacenter) with per-VM storage paths
      - Data disks per VM for S2D pool (per-VM storage paths)
      - Attaches data disks to VMs

    All parameters default from the generated solution config YAML but can be
    overridden via script parameters for maximum flexibility.
    Credentials are resolved from Key Vault via keyvault:// URIs — NEVER interactively.

.PARAMETER SolutionConfigPath
    Path to solution-sofs.yml. Default: solutions/sofs/solution-sofs.yml relative to CWD.

.PARAMETER Credential
    PSCredential for VM admin. Overrides Key Vault resolution.

.PARAMETER SubscriptionId
    Azure subscription ID. Overrides config value.

.PARAMETER ResourceGroup
    Target resource group name. Overrides config value.

.PARAMETER Location
    Azure region. Overrides config value.

.PARAMETER CustomLocationId
    ARM ID of the Azure Local custom location. Overrides config value.

.PARAMETER LogicalNetworkId
    ARM ID of the logical network for NIC placement. Overrides config value.

.PARAMETER ImageName
    Gallery image name on Azure Local. Overrides config value.

.PARAMETER StoragePathId
    Default storage path ARM ID (used when StoragePathIds is absent). Overrides config value.

.PARAMETER StoragePathIds
    Hashtable of per-VM storage paths keyed by zero-padded index (01, 02, ...). Overrides config value.

.PARAMETER VMPrefix
    VM naming prefix. Overrides config value.

.PARAMETER VMCount
    Number of SOFS VMs to deploy. Overrides config value.

.PARAMETER VMProcessors
    vCPU count per VM. Overrides config value.

.PARAMETER VMMemoryMB
    Memory in MB per VM. Overrides config value.

.PARAMETER DataDiskCount
    Data disks per VM. Overrides config value.

.PARAMETER DataDiskSizeGB
    Size per data disk in GB. Overrides config value.

.PARAMETER WitnessStorageAccount
    Cloud witness storage account name. Overrides config value.

.PARAMETER Tags
    Hashtable of resource tags. Overrides config default.

.PARAMETER VMIPs
    Hashtable of per-VM static IPs keyed by zero-padded index (01, 02, ...). Overrides config value.

.PARAMETER WhatIf
    Dry-run mode — displays what would be deployed without making changes.

.PARAMETER LogPath
    Override log file path.

.EXAMPLE
    .\Deploy-SOFS-Azure.ps1
    .\Deploy-SOFS-Azure.ps1 -WhatIf
    .\Deploy-SOFS-Azure.ps1 -ResourceGroup "rg-sofs-custom" -VMCount 3
    .\Deploy-SOFS-Azure.ps1 -Credential (Get-Credential) -StoragePathIds @{ "01"="..."; "02"="..."; "03"="..." }

.NOTES
    Author:  Hybrid Cloud Solutions LLC
    Version: 3.0
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]       $SolutionConfigPath    = "",       # Path to solution-sofs.yml
    [PSCredential] $Credential            = $null,    # Override credential resolution
    [string]       $SubscriptionId        = "",       # Azure subscription ID
    [string]       $ResourceGroup         = "",       # Target resource group
    [string]       $Location              = "",       # Azure region
    [string]       $CustomLocationId      = "",       # ARM ID of custom location
    [string]       $LogicalNetworkId      = "",       # ARM ID of logical network
    [string]       $ImageName             = "",       # Gallery image name on Azure Local
    [string]       $StoragePathId         = "",       # Default storage path ARM ID
    [hashtable]    $StoragePathIds        = $null,    # Per-VM storage path map {01 = ..., 02 = ...}
    [string]       $VMPrefix              = "",       # VM naming prefix
    [int]          $VMCount               = 0,        # Number of VMs
    [int]          $VMProcessors          = 0,        # vCPU per VM
    [int]          $VMMemoryMB            = 0,        # Memory MB per VM
    [int]          $DataDiskCount         = 0,        # Data disks per VM
    [int]          $DataDiskSizeGB        = 0,        # Size per data disk
    [string]       $WitnessStorageAccount = "",       # Cloud witness storage account name
    [hashtable]    $Tags                  = $null,    # Resource tags
    [hashtable]    $VMIPs                 = $null,    # Per-VM static IPs {01 = ..., 02 = ...}
    [switch]       $WhatIf,                           # Dry-run mode
    [string]       $LogPath               = ""        # Override log file path
)

# ===========================================================================
# LOG INITIALIZATION
# ===========================================================================

$scriptShortName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) -replace '^Invoke-|-Orchestrated$', ''
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
        "VERBOSE" { Write-Verbose "[$ts] $Message" }
        "DEBUG"   { Write-Debug   "[$ts] $Message" }
        default   { Write-Host "[$ts] [INFO] $Message" }
    }
}

# ===========================================================================
# KEY VAULT HELPER
# ===========================================================================

function Resolve-KeyVaultRef {
    param([string]$KvUri)
    if ($KvUri -notmatch '^keyvault://([^/]+)/(.+)$') { Write-Log "  Not a Key Vault URI: $KvUri" "WARN"; return $null }
    $vaultName  = $Matches[1]
    $secretName = $Matches[2]

    if (Get-Module -Name Az.KeyVault -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Write-Log "  Retrieving '$secretName' from '$vaultName' (Az.KeyVault)..."
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText -ErrorAction Stop
            if ($secret) { Write-Log "  Secret retrieved." "PASS"; return $secret }
            Write-Log "  Az.KeyVault returned no secret." "WARN"
        } catch { Write-Log "  Az.KeyVault failed: $_" "WARN" }
        Write-Log "  Falling back to Azure CLI..." "WARN"
    } else {
        Write-Log "  Az.KeyVault module not found — trying Azure CLI..." "WARN"
    }

    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if (-not $azCmd) { Write-Log "  Azure CLI (az) not found." "WARN"; return $null }
        Write-Log "  Retrieving '$secretName' from '$vaultName' (az CLI)..."
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $val    = (& az keyvault secret show --vault-name $vaultName --name $secretName --query value --output tsv --only-show-errors 2>$tmpErr)
        $azErr  = (Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue).Trim()
        Remove-Item $tmpErr -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($val)) {
            $errDetail = if ($azErr) { ": $azErr" } else { " (exit $LASTEXITCODE)" }
            Write-Log "  az CLI failed$errDetail." "WARN"
            return $null
        }
        Write-Log "  Secret retrieved (az CLI)." "PASS"
        return $val
    } catch { Write-Log "  az CLI failed: $_" "WARN"; return $null }
}

# ===========================================================================
# CLI HELPER
# ===========================================================================

function Test-AzCliResult {
    param([string]$Message)
    if ($LASTEXITCODE -ne 0) {
        Write-Log $Message "FAIL"
        throw "ERROR: $Message (exit code: $LASTEXITCODE)"
    }
}

# ===========================================================================
# LOAD SOLUTION CONFIG
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "SOFS Azure Resource Deployment (CLI)" "HEADER"
Write-Log "========================================" "HEADER"

$repoRoot = (Get-Location).Path

if ($SolutionConfigPath -eq "") {
    # Primary: new central config; Fallback: legacy solution config
    $primaryPath = Join-Path $repoRoot "config\variables.yml"
    $legacyPath  = Join-Path $repoRoot "solutions\sofs\solution-sofs.yml"
    if     (Test-Path $primaryPath) { $SolutionConfigPath = $primaryPath }
    elseif (Test-Path $legacyPath)  { $SolutionConfigPath = $legacyPath; Write-Log "Using legacy config path: $legacyPath" "WARN" }
    else {
        Write-Log "Config not found. Expected: config\variables.yml" "FAIL"
        Write-Log "Copy config\variables.example.yml to config\variables.yml and fill in your values." "FAIL"
        exit 1
    }
}
if (-not (Test-Path $SolutionConfigPath)) {
    Write-Log "Solution config not found: $SolutionConfigPath" "FAIL"
    Write-Log "Generate it first: .\tools\Generate-SolutionConfig.ps1 -Solution sofs-azure-local -Environment <env>" "FAIL"
    exit 1
}

try {
    $sol = Get-Content $SolutionConfigPath -Raw | ConvertFrom-Yaml
    Write-Log "Loaded solution config: $SolutionConfigPath" "PASS"
} catch {
    Write-Log "Could not parse solution YAML: $_" "FAIL"
    exit 1
}

# ===========================================================================
# COMPATIBILITY SHIM — map new sectioned config to legacy compute_wsfc keys
# ===========================================================================
# If the config already has a compute_wsfc section (legacy format), use it as-is.
# If it has the new sectioned format (azure, vm, sofs, ...), map to legacy keys
# so all downstream code works unchanged.
# ===========================================================================

if (-not $sol.compute_wsfc -and $sol.azure) {
    Write-Log "Detected new config format — applying compatibility shim..." "INFO"
    $mapped = @{}
    # azure
    $mapped['wsfc_sofs_subscription_id']    = $sol.azure.subscription_id
    $mapped['wsfc_sofs_resource_group']     = $sol.azure.resource_group
    $mapped['wsfc_sofs_location']           = $sol.azure.location
    # azure_local
    $mapped['wsfc_sofs_custom_location_id'] = $sol.azure_local.custom_location_id
    $mapped['wsfc_sofs_logical_network_id'] = $sol.azure_local.logical_network_id
    $mapped['wsfc_sofs_gallery_image_name'] = $sol.azure_local.gallery_image_name
    $mapped['wsfc_sofs_storage_path_id']    = $sol.azure_local.storage_path_id
    $mapped['wsfc_sofs_storage_path_ids']   = $sol.azure_local.storage_path_ids
    $mapped['wsfc_sofs_azl_cluster_name']   = $sol.azure_local.cluster_name
    # vm
    $mapped['wsfc_sofs_vm_prefix']          = $sol.vm.prefix
    $mapped['wsfc_sofs_vm_count']           = $sol.vm.count
    $mapped['wsfc_sofs_vm_processors']      = $sol.vm.processors
    $mapped['wsfc_sofs_vm_memory_mb']       = $sol.vm.memory_mb
    $mapped['wsfc_sofs_vm_admin_username']  = $sol.vm.admin_username
    $mapped['wsfc_sofs_vm_admin_password']  = $sol.vm.admin_password
    $mapped['wsfc_sofs_vm_ips']             = $sol.vm.ips
    # data_disks
    $mapped['wsfc_sofs_data_disk_count']    = $sol.data_disks.count
    $mapped['wsfc_sofs_data_disk_size_gb']  = $sol.data_disks.size_gb
    # domain
    $mapped['wsfc_sofs_domain_fqdn']        = $sol.domain.fqdn
    $mapped['wsfc_domain_fqdn']             = $sol.domain.fqdn
    $mapped['wsfc_sofs_domain_netbios']     = $sol.domain.netbios
    $mapped['wsfc_sofs_domain_join_username'] = $sol.domain.join_username
    $mapped['wsfc_sofs_domain_join_password'] = $sol.domain.join_password
    $mapped['wsfc_sofs_cluster_ou_path']    = $sol.domain.cluster_ou_path
    $mapped['wsfc_sofs_nodes_ou_path']      = $sol.domain.nodes_ou_path
    # dns
    $mapped['wsfc_sofs_dns_servers']        = $sol.dns_servers
    # sofs
    $mapped['wsfc_sofs_name']               = $sol.sofs.name
    $mapped['wsfc_sofs_cluster_name']       = $sol.sofs.cluster_name
    $mapped['wsfc_sofs_cluster_ip']         = $sol.sofs.cluster_ip
    $mapped['wsfc_sofs_share_name']         = $sol.sofs.share_name
    $mapped['wsfc_sofs_role_enabled']       = $sol.sofs.role_enabled
    $mapped['wsfc_sofs_anti_affinity_rule_name'] = $sol.sofs.anti_affinity_rule_name
    # s2d
    $mapped['wsfc_sofs_s2d_volume_name']    = $sol.s2d.volume_name
    $mapped['wsfc_sofs_s2d_volume_size_gb'] = $sol.s2d.volume_size_gb
    $mapped['wsfc_sofs_s2d_data_copies']    = $sol.s2d.data_copies
    # cloud_witness
    $mapped['wsfc_sofs_cloud_witness_name'] = $sol.cloud_witness.name
    $mapped['wsfc_sofs_cloud_witness_key_uri']    = $sol.cloud_witness.key_uri
    $mapped['wsfc_sofs_cloud_witness_key_secret'] = $sol.cloud_witness.key_secret
    # guest config
    $mapped['wsfc_sofs_guest_config_engine'] = $sol.guest_config_engine
    # ansible controller
    if ($sol.ansible_controller) {
        $mapped['wsfc_sofs_ansible_controller_name']           = $sol.ansible_controller.name
        $mapped['wsfc_sofs_ansible_controller_size']           = $sol.ansible_controller.size
        $mapped['wsfc_sofs_ansible_controller_admin_username'] = $sol.ansible_controller.admin_username
        $mapped['wsfc_sofs_ansible_controller_hub_subnet_id']  = $sol.ansible_controller.hub_subnet_id
        $mapped['wsfc_sofs_ansible_controller_hub_rg']         = $sol.ansible_controller.hub_rg
        $mapped['wsfc_sofs_ansible_existing_controller_ip']    = $sol.ansible_controller.existing_controller_ip
        $mapped['wsfc_sofs_ansible_existing_controller_user']  = $sol.ansible_controller.existing_controller_user
    }

    $sol['compute_wsfc'] = $mapped
    Write-Log "Compatibility shim applied — mapped new config sections to legacy keys." "PASS"
}

$cfg = $sol.compute_wsfc                                                 # compute.wsfc section

if (-not $cfg) {
    Write-Log "Solution config missing 'compute_wsfc' section." "FAIL"
    exit 1
}

# ===========================================================================
# RESOLVE PARAMETERS — param override > solution config > error
# ===========================================================================

# Helper: resolve a value from param, then config, then fail
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

$SubscriptionId         = Resolve-Param $SubscriptionId         $cfg.wsfc_sofs_subscription_id    "SubscriptionId"            # compute.wsfc.wsfc_sofs_subscription_id
$ResourceGroup          = Resolve-Param $ResourceGroup          $cfg.wsfc_sofs_resource_group     "ResourceGroup"             # compute.wsfc.wsfc_sofs_resource_group
$Location               = Resolve-Param $Location               $cfg.wsfc_sofs_location           "Location"                  # compute.wsfc.wsfc_sofs_location
$CustomLocationId       = Resolve-Param $CustomLocationId       $cfg.wsfc_sofs_custom_location_id "CustomLocationId"          # compute.wsfc.wsfc_sofs_custom_location_id
$LogicalNetworkId       = Resolve-Param $LogicalNetworkId       $cfg.wsfc_sofs_logical_network_id "LogicalNetworkId"          # compute.wsfc.wsfc_sofs_logical_network_id
$ImageName              = Resolve-Param $ImageName              $cfg.wsfc_sofs_gallery_image_name "ImageName"                 # compute.wsfc.wsfc_sofs_gallery_image_name
$VMPrefix               = Resolve-Param $VMPrefix               $cfg.wsfc_sofs_vm_prefix          "VMPrefix"                  # compute.wsfc.wsfc_sofs_vm_prefix
$WitnessStorageAccount  = Resolve-Param $WitnessStorageAccount  $cfg.wsfc_sofs_cloud_witness_name "WitnessStorageAccount"     # compute.wsfc.wsfc_sofs_cloud_witness_name

# Integer params: 0 = not set via param, use config
if ($VMCount      -le 0) { $VMCount      = [int]$cfg.wsfc_sofs_vm_count         }  # compute.wsfc.wsfc_sofs_vm_count
if ($VMProcessors -le 0) { $VMProcessors = [int]$cfg.wsfc_sofs_vm_processors    }  # compute.wsfc.wsfc_sofs_vm_processors
if ($VMMemoryMB   -le 0) { $VMMemoryMB   = [int]$cfg.wsfc_sofs_vm_memory_mb     }  # compute.wsfc.wsfc_sofs_vm_memory_mb
if ($DataDiskCount  -le 0) { $DataDiskCount  = [int]$cfg.wsfc_sofs_data_disk_count   }  # compute.wsfc.wsfc_sofs_data_disk_count
if ($DataDiskSizeGB -le 0) { $DataDiskSizeGB = [int]$cfg.wsfc_sofs_data_disk_size_gb }  # compute.wsfc.wsfc_sofs_data_disk_size_gb

# Storage paths — per-VM map takes priority, then single default
if (-not $StoragePathIds -and $cfg.wsfc_sofs_storage_path_ids) {
    $StoragePathIds = @{}
    foreach ($key in $cfg.wsfc_sofs_storage_path_ids.Keys) {
        $StoragePathIds["$key"] = $cfg.wsfc_sofs_storage_path_ids[$key]      # compute.wsfc.wsfc_sofs_storage_path_ids
    }
}
if ($StoragePathId -eq "") {
    $StoragePathId = $cfg.wsfc_sofs_storage_path_id                          # compute.wsfc.wsfc_sofs_storage_path_id (fallback)
}
# Validate at least one storage path source exists
if (-not $StoragePathIds -and [string]::IsNullOrWhiteSpace($StoragePathId)) {
    Write-Log "No storage path provided — set StoragePathIds or StoragePathId." "FAIL"
    throw "Missing required value: StoragePathId or StoragePathIds"
}

# VM IPs — per-VM map from param or config
if (-not $VMIPs -and $cfg.wsfc_sofs_vm_ips) {
    $VMIPs = @{}
    foreach ($key in $cfg.wsfc_sofs_vm_ips.Keys) {
        $VMIPs["$key"] = $cfg.wsfc_sofs_vm_ips[$key]                        # compute.wsfc.wsfc_sofs_vm_ips
    }
}

# Admin credential URIs from config
$VMAdminUsername     = $cfg.wsfc_sofs_vm_admin_username       # compute.wsfc.wsfc_sofs_vm_admin_username
$VMAdminPassUri      = $cfg.wsfc_sofs_vm_admin_password       # compute.wsfc.wsfc_sofs_vm_admin_password (keyvault:// URI)

# Domain join config
$DomainFQDN          = $cfg.wsfc_sofs_domain_fqdn             # compute.wsfc.wsfc_sofs_domain_fqdn
$DomainNetBIOS       = $cfg.wsfc_sofs_domain_netbios          # compute.wsfc.wsfc_sofs_domain_netbios
$NodesOUPath         = $cfg.wsfc_sofs_nodes_ou_path           # compute.wsfc.wsfc_sofs_nodes_ou_path
$DomainJoinUser      = $cfg.wsfc_sofs_domain_join_username    # compute.wsfc.wsfc_sofs_domain_join_username
$DomainJoinPassUri   = $cfg.wsfc_sofs_domain_join_password    # compute.wsfc.wsfc_sofs_domain_join_password (keyvault:// URI)

# Tags: param > default
if (-not $Tags) {
    $Tags = @{
        project     = "SOFS"
        environment = "production"
        workload    = "FSLogix"
        solution    = "sofs-azure-local"
    }
}

# Build az CLI tags: array for CLI args, string for logging
$TagsArray  = @($Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
$TagsString = $TagsArray -join " "

Write-Log "Subscription:      $SubscriptionId"
Write-Log "Resource Group:    $ResourceGroup"
Write-Log "Location:          $Location"
Write-Log "VMs:               $VMCount x $VMPrefix (${VMProcessors} vCPU, ${VMMemoryMB} MB)"
Write-Log "Data Disks:        $DataDiskCount x ${DataDiskSizeGB} GB per VM"
Write-Log "Cloud Witness:     $WitnessStorageAccount"
Write-Log "Gallery Image:     $ImageName"
if ($StoragePathIds) {
    Write-Log "Storage Paths:     Per-VM map ($($StoragePathIds.Count) entries)"
} else {
    Write-Log "Storage Path:      $StoragePathId (single — all VMs)"
}
if ($VMIPs -and $VMIPs.Count -gt 0) {
    Write-Log "Static IPs:        $($VMIPs.Values -join ', ')"
} else {
    Write-Log "Static IPs:        None (DHCP)"
}

# ===========================================================================
# CREDENTIAL RESOLUTION — param > Key Vault > HARD FAIL (no prompts)
# ===========================================================================

Write-Log "Resolving VM admin credentials..." "HEADER"

$VMAdminPassword = $null
$resolvedUser    = $null

if ($Credential) {
    # Extract from PSCredential parameter
    $resolvedUser    = $Credential.UserName
    $VMAdminPassword = $Credential.GetNetworkCredential().Password
    Write-Log "Credentials provided via -Credential parameter for '$resolvedUser'." "PASS"
} else {
    # Resolve username — may be a keyvault:// URI or a plain string
    $resolvedUser = $VMAdminUsername
    if ($VMAdminUsername -match '^keyvault://') {
        $kvUser = Resolve-KeyVaultRef -KvUri $VMAdminUsername
        if ($kvUser) { $resolvedUser = $kvUser } else { Write-Log "  Could not resolve username from Key Vault — using raw value." "WARN" }
    }

    $VMAdminPassword = Resolve-KeyVaultRef -KvUri $VMAdminPassUri
    if (-not $VMAdminPassword) {
        Write-Log "FATAL: Could not resolve VM admin password from Key Vault and no -Credential parameter provided." "FAIL"
        Write-Log "  Provide credentials via: -Credential (Get-Credential) OR ensure Key Vault access." "FAIL"
        exit 1
    }
    Write-Log "Credentials resolved for '$resolvedUser'." "PASS"
}

# ===========================================================================
# WHATIF CHECK
# ===========================================================================

if ($WhatIf) {
    Write-Log "========================================" "WARN"
    Write-Log "[DRY RUN] Would deploy the following:" "WARN"
    Write-Log "========================================" "WARN"
    Write-Log "  Resource Group:  $ResourceGroup (create if absent)"
    Write-Log "  Cloud Witness:   $WitnessStorageAccount (Standard_LRS, StorageV2)"
    Write-Log "  NICs:            $VMCount x ${VMPrefix}-XX-nic"
    for ($i = 1; $i -le $VMCount; $i++) {
        $key = "{0:D2}" -f $i
        $ip  = if ($VMIPs -and $VMIPs[$key]) { $VMIPs[$key] } else { "DHCP" }
        $sp  = if ($StoragePathIds -and $StoragePathIds[$key]) { Split-Path $StoragePathIds[$key] -Leaf } elseif ($StoragePathId) { Split-Path $StoragePathId -Leaf } else { "none" }
        Write-Log "    ${VMPrefix}-${key}: IP=$ip  StoragePath=$sp"
    }
    Write-Log "  VMs:             $VMCount x ${VMPrefix}-XX ($VMProcessors vCPU, $VMMemoryMB MB)"
    Write-Log "  Data Disks:      $($VMCount * $DataDiskCount) x ${DataDiskSizeGB} GB (dynamic)"
    Write-Log "  Tags:            $TagsString"
    Write-Log "  Domain Join:     $DomainFQDN ($DomainNetBIOS) -> OU=$NodesOUPath"
    Write-Log "[DRY RUN] No changes made." "WARN"

    # Cleanup sensitive data
    $VMAdminPassword = $null
    [System.GC]::Collect()
    exit 0
}

# ===========================================================================
# ENSURE CLI EXTENSION
# ===========================================================================

Write-Log "Ensuring stack-hci-vm CLI extension..." "HEADER"
az extension add --name stack-hci-vm --upgrade --yes 2>$null
Write-Log "Extension ready." "PASS"

# ===========================================================================
# SET SUBSCRIPTION CONTEXT
# ===========================================================================

Write-Log "Setting subscription context..." "HEADER"
az account set --subscription $SubscriptionId
Test-AzCliResult "Failed to set subscription"
Write-Log "Subscription set: $SubscriptionId" "PASS"

# ===========================================================================
# STEP 0: Ensure Resource Group Exists
# ===========================================================================

Write-Log "Step 0 — Ensure Resource Group" "HEADER"

$rgExists = az group exists --name $ResourceGroup 2>$null
if ($rgExists -eq "true") {
    Write-Log "Resource group '$ResourceGroup' already exists. Skipping." "PASS"
} else {
    Write-Log "Creating resource group: $ResourceGroup ($Location)"
    az group create `
        --name $ResourceGroup `
        --location $Location `
        --tags $TagsArray `
        --output none
    Test-AzCliResult "Failed to create resource group $ResourceGroup"
    Write-Log "Resource group '$ResourceGroup' created." "PASS"
}

# ===========================================================================
# STEP 1: Create Cloud Witness Storage Account
# ===========================================================================

Write-Log "Step 1 — Create Cloud Witness Storage Account" "HEADER"

# Idempotency: check if storage account already exists
$witnessExists = az storage account show --name $WitnessStorageAccount --resource-group $ResourceGroup --query name -o tsv 2>$null
if ($witnessExists) {
    Write-Log "Storage account '$WitnessStorageAccount' already exists. Skipping create." "PASS"
} else {
    Write-Log "Creating storage account: $WitnessStorageAccount"
    az storage account create `
        --name $WitnessStorageAccount `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --tags $TagsArray `
        --output none
    Test-AzCliResult "Failed to create cloud witness storage account"
    Write-Log "Cloud witness storage account created." "PASS"
}

# Retrieve key for cluster quorum configuration
$WitnessKey = az storage account keys list `
    --account-name $WitnessStorageAccount `
    --resource-group $ResourceGroup `
    --query "[0].value" -o tsv
Test-AzCliResult "Failed to retrieve witness storage account key"
Write-Log "Cloud witness key retrieved." "PASS"

# ===========================================================================
# STEP 2: Create Network Interfaces (with static IPs)
# ===========================================================================

Write-Log "Step 2 — Create $VMCount NICs on compute logical network (parallel)" "HEADER"

1..$VMCount | ForEach-Object -Parallel {
    $i       = $_
    $key     = "{0:D2}" -f $i
    $VMName  = "$($using:VMPrefix)-${key}"
    $NicName = "$VMName-nic"
    $logFile = $using:logFile

    function Write-ParallelLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        $mtx  = [System.Threading.Mutex]::new($false, "SOFSLogMutex")
        try   { $mtx.WaitOne() | Out-Null; $line | Out-File -FilePath $logFile -Append -Encoding utf8 }
        finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
        switch ($Level) {
            "PASS" { Write-Host "[$ts] [PASS] $Message" -ForegroundColor Green }
            "FAIL" { Write-Host "[$ts] [FAIL] $Message" -ForegroundColor Red }
            "WARN" { Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow }
            default { Write-Host "[$ts] [INFO] $Message" }
        }
    }

    # Idempotency: check if NIC exists
    $nicExists = az stack-hci-vm network nic show --resource-group $using:ResourceGroup --name $NicName --query name -o tsv 2>$null
    if ($nicExists) {
        Write-ParallelLog "  NIC '$NicName' already exists. Skipping." "PASS"
        return
    }

    # Build NIC create command with optional static IP
    # NOTE: --tags omitted — stack-hci-vm extension has a serialization bug;
    #       tags are applied post-deployment via az resource tag (Step 6b)
    $nicArgs = @(
        "--resource-group", $using:ResourceGroup,
        "--custom-location", $using:CustomLocationId,
        "--location", $using:Location,
        "--name", $NicName,
        "--subnet-id", $using:LogicalNetworkId,
        "--output", "none"
    )

    $localVMIPs = $using:VMIPs
    $staticIP = if ($localVMIPs -and $localVMIPs[$key]) { $localVMIPs[$key] } else { $null }
    if ($staticIP) {
        $nicArgs += @("--ip-address", $staticIP)
        Write-ParallelLog "  Creating NIC: $NicName (static IP: $staticIP)"
    } else {
        Write-ParallelLog "  Creating NIC: $NicName (DHCP)"
    }

    & az stack-hci-vm network nic create @nicArgs
    if ($LASTEXITCODE -ne 0) {
        Write-ParallelLog "Failed to create NIC $NicName" "FAIL"
        throw "ERROR: Failed to create NIC $NicName (exit code: $LASTEXITCODE)"
    }
    Write-ParallelLog "  NIC '$NicName' created." "PASS"
} -ThrottleLimit 5

Write-Log "All $VMCount NICs created." "PASS"

# ===========================================================================
# STEP 3: Create VMs (with per-VM storage paths)
# ===========================================================================

Write-Log "Step 3 — Create $VMCount SOFS VMs (parallel)" "HEADER"

1..$VMCount | ForEach-Object -Parallel {
    $i       = $_
    $key     = "{0:D2}" -f $i
    $VMName  = "$($using:VMPrefix)-${key}"
    $NicName = "$VMName-nic"
    $logFile = $using:logFile

    function Write-ParallelLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        $mtx  = [System.Threading.Mutex]::new($false, "SOFSLogMutex")
        try   { $mtx.WaitOne() | Out-Null; $line | Out-File -FilePath $logFile -Append -Encoding utf8 }
        finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
        switch ($Level) {
            "PASS" { Write-Host "[$ts] [PASS] $Message" -ForegroundColor Green }
            "FAIL" { Write-Host "[$ts] [FAIL] $Message" -ForegroundColor Red }
            "WARN" { Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow }
            default { Write-Host "[$ts] [INFO] $Message" }
        }
    }

    # Idempotency: check if VM exists
    $vmExists = az stack-hci-vm show --resource-group $using:ResourceGroup --name $VMName --query name -o tsv 2>$null
    if ($vmExists) {
        Write-ParallelLog "  VM '$VMName' already exists. Skipping." "PASS"
        return
    }

    # Resolve per-VM storage path: map entry > default single path
    $localStoragePathIds = $using:StoragePathIds
    $vmStoragePath = if ($localStoragePathIds -and $localStoragePathIds[$key]) {
        $localStoragePathIds[$key]
    } else { $using:StoragePathId }

    Write-ParallelLog "  Creating VM: $VMName ($($using:VMProcessors) vCPU, $($using:VMMemoryMB) MB, storage=$(Split-Path $vmStoragePath -Leaf))"

    az stack-hci-vm create `
        --name $VMName `
        --resource-group $using:ResourceGroup `
        --custom-location $using:CustomLocationId `
        --location $using:Location `
        --image $using:ImageName `
        --admin-username $using:resolvedUser `
        --admin-password $using:VMAdminPassword `
        --computer-name $VMName `
        --hardware-profile memory-mb="$($using:VMMemoryMB)" processors="$($using:VMProcessors)" `
        --nics $NicName `
        --storage-path-id $vmStoragePath `
        --authentication-type all `
        --enable-agent true `
        --output none
    # NOTE: --tags omitted — stack-hci-vm extension serialization bug; tags applied in Step 6b
    if ($LASTEXITCODE -ne 0) {
        Write-ParallelLog "Failed to create VM $VMName" "FAIL"
        throw "ERROR: Failed to create VM $VMName (exit code: $LASTEXITCODE)"
    }
    Write-ParallelLog "  VM '$VMName' created." "PASS"
} -ThrottleLimit 5

Write-Log "All $VMCount VMs created." "PASS"

# ===========================================================================
# STEP 4: Create Data Disks (with per-VM storage paths)
# ===========================================================================

$TotalDisks = $VMCount * $DataDiskCount
Write-Log "Step 4 — Create $TotalDisks data disks ($DataDiskCount x $DataDiskSizeGB GB per VM, parallel)" "HEADER"

# Build a flat list of all disk jobs: {VMName, DiskName, StoragePath}
$diskJobs = @()
for ($i = 1; $i -le $VMCount; $i++) {
    $key           = "{0:D2}" -f $i
    $VMName        = "${VMPrefix}-${key}"
    $vmStoragePath = if ($StoragePathIds -and $StoragePathIds[$key]) { $StoragePathIds[$key] } else { $StoragePathId }
    for ($d = 1; $d -le $DataDiskCount; $d++) {
        $diskJobs += [PSCustomObject]@{ VMName = $VMName; DiskName = "$VMName-data$d"; StoragePath = $vmStoragePath }
    }
}

$diskJobs | ForEach-Object -Parallel {
    $job     = $_
    $logFile = $using:logFile

    function Write-ParallelLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        $mtx  = [System.Threading.Mutex]::new($false, "SOFSLogMutex")
        try   { $mtx.WaitOne() | Out-Null; $line | Out-File -FilePath $logFile -Append -Encoding utf8 }
        finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
        switch ($Level) {
            "PASS" { Write-Host "[$ts] [PASS] $Message" -ForegroundColor Green }
            "FAIL" { Write-Host "[$ts] [FAIL] $Message" -ForegroundColor Red }
            "WARN" { Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow }
            default { Write-Host "[$ts] [INFO] $Message" }
        }
    }

    # Idempotency: check if disk exists
    $diskExists = az stack-hci-vm disk show --resource-group $using:ResourceGroup --name $job.DiskName --query name -o tsv 2>$null
    if ($diskExists) {
        Write-ParallelLog "  Disk '$($job.DiskName)' already exists. Skipping." "PASS"
        return
    }

    Write-ParallelLog "  Creating disk: $($job.DiskName) ($($using:DataDiskSizeGB) GB, dynamic, storage=$(Split-Path $job.StoragePath -Leaf))"

    # NOTE: --tags omitted — stack-hci-vm extension serialization bug; tags applied in Step 6b
    az stack-hci-vm disk create `
        --resource-group $using:ResourceGroup `
        --custom-location $using:CustomLocationId `
        --location $using:Location `
        --name $job.DiskName `
        --size-gb $using:DataDiskSizeGB `
        --dynamic true `
        --storage-path-id $job.StoragePath `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-ParallelLog "Failed to create disk $($job.DiskName)" "FAIL"
        throw "ERROR: Failed to create disk $($job.DiskName) (exit code: $LASTEXITCODE)"
    }
    Write-ParallelLog "  Disk '$($job.DiskName)' created." "PASS"
} -ThrottleLimit 10

Write-Log "All $TotalDisks data disks created." "PASS"

# ===========================================================================
# STEP 5: Attach Data Disks to VMs
# ===========================================================================

Write-Log "Step 5 — Attach Data Disks to VMs" "HEADER"

for ($i = 1; $i -le $VMCount; $i++) {
    $key    = "{0:D2}" -f $i
    $VMName = "${VMPrefix}-${key}"

    # Check if disks are already attached — .name field doesn't exist on dataDisks, extract from ARM ID
    $attachedDiskIds = az stack-hci-vm show `
        --resource-group $ResourceGroup `
        --name $VMName `
        --query "properties.storageProfile.dataDisks[].id" -o json 2>$null | ConvertFrom-Json
    $attachedDiskNames = @($attachedDiskIds | ForEach-Object { Split-Path $_ -Leaf })

    $expectedDiskNames = @(1..$DataDiskCount | ForEach-Object { "$VMName-data$_" })

    $missingDisks = @($expectedDiskNames | Where-Object { $_ -notin $attachedDiskNames })
    if ($missingDisks.Count -eq 0) {
        Write-Log "  [$VMName] All $DataDiskCount disks already attached. Skipping." "PASS"
        continue
    }

    Write-Log "  Attaching disks to ${VMName}: $($expectedDiskNames -join ', ')"

    az stack-hci-vm disk attach `
        --resource-group $ResourceGroup `
        --vm-name $VMName `
        --disks @expectedDiskNames `
        --yes `
        --output none
    Test-AzCliResult "Failed to attach disks to $VMName"
}

Write-Log "All disks attached." "PASS"

# ===========================================================================
# STEP 5b: Domain Join VMs via JsonADDomainExtension (Arc)
# ===========================================================================

Write-Log "Step 5b — Domain join $VMCount VMs via JsonADDomainExtension" "HEADER"

# Resolve domain join password from Key Vault
Write-Log "Resolving domain join credentials from Key Vault..."
$DomainJoinPassword = Resolve-KeyVaultRef -KvUri $DomainJoinPassUri
if (-not $DomainJoinPassword) {
    Write-Log "Could not resolve domain join password: $DomainJoinPassUri" "FAIL"
    throw "ERROR: Domain join password unavailable"
}

# Format user as UPN (user@domain) for JsonADDomainExtension — NetBIOS DOMAIN\user format
# is unreliable with the extension's internal NetJoinDomain call; UPN format works consistently
$DomainJoinUserFull = if ($DomainJoinUser -notlike "*@*" -and $DomainJoinUser -notlike "*\\*") {
    "$DomainJoinUser@$DomainFQDN"
} elseif ($DomainJoinUser -like "*\\*") {
    # Convert DOMAIN\user to UPN
    "$($DomainJoinUser.Split('\')[1])@$DomainFQDN"
} else { $DomainJoinUser }

Write-Log "Domain join credentials resolved for '$DomainJoinUserFull'." "PASS"
Write-Log "  Domain:  $DomainFQDN"
Write-Log "  OU:      $NodesOUPath"

# Build extension JSON and write to temp files (CLI splits inline JSON on commas)
$djSettingsFile  = [System.IO.Path]::GetTempFileName()
$djProtectedFile = [System.IO.Path]::GetTempFileName()
[ordered]@{ Name = $DomainFQDN; OUPath = $NodesOUPath; User = $DomainJoinUserFull; Restart = "true"; Options = "3" } | ConvertTo-Json -Compress | Out-File $djSettingsFile  -Encoding utf8 -NoNewline
[ordered]@{ Password = $DomainJoinPassword } | ConvertTo-Json -Compress                                              | Out-File $djProtectedFile -Encoding utf8 -NoNewline

1..$VMCount | ForEach-Object -Parallel {
    $i      = $_
    $key    = "{0:D2}" -f $i
    $VMName = "$($using:VMPrefix)-${key}"
    $logFile = $using:logFile

    function Write-ParallelLog {
        param([string]$Message, [string]$Level = "INFO")
        $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$ts] [$Level] $Message"
        $mtx  = [System.Threading.Mutex]::new($false, "SOFSLogMutex")
        try   { $mtx.WaitOne() | Out-Null; $line | Out-File -FilePath $logFile -Append -Encoding utf8 }
        finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
        switch ($Level) {
            "PASS" { Write-Host "[$ts] [PASS] $Message" -ForegroundColor Green }
            "FAIL" { Write-Host "[$ts] [FAIL] $Message" -ForegroundColor Red }
            "WARN" { Write-Host "[$ts] [WARN] $Message" -ForegroundColor Yellow }
            default { Write-Host "[$ts] [INFO] $Message" }
        }
    }

    # Idempotency: skip if extension already succeeded
    # Azure Local VMs are Arc-connected machines — extensions via connectedmachine provider
    $extState = az connectedmachine extension show `
        --resource-group $using:ResourceGroup `
        --machine-name $VMName `
        --name JsonADDomainExtension `
        --query "properties.provisioningState" -o tsv 2>$null
    if ($extState -eq "Succeeded") {
        Write-ParallelLog "  [$VMName] Domain join extension already succeeded. Skipping." "PASS"
        return
    }

    Write-ParallelLog "  [$VMName] Installing JsonADDomainExtension..."
    az connectedmachine extension create `
        --resource-group $using:ResourceGroup `
        --machine-name $VMName `
        --name JsonADDomainExtension `
        --type JsonADDomainExtension `
        --publisher Microsoft.Compute `
        --location $using:Location `
        --settings "@$($using:djSettingsFile)" `
        --protected-settings "@$($using:djProtectedFile)" `
        --output none
    if ($LASTEXITCODE -ne 0) {
        Write-ParallelLog "Failed to domain join $VMName" "FAIL"
        throw "ERROR: Failed to domain join $VMName (exit code: $LASTEXITCODE)"
    }
    Write-ParallelLog "  [$VMName] Domain join complete." "PASS"
} -ThrottleLimit 5

# Clean up temp files and clear sensitive data
Remove-Item $djSettingsFile, $djProtectedFile -ErrorAction SilentlyContinue
$DomainJoinPassword = $null

Write-Log "All $VMCount VMs domain joined to $DomainFQDN." "PASS"

# ===========================================================================
# STEP 6: Verify Deployment
# ===========================================================================

Write-Log "Step 6 — Verify Deployment" "HEADER"

$allGood = $true
for ($i = 1; $i -le $VMCount; $i++) {
    $key    = "{0:D2}" -f $i
    $VMName = "${VMPrefix}-${key}"

    $vmStatus = az stack-hci-vm show `
        --resource-group $ResourceGroup `
        --name $VMName `
        --query "{name:name, status:properties.status.provisioningStatus.status, dataDisks:length(properties.storageProfile.dataDisks)}" `
        -o json 2>$null | ConvertFrom-Json

    if ($vmStatus) {
        $diskCount = if ($vmStatus.dataDisks) { $vmStatus.dataDisks } else { 0 }
        Write-Log "  ${VMName}: status=$($vmStatus.status), dataDisks=$diskCount" "PASS"
        if ($diskCount -lt $DataDiskCount) {
            Write-Log "  ${VMName}: Expected $DataDiskCount data disks but found $diskCount!" "WARN"
            $allGood = $false
        }
    } else {
        Write-Log "  ${VMName}: Could not verify — VM not found!" "FAIL"
        $allGood = $false
    }
}

# ===========================================================================
# STEP 6b: Apply Tags to HCI Resources (workaround for stack-hci-vm extension bug)
# ===========================================================================

Write-Log "Step 6b — Apply tags to HCI resources (stack-hci-vm extension workaround)" "HEADER"

$hciResources = (az resource list --resource-group $ResourceGroup --query "[?contains(type,'microsoft.azurestackhci')].id" -o tsv 2>$null) |
    Where-Object { $_ -match '^/subscriptions/' }
if ($hciResources) {
    $taggedCount = 0
    foreach ($resId in ($hciResources | Where-Object { $_.Trim() })) {
        $resId = $resId.Trim()
        $resName = Split-Path $resId -Leaf
        az resource tag --ids $resId --tags $TagsArray --is-incremental --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $taggedCount++
        } else {
            Write-Log "  Could not tag: $resName" "WARN"
        }
    }
    Write-Log "Tagged $taggedCount HCI resources." "PASS"
} else {
    Write-Log "No HCI resources found to tag." "WARN"
}

# ===========================================================================
# SUMMARY
# ===========================================================================

$TotalPoolTB = [math]::Round($VMCount * $DataDiskCount * $DataDiskSizeGB / 1024, 1)

Write-Log "========================================" "HEADER"
if ($allGood) {
    Write-Log "DEPLOYMENT COMPLETE" "PASS"
} else {
    Write-Log "DEPLOYMENT COMPLETE (with warnings)" "WARN"
}
Write-Log "========================================" "HEADER"
Write-Log "  Resource Group:      $ResourceGroup"
Write-Log "  VMs Created:         $VMCount"
Write-Log "  Data Disks per VM:   $DataDiskCount x $DataDiskSizeGB GB"
Write-Log "  Total S2D Pool:      $TotalPoolTB TB"
Write-Log "  Cloud Witness:       $WitnessStorageAccount"
Write-Log "  Storage Paths:       $(if ($StoragePathIds) { 'per-VM map' } else { 'single' })"
Write-Log "  Log File:            $logFile"
Write-Log ""
Write-Log "NEXT STEPS:" "HEADER"
Write-Log "  1. Verify VMs are domain-joined and on the compute network"
Write-Log "  2. Run: .\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1"

# Cleanup sensitive data from memory
$VMAdminPassword = $null
[System.GC]::Collect()
