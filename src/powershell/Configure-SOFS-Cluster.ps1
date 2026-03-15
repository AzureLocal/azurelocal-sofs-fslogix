<#
.SYNOPSIS
    Configure-SOFS-Cluster.ps1

.DESCRIPTION
    Run this script from a management workstation with WinRM access to the SOFS VMs.
    Performs Phases 3-11 of the SOFS deployment:
      - Configures anti-affinity rules on the Azure Local cluster
      - Installs Failover Clustering and File Server roles on all SOFS VMs
      - Validates and creates the guest failover cluster
      - Configures cloud witness
      - Enables Storage Spaces Direct (S2D)
      - Applies guest S2D tuning
      - Creates the two-way mirror volume
      - Adds the Scale-Out File Server role
      - Creates the FSLogix SMB share with correct permissions
      - Outputs antivirus exclusion guidance
      - Validates the deployment

    All parameters default from the generated solution config YAML but can be
    overridden via script parameters. Idempotent — safe to re-run.
    Credentials are resolved from Key Vault via keyvault:// URIs — NEVER interactively.

.PARAMETER SolutionConfigPath
    Path to solution-sofs.yml. Default: solutions/sofs/solution-sofs.yml relative to CWD.

.PARAMETER Credential
    PSCredential override — used for WinRM sessions to SOFS VMs.

.PARAMETER TargetNode
    Limit execution to specific node names. Empty = all SOFS nodes.

.PARAMETER SetTrustedHosts
    If set, adds all SOFS VM IPs/FQDNs to the local WinRM TrustedHosts list before connecting.
    Use when connecting by IP or when Kerberos is not available.

.PARAMETER RemoveTrustedHosts
    If set, removes SOFS entries from TrustedHosts after script completes.

.PARAMETER WinRMTransport
    WinRM transport: 'kerberos' (default, uses FQDN) or 'basic' (uses IP, requires TrustedHosts).

.PARAMETER GuestClusterName
    Failover cluster name. Overrides config value.

.PARAMETER GuestClusterIP
    Failover cluster IP. Overrides config value.

.PARAMETER SOFSAccessPoint
    SOFS cluster role name. Overrides config value.

.PARAMETER FSLogixShareName
    SMB share name. Overrides config value.

.PARAMETER WitnessStorageAccount
    Cloud witness storage account name. Overrides config value.

.PARAMETER S2DVolumeName
    S2D volume friendly name. Overrides config value.

.PARAMETER S2DVolumeSizeGB
    S2D volume size in GB. Overrides config value.

.PARAMETER S2DNumberOfDataCopies
    S2D mirror data copies (2 or 3). Overrides config value.

.PARAMETER DomainFQDN
    Domain FQDN for WinRM targets. Overrides config value.

.PARAMETER DomainNetBIOS
    Domain NetBIOS name for permissions. Overrides config value.

.PARAMETER AntiAffinityRuleName
    Anti-affinity rule name. Empty string disables. Overrides config value.

.PARAMETER AzureLocalClusterName
    Azure Local physical cluster name (for anti-affinity). Overrides config value.

.PARAMETER VMPrefix
    VM naming prefix. Overrides config value.

.PARAMETER VMCount
    Number of SOFS VMs. Overrides config value.

.PARAMETER WhatIf
    Dry-run mode — displays what would be configured without making changes.

.PARAMETER LogPath
    Override log file path.

.EXAMPLE
    .\Configure-SOFS-Cluster.ps1
    .\Configure-SOFS-Cluster.ps1 -WhatIf
    .\Configure-SOFS-Cluster.ps1 -Credential (Get-Credential) -SetTrustedHosts
    .\Configure-SOFS-Cluster.ps1 -GuestClusterName "SOFS-Cluster" -VMCount 3

.NOTES
    Author:  TierPoint Hybrid Cloud Solutions
    Version: 3.0
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]       $SolutionConfigPath     = "",            # Path to solution-sofs.yml
    [PSCredential] $Credential             = $null,         # Override credential resolution
    [string[]]     $TargetNode             = @(),           # Limit to specific nodes; empty = all
    [switch]       $SetTrustedHosts,                        # Add VMs to TrustedHosts before connecting (auto-enabled when WinRMTransport=basic)
    [switch]       $RemoveTrustedHosts,                     # Clean up TrustedHosts after completion
    [ValidateSet("kerberos","basic")]
    [string]       $WinRMTransport         = "basic",       # WinRM transport: basic=IP+NTLM (default, works from non-domain machines); kerberos=FQDN+Kerberos (domain-joined only)
    [string]       $GuestClusterName       = "",            # Failover cluster name
    [string]       $GuestClusterIP         = "",            # Failover cluster IP
    [string]       $SOFSAccessPoint        = "",            # SOFS cluster role name
    [string]       $SOFSAccessPointIP      = "",            # SOFS cluster role static IP (VCO)
    [string]       $FSLogixShareName       = "",            # SMB share name
    [string]       $WitnessStorageAccount  = "",            # Cloud witness storage account name
    [string]       $S2DVolumeName          = "",            # S2D volume friendly name
    [int]          $S2DVolumeSizeGB        = 0,             # S2D volume size in GB
    [int]          $S2DNumberOfDataCopies  = 0,             # Mirror data copies (2 or 3)
    [string]       $DomainFQDN             = "",            # Domain FQDN
    [string]       $DomainNetBIOS          = "",            # Domain NetBIOS name
    [string]       $AntiAffinityRuleName   = "",            # Anti-affinity rule name (empty = use config)
    [string]       $AzureLocalClusterName  = "",            # Azure Local physical cluster name
    [string]       $VMPrefix               = "",            # VM naming prefix
    [int]          $VMCount                = 0,             # Number of SOFS VMs
    [switch]       $WhatIf,                                 # Dry-run mode
    [string]       $LogPath                = ""             # Override log file path
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
# LOAD SOLUTION CONFIG
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "SOFS Guest Cluster Configuration" "HEADER"
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

$VMPrefix               = Resolve-Param $VMPrefix               $cfg.wsfc_sofs_vm_prefix          "VMPrefix"                  # compute.wsfc.wsfc_sofs_vm_prefix
$GuestClusterName       = Resolve-Param $GuestClusterName       $cfg.wsfc_sofs_cluster_name       "GuestClusterName"          # compute.wsfc.wsfc_sofs_cluster_name
$GuestClusterIP         = Resolve-Param $GuestClusterIP         $cfg.wsfc_sofs_cluster_ip         "GuestClusterIP"            # compute.wsfc.wsfc_sofs_cluster_ip
$SOFSAccessPoint        = Resolve-Param $SOFSAccessPoint        $cfg.wsfc_sofs_name               "SOFSAccessPoint"           # compute.wsfc.wsfc_sofs_name
$SOFSAccessPointIP      = Resolve-Param $SOFSAccessPointIP      $cfg.wsfc_sofs_ip                 "SOFSAccessPointIP" $false  # compute.wsfc.wsfc_sofs_ip (not used in current logic)
$FSLogixShareName       = Resolve-Param $FSLogixShareName       $cfg.wsfc_sofs_share_name         "FSLogixShareName"          # compute.wsfc.wsfc_sofs_share_name
$WitnessStorageAccount  = Resolve-Param $WitnessStorageAccount  $cfg.wsfc_sofs_cloud_witness_name "WitnessStorageAccount"     # compute.wsfc.wsfc_sofs_cloud_witness_name
$S2DVolumeName          = Resolve-Param $S2DVolumeName          $cfg.wsfc_sofs_s2d_volume_name    "S2DVolumeName"             # compute.wsfc.wsfc_sofs_s2d_volume_name
$DomainFQDN             = Resolve-Param $DomainFQDN             $cfg.wsfc_sofs_domain_fqdn        "DomainFQDN"                # compute.wsfc.wsfc_sofs_domain_fqdn
$DomainNetBIOS          = Resolve-Param $DomainNetBIOS          $cfg.wsfc_sofs_domain_netbios     "DomainNetBIOS"             # compute.wsfc.wsfc_sofs_domain_netbios

# Integer params: 0 = not set via param, use config
if ($VMCount -le 0)              { $VMCount              = [int]$cfg.wsfc_sofs_vm_count          }  # compute.wsfc.wsfc_sofs_vm_count
if ($S2DVolumeSizeGB -le 0)      { $S2DVolumeSizeGB      = [int]$cfg.wsfc_sofs_s2d_volume_size_gb }  # compute.wsfc.wsfc_sofs_s2d_volume_size_gb
if ($S2DNumberOfDataCopies -le 0) { $S2DNumberOfDataCopies = [int]$cfg.wsfc_sofs_s2d_data_copies  }  # compute.wsfc.wsfc_sofs_s2d_data_copies

$S2DVolumeSize = "${S2DVolumeSizeGB}GB"

$WitnessEndpoint = "core.windows.net"

# Anti-affinity — use config if param is empty
if ($AntiAffinityRuleName -eq "") {
    $AntiAffinityRuleName = if ($cfg['wsfc_sofs_anti_affinity_rule_name']) { $cfg['wsfc_sofs_anti_affinity_rule_name'] } else { "SOFS-AntiAffinity" }
}
$AntiAffinityEnabled = ($AntiAffinityRuleName -ne "")

# Azure Local cluster name
if ($AzureLocalClusterName -eq "") {
    $AzureLocalClusterName = if ($cfg['wsfc_sofs_azl_cluster_name']) { $cfg['wsfc_sofs_azl_cluster_name'] } else { "AzLocalCluster" }
}

# Build VM names
$VMNames = @()
for ($i = 1; $i -le $VMCount; $i++) {
    $VMNames += "{0}-{1:D2}" -f $VMPrefix, $i
}

# VM IPs — from wsfc_sofs_vm_ips map or DNS fallback
$VMIPs = @{}
if ($cfg.wsfc_sofs_vm_ips -and $cfg.wsfc_sofs_vm_ips.Count -gt 0) {
    $i = 1
    foreach ($VM in $VMNames) {
        $key = "{0:D2}" -f $i
        $ip  = $cfg.wsfc_sofs_vm_ips[$key]                              # compute.wsfc.wsfc_sofs_vm_ips
        if ($ip) { $VMIPs[$VM] = $ip }
        $i++
    }
} else {
    Write-Log "No node IPs in config — will resolve via DNS." "WARN"
    foreach ($VM in $VMNames) {
        try {
            $resolved = [System.Net.Dns]::GetHostAddresses($VM) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
            $VMIPs[$VM] = $resolved.IPAddressToString
            Write-Log "  Resolved $VM -> $($VMIPs[$VM])"
        } catch {
            Write-Log "  Could not resolve $VM — WinRM may fail." "WARN"
        }
    }
}

# Credential config — use domain account (required for Kerberos WinRM and AD object creation)
# Local VM admin cannot authenticate via Kerberos; New-Cluster and Add-ClusterScaleOutFileServerRole
# both require domain credentials to create CNO/VCO objects in AD.
$ClusterAdminUser    = $cfg.wsfc_sofs_domain_join_username               # compute.wsfc.wsfc_sofs_domain_join_username (plain string or keyvault://)
$ClusterAdminPassUri = $cfg.wsfc_sofs_domain_join_password               # compute.wsfc.wsfc_sofs_domain_join_password (keyvault:// URI)

Write-Log "Cluster:           $GuestClusterName ($GuestClusterIP)"
Write-Log "SOFS Name:         $SOFSAccessPoint"
Write-Log "Share:             $FSLogixShareName"
Write-Log "S2D Volume:        $S2DVolumeName ($S2DVolumeSize, ${S2DNumberOfDataCopies}-way mirror)"
Write-Log "Cloud Witness:     $WitnessStorageAccount"
Write-Log "Domain:            $DomainFQDN ($DomainNetBIOS)"
Write-Log "VMs:               $($VMNames -join ', ')"
Write-Log "Anti-affinity:     $AntiAffinityEnabled"
Write-Log "WinRM Transport:   $WinRMTransport"

# ===========================================================================
# CREDENTIAL RESOLUTION — param > Key Vault > HARD FAIL (no prompts)
# ===========================================================================

if (-not $Credential) {
    Write-Log "Resolving domain credentials from Key Vault..." "HEADER"

    # Resolve username — may be a keyvault:// URI or a plain string
    $resolvedUser = $ClusterAdminUser
    if ($ClusterAdminUser -match '^keyvault://') {
        $kvUser = Resolve-KeyVaultRef -KvUri $ClusterAdminUser
        if ($kvUser) { $resolvedUser = $kvUser } else { Write-Log "  Could not resolve username from Key Vault — using raw value." "WARN" }
    }

    # Build DOMAIN\user format for NTLM WinRM (basic/IP transport requires NTLM; UPN does not work with NTLM)
    # Kerberos transport uses UPN, but basic transport (default for non-domain laptops) requires DOMAIN\user
    if ($resolvedUser -notlike "*\*" -and $resolvedUser -notlike "*@*") {
        $resolvedUser = "$DomainNetBIOS\$resolvedUser"
    } elseif ($resolvedUser -like "*@*") {
        # Convert UPN to DOMAIN\user for NTLM
        $resolvedUser = "$DomainNetBIOS\$($resolvedUser.Split('@')[0])"
    }

    $clusterPass = Resolve-KeyVaultRef -KvUri $ClusterAdminPassUri
    if ($clusterPass) {
        $Credential = New-Object PSCredential($resolvedUser, (ConvertTo-SecureString $clusterPass -AsPlainText -Force))
        Write-Log "Credentials resolved for '$resolvedUser'." "PASS"
    } else {
        Write-Log "FATAL: Could not resolve domain credentials from Key Vault and no -Credential parameter provided." "FAIL"
        Write-Log "  Provide credentials via: -Credential (Get-Credential) OR ensure Key Vault access." "FAIL"
        exit 1
    }
}

# Resolve cloud witness key
Write-Log "Resolving cloud witness key..." "HEADER"
$WitnessKey = $null
if ($cfg['wsfc_sofs_cloud_witness_key_uri'] -and $cfg['wsfc_sofs_cloud_witness_key_uri'] -ne "") {
    $WitnessKey = Resolve-KeyVaultRef -KvUri $cfg['wsfc_sofs_cloud_witness_key_uri']  # compute.wsfc.wsfc_sofs_cloud_witness_key_uri
}
if (-not $WitnessKey) {
    # Fallback: retrieve key directly from witness storage account
    Write-Log "  Falling back to storage account key retrieval (az CLI)..." "WARN"
    try {
        $WitnessKey = az storage account keys list `
            --account-name $WitnessStorageAccount `
            --resource-group $cfg.wsfc_sofs_resource_group `
            --query "[0].value" -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $WitnessKey) {
            Write-Log "  Witness key retrieved from storage account." "PASS"
        } else {
            Write-Log "  Could not retrieve witness key. Cloud witness setup will fail." "FAIL"
            exit 1
        }
    } catch {
        Write-Log "  Storage key retrieval failed: $_" "FAIL"
        exit 1
    }
}

# ===========================================================================
# TRUSTEDHOSTS MANAGEMENT
# ===========================================================================

# Auto-enable TrustedHosts when using basic transport — required for NTLM from non-domain machines
if ($WinRMTransport -eq "basic" -and -not $SetTrustedHosts) {
    Write-Log "WinRMTransport=basic: auto-enabling TrustedHosts management." "WARN"
    $SetTrustedHosts = $true
}

$trustedHostsEntries = @()

if ($SetTrustedHosts) {
    Write-Log "Setting TrustedHosts for SOFS VMs..." "HEADER"

    # For basic transport only add IPs — FQDNs are irrelevant and require DNS
    # For kerberos transport add FQDNs (Kerberos requires name-based auth)
    foreach ($VM in $VMNames) {
        if ($WinRMTransport -eq "basic") {
            if ($VMIPs[$VM]) { $trustedHostsEntries += $VMIPs[$VM] }
        } else {
            $trustedHostsEntries += "$VM.$DomainFQDN"
        }
    }

    # Read current TrustedHosts
    $currentTH = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
    $existingEntries = if ($currentTH) { $currentTH -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } } else { @() }

    # Check if each entry is already covered — handles exact matches and wildcards (e.g. 192.168.222.*)
    $uncovered = $trustedHostsEntries | Where-Object {
        $entry = $_
        -not ($existingEntries | Where-Object { $entry -like $_ })
    }

    if ($uncovered.Count -eq 0) {
        Write-Log "  All SOFS IPs already covered by existing TrustedHosts entries." "PASS"
    } else {
        $allEntries = ($existingEntries + $uncovered) -join ','
        try {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $allEntries -Force -ErrorAction Stop
            Write-Log "  Added to TrustedHosts: $($uncovered -join ', ')" "PASS"
        } catch {
            Write-Log "  Could not update TrustedHosts (run as Administrator if needed): $_" "WARN"
            Write-Log "  Continuing — existing entries may already cover the target IPs." "WARN"
        }
    }
}

# ===========================================================================
# WHATIF CHECK
# ===========================================================================

if ($WhatIf) {
    Write-Log "========================================" "WARN"
    Write-Log "[DRY RUN] Would configure the following:" "WARN"
    Write-Log "========================================" "WARN"
    Write-Log "  Phase 3:  Anti-affinity rules (enabled=$AntiAffinityEnabled)"
    Write-Log "  Phase 5:  Failover-Clustering, FS-FileServer roles on $VMCount nodes"
    Write-Log "  Phase 6:  Create cluster '$GuestClusterName' @ $GuestClusterIP"
    Write-Log "  Phase 7:  Enable S2D, create volume '$S2DVolumeName' ($S2DVolumeSize)"
    Write-Log "  Phase 8:  AD pre-stage + SOFS role '$SOFSAccessPoint' + share '$FSLogixShareName' (verified)"
    Write-Log "  Phase 9:  NTFS permissions on share directory (verified — all 4 ACEs confirmed)"
    Write-Log "  Phase 10: Antivirus exclusion guidance"
    Write-Log "  Phase 11: Deployment validation"
    Write-Log "[DRY RUN] No changes made." "WARN"
    exit 0
}

# ===========================================================================
# HELPER FUNCTIONS
# ===========================================================================

function Get-WinRMTarget {
    param([string]$VMName)
    if ($script:WinRMTransport -eq "basic" -and $script:VMIPs[$VMName]) {
        return $script:VMIPs[$VMName]
    }
    return "$VMName.$($script:DomainFQDN)"
}

function Invoke-OnAllNodes {
    param(
        [scriptblock]$ScriptBlock,
        [hashtable]$ArgumentList = @{}
    )
    $targetVMs = if ($script:TargetNode.Count -gt 0) {
        $script:VMNames | Where-Object { $_ -in $script:TargetNode }
    } else { $script:VMNames }

    foreach ($VM in $targetVMs) {
        $Target = Get-WinRMTarget -VMName $VM
        Write-Log "  [$VM] ($Target) ..." "VERBOSE"
        Invoke-Command -ComputerName $Target -Credential $script:Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }
}

function Invoke-OnFirstNode {
    param([scriptblock]$ScriptBlock)
    $FirstVM = $script:VMNames[0]
    $Target  = Get-WinRMTarget -VMName $FirstVM
    Write-Log "  [$FirstVM] ($Target) ..." "VERBOSE"
    Invoke-Command -ComputerName $Target -Credential $script:Credential -ScriptBlock $ScriptBlock -ErrorAction Stop
}

function Wait-ForNodeOnline {
    <#
    .DESCRIPTION
        Polls WinRM on a node via FQDN (or IP if basic transport) until it responds.
        Replaces the fragile Start-Sleep approach.
    #>
    param(
        [string]$VMName,
        [int]$MaxAttempts = 20,
        [int]$IntervalSeconds = 15
    )
    $Target = Get-WinRMTarget -VMName $VMName
    $Attempt = 0
    do {
        $Attempt++
        $Online = Test-WSMan -ComputerName $Target -ErrorAction SilentlyContinue
        if (-not $Online) {
            Write-Log "  [$VMName] Not ready yet (attempt $Attempt/$MaxAttempts)..." "WARN"
            Start-Sleep -Seconds $IntervalSeconds
        }
    } while (-not $Online -and $Attempt -lt $MaxAttempts)

    if ($Online) {
        Write-Log "  [$VMName] Online." "PASS"
        return $true
    } else {
        Write-Log "  [$VMName] Failed to come back online after $MaxAttempts attempts." "FAIL"
        return $false
    }
}

# ===========================================================================
# PHASE 3: Configure Anti-Affinity Rules on Azure Local Cluster
# ===========================================================================

Write-Log "Phase 3 — Configure Anti-Affinity Rules" "HEADER"

if ($AntiAffinityEnabled) {
    Write-Log "Configuring anti-affinity rule on Azure Local cluster: $AzureLocalClusterName"

    if (-not (Get-Module -Name FailoverClusters -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-Log "FailoverClusters module not installed on this machine. Skipping anti-affinity." "WARN"
        Write-Log "  Install RSAT: Add-WindowsCapability -Online -Name Rsat.FailoverCluster.Management.Tools~~~~0.0.1.0" "WARN"
        Write-Log "  Then re-run, or configure anti-affinity manually on $AzureLocalClusterName." "WARN"
    } else {
        # Idempotency: check if rule already exists
        $existingRule = Get-ClusterAffinityRule -Name $AntiAffinityRuleName -Cluster $AzureLocalClusterName -ErrorAction SilentlyContinue
        if ($existingRule) {
            Write-Log "Anti-affinity rule '$AntiAffinityRuleName' already exists. Skipping create." "PASS"
        } else {
            try {
                New-ClusterAffinityRule -Name $AntiAffinityRuleName `
                                        -RuleType DifferentNode `
                                        -Cluster $AzureLocalClusterName `
                                        -ErrorAction Stop

                Add-ClusterGroupToAffinityRule -Groups $VMNames `
                                               -Name $AntiAffinityRuleName `
                                               -Cluster $AzureLocalClusterName `
                                               -ErrorAction Stop

                Set-ClusterAffinityRule -Name $AntiAffinityRuleName `
                                        -Enabled 1 `
                                        -Cluster $AzureLocalClusterName `
                                        -ErrorAction Stop

                Write-Log "Anti-affinity rule '$AntiAffinityRuleName' created and enabled." "PASS"
            }
            catch {
                Write-Log "New-ClusterAffinityRule not available. Falling back to AntiAffinityClassNames..." "WARN"

                try {
                    $AntiAffinity = New-Object System.Collections.Specialized.StringCollection
                    $AntiAffinity.Add("SOFSCluster") | Out-Null

                    foreach ($VM in $VMNames) {
                        (Get-ClusterGroup -Name $VM -Cluster $AzureLocalClusterName).AntiAffinityClassNames = $AntiAffinity
                    }
                    Write-Log "Legacy anti-affinity class applied to all SOFS VMs." "PASS"
                }
                catch {
                    Write-Log "Anti-affinity fallback also failed: $_" "WARN"
                    Write-Log "Anti-affinity must be configured manually on $AzureLocalClusterName." "WARN"
                }
            }
        }

        # Verify placement (best-effort)
        try {
            Write-Log "Current VM placement:"
            Get-ClusterGroup -Cluster $AzureLocalClusterName |
                Where-Object { $_.Name -in $VMNames } |
                Format-Table Name, OwnerNode, State -AutoSize
        }
        catch {
            Write-Log "Could not verify VM placement: $_" "WARN"
        }
    }
} else {
    Write-Log "Anti-affinity disabled in config — skipping." "WARN"
}

# ===========================================================================
# PHASE 5: Install Required Roles and Features
# ===========================================================================

Write-Log "Phase 5 — Install Roles and Features on SOFS VMs" "HEADER"

$restartNeeded = $false

Invoke-OnAllNodes -ScriptBlock {
    $Features = @(
        "Failover-Clustering",
        "FS-FileServer",
        "RSAT-Clustering-PowerShell"
    )

    # Idempotency: check if all features are already installed
    $missing = $Features | Where-Object { (Get-WindowsFeature -Name $_).InstallState -ne 'Installed' }
    if ($missing.Count -eq 0) {
        Write-Host "    All features already installed. No action needed." -ForegroundColor Green
        return
    }

    Write-Host "    Installing: $($missing -join ', ')" -ForegroundColor Yellow
    $Result = Install-WindowsFeature -Name $missing -IncludeManagementTools
    if ($Result.RestartNeeded -eq "Yes") {
        Write-Host "    Restart required — restarting..." -ForegroundColor Yellow
        Restart-Computer -Force
    }
    else {
        Write-Host "    Features installed. No restart needed." -ForegroundColor Green
    }
}

# Wait for all nodes to come back online (replaces fragile Start-Sleep 60)
Write-Log "Waiting for all nodes to come back online..."
$allOnline = $true
foreach ($VM in $VMNames) {
    if (-not (Wait-ForNodeOnline -VMName $VM -MaxAttempts 20 -IntervalSeconds 15)) {
        Write-Log "[$VM] Failed to come back online after restart." "FAIL"
        throw "[$VM] Failed to come back online after restart."
    }
}

Write-Log "All nodes online." "PASS"

# ===========================================================================
# PHASE 5b: Ensure cluster account is local Administrator on all nodes
# New-Cluster runs on SOFS-01 and connects to SOFS-02/03 using the calling
# user's identity — that account must be a local admin on every node.
# ===========================================================================

Write-Log "Phase 5b — Ensure '$($Credential.UserName)' is local Administrator on all nodes" "HEADER"

try {
    Invoke-OnAllNodes -ScriptBlock {
        $user = $using:Credential.UserName  # DOMAIN\user format e.g. MGMT\svc.azl.local
        $members = net localgroup Administrators 2>$null
        $shortUser = ($user -split '\\')[-1]
        $alreadyMember = $members | Where-Object { $_ -like "*$shortUser*" }
        if ($alreadyMember) {
            Write-Host "    '$user' already in local Administrators." -ForegroundColor Green
        } else {
            Add-LocalGroupMember -Group "Administrators" -Member $user -ErrorAction Stop
            Write-Host "    '$user' added to local Administrators." -ForegroundColor Green
        }
    }
    Write-Log "Local admin membership verified on all nodes." "PASS"
} catch {
    Write-Log "FATAL: Could not add '$($Credential.UserName)' to local Administrators on a node: $_" "FAIL"
    Write-Log "  Add the account manually to local Administrators on all SOFS VMs and re-run." "FAIL"
    exit 1
}

# ===========================================================================
# PHASE 6: Validate and Create the Guest Failover Cluster
# ===========================================================================

Write-Log "Phase 6 — Create Guest Failover Cluster" "HEADER"

# Idempotency: check if cluster already exists
$clusterExists = $false
try {
    $existingCluster = Invoke-OnFirstNode -ScriptBlock {
        Get-Cluster -ErrorAction SilentlyContinue
    }
    if ($existingCluster) {
        $clusterExists = $true
        Write-Log "Cluster '$($existingCluster.Name)' already exists. Skipping create." "PASS"
    }
} catch {
    # Cluster does not exist yet
}

if (-not $clusterExists) {
    Write-Log "Running cluster validation..."
    Invoke-OnFirstNode -ScriptBlock {
        Test-Cluster -Node $using:VMNames `
                     -Include "Inventory", "Network", "System Configuration" `
                     -ErrorAction SilentlyContinue | Out-Null
        Write-Host "    Validation complete." -ForegroundColor Green
    }

    Write-Log "Creating failover cluster: $GuestClusterName ($GuestClusterIP)"
    # Run New-Cluster as a scheduled task on SOFS-01 — task runs as domain user with a real
    # Kerberos TGT, so it can authenticate outbound to SOFS-02/03. No laptop changes needed.
    $plainPass  = $Credential.GetNetworkCredential().Password
    $domainUser = $Credential.UserName
    $taskName   = "SOFS-NewCluster"
    $resultFile = "C:\Windows\Temp\NewCluster-result.txt"
    $nodesCsv   = $VMNames -join ","

    try {
        Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument ("-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"" +
                                "try { " +
                                "New-Cluster -Name '$using:GuestClusterName' " +
                                "-Node @('$($using:VMNames -join "','")') " +
                                "-StaticAddress '$using:GuestClusterIP' -NoStorage -ErrorAction Stop | Out-Null; " +
                                "'SUCCESS' | Out-File -FilePath '$using:resultFile' -Encoding utf8 " +
                                "} catch { `$_.Exception.Message | Out-File -FilePath '$using:resultFile' -Encoding utf8; exit 1 }`"")
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

            Remove-Item $using:resultFile -Force -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName -Confirm:$false -ErrorAction SilentlyContinue

            Register-ScheduledTask -TaskName $using:taskName `
                -Action $action -Settings $settings `
                -RunLevel Highest `
                -User $using:domainUser -Password $using:plainPass `
                -Force | Out-Null

            Start-ScheduledTask -TaskName $using:taskName
            Write-Host "    Task started." -ForegroundColor Green
        }

        # Poll until complete (max 5 minutes)
        Write-Log "  Waiting for New-Cluster task to complete..."
        $deadline = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 5
            $state = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
                (Get-ScheduledTask -TaskName $using:taskName -ErrorAction SilentlyContinue).State
            }
        } while ($state -eq 'Running' -and (Get-Date) -lt $deadline)

        # Read result and clean up
        $result = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
            $r = Get-Content $using:resultFile -Raw -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item $using:resultFile -Force -ErrorAction SilentlyContinue
            return $r
        }

        if ($result -notmatch 'SUCCESS') {
            Write-Log "FATAL: New-Cluster failed: $result" "FAIL"
            Write-Log "  Ensure '$domainUser' has 'Create Computer Objects' in the cluster OU in AD." "FAIL"
            exit 1
        }
    } catch {
        Write-Log "FATAL: New-Cluster task setup failed: $_" "FAIL"
        exit 1
    }
    Write-Log "  Cluster '$GuestClusterName' created." "PASS"
    Write-Log "  Waiting for cluster service to stabilize..."
    Start-Sleep -Seconds 30
}

# Cloud witness — idempotent (Set-ClusterQuorum overwrites existing quorum config)
Write-Log "Configuring Cloud Witness..."
Invoke-OnFirstNode -ScriptBlock {
    Set-ClusterQuorum -CloudWitness `
                      -AccountName $using:WitnessStorageAccount `
                      -AccessKey $using:WitnessKey `
                      -Endpoint $using:WitnessEndpoint `
                      -ErrorAction Stop | Out-Null
    Write-Host "    Cloud witness configured." -ForegroundColor Green
}

Write-Log "Guest cluster ready with cloud witness." "PASS"

# ===========================================================================
# PHASE 7: Enable Storage Spaces Direct (S2D)
# ===========================================================================

Write-Log "Phase 7 — Enable Storage Spaces Direct" "HEADER"

# Check if S2D is already enabled AND the pool exists
$s2dEnabled = $false
try {
    $s2dStatus = Invoke-OnFirstNode -ScriptBlock {
        $enabled = Get-ClusterStorageSpacesDirect -ErrorAction SilentlyContinue
        $pool    = Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue
        return ($enabled -and $pool)
    }
    if ($s2dStatus) {
        $s2dEnabled = $true
        Write-Log "S2D already enabled and pool exists. Skipping." "PASS"
    } else {
        Write-Log "S2D enabled flag set but no pool found — will re-run Enable-ClusterStorageSpacesDirect." "WARN"
    }
} catch {
    # S2D not enabled yet
}

if (-not $s2dEnabled) {
    # Clean data disks on all nodes
    Write-Log "Cleaning data disks on all nodes..."
    Invoke-OnAllNodes -ScriptBlock {
        Get-Disk | Where-Object { $_.Number -ne 0 -and $_.IsBoot -eq $false } |
            Clear-Disk -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "    Disks cleaned." -ForegroundColor Green
    }

    # Enable S2D
    Write-Log "Enabling Storage Spaces Direct..."
    Invoke-OnFirstNode -ScriptBlock {
        Enable-ClusterStorageSpacesDirect -Confirm:$false -ErrorAction Stop
        Write-Host "    S2D enabled." -ForegroundColor Green
    }
}

# Apply guest S2D tuning on all nodes (idempotent — registry set is always safe to re-apply)
Write-Log "Applying guest S2D tuning (HwTimeout, AutoReplace)..."
Invoke-OnAllNodes -ScriptBlock {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\spaceport\Parameters" `
                     -Name "HwTimeout" `
                     -Value 0x0000003C `
                     -Type DWord
    Write-Host "    HwTimeout set to 60s." -ForegroundColor Green
}

Invoke-OnFirstNode -ScriptBlock {
    try {
        Get-StorageSubSystem Clus* |
            Set-StorageHealthSetting -Name "System.Storage.PhysicalDisk.AutoReplace.Enabled" -Value "False" -ErrorAction Stop
        Write-Host "    AutoReplace disabled." -ForegroundColor Green
    } catch {
        Write-Host "    AutoReplace setting skipped (storage subsystem not ready — safe to ignore): $_" -ForegroundColor Yellow
    }
}

# Create the S2D volume — idempotency check
$volumeExists = $false
try {
    $existingVolume = Invoke-OnFirstNode -ScriptBlock {
        Get-VirtualDisk -FriendlyName $using:S2DVolumeName -ErrorAction SilentlyContinue
    }
    if ($existingVolume) {
        $volumeExists = $true
        Write-Log "S2D volume '$S2DVolumeName' already exists. Skipping create." "PASS"
    }
} catch {
    # Volume does not exist
}

if (-not $volumeExists) {
    Write-Log "Creating S2D volume: $S2DVolumeName ($S2DVolumeSize, ${S2DNumberOfDataCopies}-way mirror)..."
    Invoke-OnFirstNode -ScriptBlock {
        New-Volume -FriendlyName $using:S2DVolumeName `
                   -StoragePoolFriendlyName "S2D on $using:GuestClusterName" `
                   -FileSystem CSVFS_ReFS `
                   -ResiliencySettingName Mirror `
                   -NumberOfDataCopies $using:S2DNumberOfDataCopies `
                   -Size ([uint64]$using:S2DVolumeSizeGB * 1GB) `
                   -ErrorAction Stop | Out-Null
        Write-Host "    Volume '$using:S2DVolumeName' created." -ForegroundColor Green
    }
}

# Verify
Write-Log "Verifying S2D..."
Invoke-OnFirstNode -ScriptBlock {
    Get-VirtualDisk | Format-Table FriendlyName, ResiliencySettingName, Size, HealthStatus -AutoSize
    Get-StoragePool -IsPrimordial $false | Format-Table FriendlyName, Size, AllocatedSize, HealthStatus -AutoSize
}

Write-Log "S2D enabled and volume ready." "PASS"

# Credentials shared by Phase 8 and Phase 9 tasks
$plainPass8   = $Credential.GetNetworkCredential().Password
$domainUser8  = $Credential.UserName

# ===========================================================================
# PHASE 8: AD Pre-Staging, SOFS Role, and FSLogix Share Creation
# Runs as a scheduled task on SOFS-01 to avoid WinRM double-hop issues.
# VERIFICATION gate runs after task completes — script will not proceed to
# Phase 9 unless role is Online AND share exists.
# ===========================================================================

Write-Log "Phase 8 — AD Pre-Staging, SOFS Role, and FSLogix Share Creation" "HEADER"
$taskName8   = "SOFS-Phase8"
$taskScript8 = "C:\Windows\Temp\SOFS-Phase8.ps1"
$resultFile8 = "C:\Windows\Temp\SOFS-Phase8-result.txt"
$taskLog8    = "C:\Windows\Temp\SOFS-Phase8-log.txt"

# Outer-scope variables expand into the here-string when it is created.
# Inner variables are backtick-escaped so they remain as real variables in the generated .ps1.
# Outer-scope variables expand into the here-string when it is created.
# Inner variables are backtick-escaped so they remain as real variables in the generated .ps1.
$scriptBody8 = @"
`$ErrorActionPreference = 'Continue'
Start-Transcript -Path '$taskLog8' -Force | Out-Null
try { Import-Module FailoverClusters -ErrorAction Stop } catch {
    Write-Host "[WARN] FailoverClusters module import failed: `$_ — continuing (cmdlets may already be available)."
}

try {
    # -----------------------------------------------------------------------
    # CLEANUP: Remove stale $SOFSAccessPoint AD object and DNS records from
    # previous partial runs. Only deletes if cluster group is NOT Online.
    # -----------------------------------------------------------------------
    `$sofsGroupPre = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
    if (-not `$sofsGroupPre -or `$sofsGroupPre.State -ne 'Online') {
        Write-Host '[CLEANUP] SOFS group not Online — checking for stale AD object and DNS...'
        `$cleanSearcher = New-Object DirectoryServices.DirectorySearcher([ADSI]'')
        `$cleanSearcher.Filter = '(&(objectClass=computer)(sAMAccountName=${SOFSAccessPoint}`$))'
        `$staleAD = `$cleanSearcher.FindOne()
        if (`$staleAD) {
            Write-Host '[CLEANUP] Deleting stale AD object for $SOFSAccessPoint...'
            `$staleEntry = `$staleAD.GetDirectoryEntry()
            `$staleEntry.DeleteTree()
            Write-Host '[CLEANUP] AD object deleted.'
        }
        # Flush local DNS cache so stale A records don't block Add-ClusterScaleOutFileServerRole
        & ipconfig /flushdns 2>`$null | Out-Null
        # Remove stale DNS A records via nsupdate-style dynamic update
        try {
            `$dnsName = '${SOFSAccessPoint}.$DomainFQDN'
            `$oldIPs = [System.Net.Dns]::GetHostAddresses(`$dnsName) | ForEach-Object { `$_.IPAddressToString }
            foreach (`$ip in `$oldIPs) {
                Write-Host "[CLEANUP] Removing stale DNS A record: `$dnsName -> `$ip"
                & dnscmd . /recorddelete $DomainFQDN $SOFSAccessPoint A `$ip /f 2>`$null
            }
            if (`$oldIPs) { Write-Host '[CLEANUP] DNS records removed.' }
        } catch {
            Write-Host "[CLEANUP] No stale DNS records found for $SOFSAccessPoint (OK)."
        }
        Start-Sleep -Seconds 5
    } else {
        Write-Host '[CLEANUP] SOFS group already Online — skipping cleanup.'
    }

    # -----------------------------------------------------------------------
    # PRE-STAGE: Create $SOFSAccessPoint computer object in AD and grant
    # ${GuestClusterName}$ full control over it.  Without this, the Distributed
    # Network Name resource fails in milliseconds because ${GuestClusterName}$
    # doesn't have "Create Computer Objects" in the OU.
    # This task runs as svc.azl.local (domain admin) — single hop to AD
    # via ADSI, no WinRM double-hop issue.
    # -----------------------------------------------------------------------
    Write-Host '[PRESTAGE] Looking up ${GuestClusterName}$ in AD...'
    `$searcher = New-Object DirectoryServices.DirectorySearcher([ADSI]'')
    `$searcher.Filter = '(&(objectClass=computer)(sAMAccountName=${GuestClusterName}$))'
    `$clusterAD = `$searcher.FindOne()
    if (-not `$clusterAD) { throw 'Could not find ${GuestClusterName}$ computer object in AD' }
    `$clusterDN = `$clusterAD.Properties['distinguishedname'][0]
    `$ouDN      = (`$clusterDN -split ',', 2)[1]
    Write-Host "[PRESTAGE] ${GuestClusterName}$ DN: `$clusterDN"
    Write-Host "[PRESTAGE] Target OU: `$ouDN"

    `$searcher.Filter = '(&(objectClass=computer)(sAMAccountName=${SOFSAccessPoint}$))'
    `$fsAD = `$searcher.FindOne()
    if (-not `$fsAD) {
        Write-Host '[PRESTAGE] Creating $SOFSAccessPoint computer object (disabled, pre-staged)...'
        `$ouEntry = [ADSI]"LDAP://`$ouDN"
        `$newComp = `$ouEntry.Children.Add('CN=$SOFSAccessPoint', 'computer')
        `$newComp.Properties['sAMAccountName'].Value    = '${SOFSAccessPoint}`$'
        `$newComp.Properties['userAccountControl'].Value = 4098  # WORKSTATION_TRUST_ACCOUNT | ACCOUNTDISABLE
        `$newComp.CommitChanges()
        Write-Host '[PRESTAGE] Computer object created.'
        `$searcher.Filter = '(&(objectClass=computer)(sAMAccountName=${SOFSAccessPoint}`$))'
        `$fsAD = `$searcher.FindOne()
    } else {
        Write-Host '[PRESTAGE] $SOFSAccessPoint AD object already exists.'
    }

    Write-Host '[PRESTAGE] Granting ${GuestClusterName}$ GenericAll on $SOFSAccessPoint AD object...'
    `$clusterSidBytes = `$clusterAD.Properties['objectsid'][0]
    `$clusterSid      = New-Object System.Security.Principal.SecurityIdentifier(`$clusterSidBytes, 0)
    `$fsDN    = `$fsAD.Properties['distinguishedname'][0]
    `$fsEntry = [ADSI]"LDAP://`$fsDN"
    `$rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        `$clusterSid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    `$fsEntry.ObjectSecurity.AddAccessRule(`$rule)
    `$fsEntry.CommitChanges()
    Write-Host '[PRESTAGE] Permission granted.'

    # -----------------------------------------------------------------------
    # PHASE 8: Add SOFS role (remove any Failed/partial first)
    # -----------------------------------------------------------------------
    Write-Host '[STEP1] Checking cluster group state...'
    `$sofsGroup = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
    Write-Host "[STEP1] Group state: `$(`$sofsGroup.State)"

    if (`$sofsGroup -and `$sofsGroup.State -eq 'Online') {
        Write-Host '[STEP1] Already Online — skipping Add.'
    } else {
        if (`$sofsGroup) {
            Write-Host "[STEP1] Removing failed/offline group (state=`$(`$sofsGroup.State))..."
            Remove-ClusterGroup -Name '$SOFSAccessPoint' -RemoveResources -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        }
        # Pre-flight: verify the pre-staged AD object is accessible and the CNO has permission
        Write-Host '[STEP1] Pre-flight: verifying AD object and DNS state...'
        `$preSearcher = New-Object DirectoryServices.DirectorySearcher([ADSI]'')
        `$preSearcher.Filter = '(&(objectClass=computer)(sAMAccountName=${SOFSAccessPoint}`$))'
        `$preAD = `$preSearcher.FindOne()
        if (`$preAD) {
            `$uac = `$preAD.Properties['useraccountcontrol'][0]
            Write-Host "[STEP1]   AD object found. userAccountControl=`$uac (4098=disabled/pre-staged, 4096=enabled)"
        } else {
            Write-Host '[STEP1]   WARNING: AD object not found — Add-ClusterScaleOutFileServerRole will create it (needs CNO OU permissions)'
        }
        # Flush DNS cache before attempting role add
        & ipconfig /flushdns 2>`$null | Out-Null

        Write-Host '[STEP1] Running Add-ClusterScaleOutFileServerRole (timeout 3 min)...'
        # Run in a background job with timeout — cmdlet can hang indefinitely if DNN resource won't come Online
        `$addJob = Start-Job -ScriptBlock {
            Import-Module FailoverClusters -ErrorAction SilentlyContinue
            Add-ClusterScaleOutFileServerRole -Name '$SOFSAccessPoint' -ErrorAction Stop
        }
        `$completed = `$addJob | Wait-Job -Timeout 180
        if (-not `$completed -or `$addJob.State -eq 'Running') {
            `$addJob | Stop-Job -PassThru | Remove-Job -Force
            # Dump cluster events for diagnosis
            Write-Host '[STEP1] TIMEOUT — cmdlet hung for 3 min. Checking cluster events...'
            Get-WinEvent -LogName 'Microsoft-Windows-FailoverClustering/Operational' -MaxEvents 20 -ErrorAction SilentlyContinue |
                Where-Object { `$_.TimeCreated -gt (Get-Date).AddMinutes(-5) } |
                ForEach-Object { Write-Host "  [`$(`$_.TimeCreated)] `$(`$_.Message)" }
            # Check if the role was partially created despite the hang
            `$sofsGroup = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
            if (`$sofsGroup) {
                Write-Host "[STEP1] Role exists in state: `$(`$sofsGroup.State)"
                # Try to bring it online manually
                if (`$sofsGroup.State -ne 'Online') {
                    Write-Host '[STEP1] Attempting Start-ClusterGroup...'
                    Start-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue | Out-Null
                    Start-Sleep -Seconds 10
                    `$sofsGroup = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
                    Write-Host "[STEP1] After Start-ClusterGroup: `$(`$sofsGroup.State)"
                }
            } else {
                throw "Add-ClusterScaleOutFileServerRole timed out after 3 min and no cluster group was created. Check cluster events."
            }
        } else {
            `$addJob | Receive-Job -ErrorAction Stop
            `$addJob | Remove-Job -Force
            Write-Host '[STEP1] Cmdlet returned successfully.'
        }

        Write-Host '[STEP1] Polling for Online (max 5 min)...'
        `$deadline = (Get-Date).AddMinutes(5)
        `$sofsGroup = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
        do {
            if (`$sofsGroup.State -eq 'Online') { break }
            Start-Sleep -Seconds 5
            `$sofsGroup = Get-ClusterGroup -Name '$SOFSAccessPoint' -ErrorAction SilentlyContinue
            Write-Host "[STEP1]   group=`$(`$sofsGroup.State)"
            # Dump resource states for debugging
            Get-ClusterResource -ErrorAction SilentlyContinue |
                Where-Object { `$_.OwnerGroup -eq '$SOFSAccessPoint' } |
                ForEach-Object { Write-Host "[STEP1]   resource: `$(`$_.Name) = `$(`$_.State)" }
        } while (`$sofsGroup.State -ne 'Online' -and (Get-Date) -lt `$deadline)

        if (`$sofsGroup.State -ne 'Online') {
            throw "Role '$SOFSAccessPoint' not Online after 5min. group=`$(`$sofsGroup.State)"
        }
    }
    Write-Host '[STEP1] Role Online.'

    # -----------------------------------------------------------------------
    # PHASE 8: Locate CSV and create FSLogix share (idempotent)
    # Note: no -Cluster param — running locally on a cluster node
    # -----------------------------------------------------------------------
    Write-Host '[STEP2] Locating CSV...'
    `$CSV = Get-ClusterSharedVolume | Where-Object { `$_.SharedVolumeInfo.FriendlyVolumeName -match '$S2DVolumeName' }
    if (-not `$CSV) { throw 'Could not find CSV for volume $S2DVolumeName' }
    `$CSVPath   = `$CSV.SharedVolumeInfo.FriendlyVolumeName
    `$SharePath = Join-Path `$CSVPath '$FSLogixShareName'
    Write-Host "[STEP2] SharePath: `$SharePath"
    if (-not (Test-Path `$SharePath)) { New-Item -Path `$SharePath -ItemType Directory -Force | Out-Null; Write-Host '[STEP2] Directory created.' }
    if (-not (Get-SmbShare -Name '$FSLogixShareName' -ScopeName '$SOFSAccessPoint' -ErrorAction SilentlyContinue)) {
        Write-Host '[STEP2] Creating SMB share...'
        New-SmbShare -Name '$FSLogixShareName' -Path `$SharePath -ScopeName '$SOFSAccessPoint' -ContinuouslyAvailable `$true -CachingMode None -FullAccess '$DomainNetBIOS\Domain Admins' -ChangeAccess '$DomainNetBIOS\Domain Users' -FolderEnumerationMode AccessBased -ErrorAction Stop | Out-Null
        Write-Host '[STEP2] Share created.'
    } else {
        Write-Host '[STEP2] Share already exists.'
    }

    'SUCCESS' | Out-File -FilePath '$resultFile8' -Encoding utf8
    Write-Host '[DONE] Phase 8 SUCCESS.'
} catch {
    `$errMsg = "FAILED: `$_"
    Write-Host `$errMsg
    `$errMsg | Out-File -FilePath '$resultFile8' -Encoding utf8
} finally {
    Stop-Transcript | Out-Null
}
"@

if (-not $WhatIf) {
    try {
        Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $using:scriptBody8 | Out-File -FilePath $using:taskScript8 -Encoding utf8 -Force
            Remove-Item $using:resultFile8 -Force -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName8 -Confirm:$false -ErrorAction SilentlyContinue
            $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$using:taskScript8`""
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
            Register-ScheduledTask -TaskName $using:taskName8 -Action $action -Settings $settings `
                -RunLevel Highest -User $using:domainUser8 -Password $using:plainPass8 -Force | Out-Null
            Start-ScheduledTask -TaskName $using:taskName8
            Write-Host "    Phase 8 task started." -ForegroundColor Green
        }

        Write-Log "  Waiting for Phase 8 task to complete (AD pre-stage + SOFS role + share)..."
        $deadline8 = (Get-Date).AddMinutes(12)
        do {
            Start-Sleep -Seconds 5
            $state8 = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
                (Get-ScheduledTask -TaskName $using:taskName8 -ErrorAction SilentlyContinue).State
            }
        } while ($state8 -eq 'Running' -and (Get-Date) -lt $deadline8)

        $readBack8 = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
            $r   = Get-Content $using:resultFile8 -Raw -ErrorAction SilentlyContinue
            $log = Get-Content $using:taskLog8    -Raw -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName8 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item $using:resultFile8  -Force -ErrorAction SilentlyContinue
            Remove-Item $using:taskScript8  -Force -ErrorAction SilentlyContinue
            Remove-Item $using:taskLog8     -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Result = $r; Log = $log }
        }
        $result8 = $readBack8.Result
        $log8    = $readBack8.Log

        if ($log8) {
            Write-Log "  --- Phase 8 task transcript ---" "HEADER"
            $log8 -split "`n" | ForEach-Object { Write-Host "    $_" }
            Write-Log "  --- end transcript ---" "HEADER"
        }

        if ($result8 -notmatch 'SUCCESS') {
            Write-Log "FATAL: Phase 8 task reported failure: $result8" "FAIL"
            exit 1
        }
    } catch {
        Write-Log "FATAL: Phase 8 task setup/execution failed: $_" "FAIL"
        exit 1
    }

    # -----------------------------------------------------------------------
    # PHASE 8 VERIFICATION
    # Query cluster and SMB subsystem directly.  Task writing 'SUCCESS' is not
    # sufficient — we confirm actual live state before proceeding to Phase 9.
    # Hard exit 1 if role is not Online or share does not exist.
    # -----------------------------------------------------------------------
    Write-Log "Phase 8 Verification — Confirming SOFS role Online and share exists" "HEADER"

    $p8verify = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction Stop -ScriptBlock {
        $grp      = Get-ClusterGroup -Name $using:SOFSAccessPoint -ErrorAction SilentlyContinue
        $grpState = if ($grp) { "$($grp.State)" } else { 'NotFound' }
        $share    = Get-SmbShare -Name $using:FSLogixShareName -ScopeName $using:SOFSAccessPoint -ErrorAction SilentlyContinue
        $dnnRes   = Get-ClusterResource -ErrorAction SilentlyContinue |
                        Where-Object { $_.ResourceType -eq 'Distributed Network Name' -and $_.OwnerGroup -eq $using:SOFSAccessPoint }
        $dnnState = if ($dnnRes) { "$($dnnRes.State)" } else { 'NotFound' }
        return [PSCustomObject]@{
            RoleState  = $grpState
            DnnState   = $dnnState
            ShareExist = ($null -ne $share)
            SharePath  = if ($share) { $share.Path } else { '' }
            ShareCA    = if ($share) { $share.ContinuouslyAvailable } else { $false }
        }
    }

    Write-Log "  SOFS role state       : $($p8verify.RoleState)"
    Write-Log "  DNN resource state    : $($p8verify.DnnState)"
    Write-Log "  Share exists          : $($p8verify.ShareExist)"
    Write-Log "  Share path            : $($p8verify.SharePath)"
    Write-Log "  ContinuouslyAvailable : $($p8verify.ShareCA)"

    $p8ok = $true

    if ($p8verify.RoleState -notmatch 'Online|^4$') {
        Write-Log "  [FAIL] SOFS role '$SOFSAccessPoint' is '$($p8verify.RoleState)' — expected Online." "FAIL"
        $p8ok = $false
    } else {
        Write-Log "  [PASS] SOFS role is Online." "PASS"
    }

    if (-not $p8verify.ShareExist) {
        Write-Log "  [FAIL] SMB share '$FSLogixShareName' (scope '$SOFSAccessPoint') was not found." "FAIL"
        $p8ok = $false
    } else {
        Write-Log "  [PASS] SMB share '$FSLogixShareName' exists at $($p8verify.SharePath)." "PASS"
    }

    if (-not $p8verify.ShareCA) {
        Write-Log "  [WARN] Share ContinuouslyAvailable = false — FSLogix requires CA shares." "WARN"
    } else {
        Write-Log "  [PASS] Share is ContinuouslyAvailable." "PASS"
    }

    if (-not $p8ok) {
        Write-Log "FATAL: Phase 8 verification failed — not proceeding to Phase 9." "FAIL"
        exit 1
    }

    Write-Log "Phase 8 complete and verified." "PASS"
} else {
    Write-Log "  [WhatIf] Would run Phase 8 scheduled task on $($VMNames[0])." "WARN"
}

# ===========================================================================
# PHASE 9: NTFS Permissions on FSLogix Share Directory
# Runs as a separate scheduled task on SOFS-01.
# VERIFICATION: After task success, the script reads the actual ACL back from
# disk and confirms all four expected ACEs are present before proceeding.
# Hard exit 1 if any required ACE is missing.
# ===========================================================================

Write-Log "Phase 9 — NTFS Permissions on FSLogix Share Directory" "HEADER"

$taskName9   = "SOFS-Phase9"
$taskScript9 = "C:\Windows\Temp\SOFS-Phase9.ps1"
$resultFile9 = "C:\Windows\Temp\SOFS-Phase9-result.txt"
$taskLog9    = "C:\Windows\Temp\SOFS-Phase9-log.txt"

$scriptBody9 = @"
Start-Transcript -Path '$taskLog9' -Force | Out-Null

try {
    `$share = Get-SmbShare -Name '$FSLogixShareName' -ScopeName '$SOFSAccessPoint' -ErrorAction Stop
    `$SharePath = `$share.Path
    Write-Host "[ACL] Share path resolved: `$SharePath"

    if (-not (Test-Path `$SharePath)) { throw "Share directory does not exist on disk: `$SharePath" }

    Write-Host '[ACL] Breaking inheritance and applying explicit NTFS ACEs...'
    `$acl = Get-Acl `$SharePath
    `$acl.SetAccessRuleProtection(`$true, `$false)
    `$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'CREATOR OWNER','Modify','ContainerInherit,ObjectInherit','InheritOnly','Allow')))
    `$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        '$DomainNetBIOS\Domain Users','Modify','None','None','Allow')))
    `$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        '$DomainNetBIOS\Domain Admins','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    `$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'NT AUTHORITY\SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -Path `$SharePath -AclObject `$acl
    Write-Host '[ACL] Set-Acl completed.'

    `$readAcl = Get-Acl `$SharePath
    Write-Host '[ACL] ACEs now on disk:'
    `$readAcl.Access | ForEach-Object {
        Write-Host "  `$(`$_.IdentityReference)  `$(`$_.FileSystemRights)  `$(`$_.AccessControlType)"
    }

    'SUCCESS' | Out-File -FilePath '$resultFile9' -Encoding utf8
    Write-Host '[DONE] Phase 9 SUCCESS.'
} catch {
    `$errMsg = "FAILED: `$_"
    Write-Host `$errMsg
    `$errMsg | Out-File -FilePath '$resultFile9' -Encoding utf8
} finally {
    Stop-Transcript | Out-Null
}
"@

if (-not $WhatIf) {
    try {
        Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction Stop -ScriptBlock {
            $using:scriptBody9 | Out-File -FilePath $using:taskScript9 -Encoding utf8 -Force
            Remove-Item $using:resultFile9 -Force -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName9 -Confirm:$false -ErrorAction SilentlyContinue
            $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$using:taskScript9`""
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
            Register-ScheduledTask -TaskName $using:taskName9 -Action $action -Settings $settings `
                -RunLevel Highest -User $using:domainUser8 -Password $using:plainPass8 -Force | Out-Null
            Start-ScheduledTask -TaskName $using:taskName9
            Write-Host "    Phase 9 task started." -ForegroundColor Green
        }

        Write-Log "  Waiting for Phase 9 task to complete (NTFS ACLs)..."
        $deadline9 = (Get-Date).AddMinutes(5)
        do {
            Start-Sleep -Seconds 5
            $state9 = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
                (Get-ScheduledTask -TaskName $using:taskName9 -ErrorAction SilentlyContinue).State
            }
        } while ($state9 -eq 'Running' -and (Get-Date) -lt $deadline9)

        $readBack9 = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction SilentlyContinue -ScriptBlock {
            $r   = Get-Content $using:resultFile9 -Raw -ErrorAction SilentlyContinue
            $log = Get-Content $using:taskLog9    -Raw -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $using:taskName9 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item $using:resultFile9  -Force -ErrorAction SilentlyContinue
            Remove-Item $using:taskScript9  -Force -ErrorAction SilentlyContinue
            Remove-Item $using:taskLog9     -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{ Result = $r; Log = $log }
        }
        $result9 = $readBack9.Result
        $log9    = $readBack9.Log

        if ($log9) {
            Write-Log "  --- Phase 9 task transcript ---" "HEADER"
            $log9 -split "`n" | ForEach-Object { Write-Host "    $_" }
            Write-Log "  --- end transcript ---" "HEADER"
        }

        if ($result9 -notmatch 'SUCCESS') {
            Write-Log "FATAL: Phase 9 task reported failure: $result9" "FAIL"
            exit 1
        }
    } catch {
        Write-Log "FATAL: Phase 9 task setup/execution failed: $_" "FAIL"
        exit 1
    }

    # -----------------------------------------------------------------------
    # PHASE 9 VERIFICATION
    # Read the ACL back from disk. Confirm all four required ACEs are present.
    # Hard exit 1 if any are missing — Phase 10 must not run on bad permissions.
    # -----------------------------------------------------------------------
    Write-Log "Phase 9 Verification — Confirming NTFS ACEs on share directory" "HEADER"

    $p9verify = Invoke-Command -ComputerName (Get-WinRMTarget -VMName $VMNames[0]) -Credential $Credential -ErrorAction Stop -ScriptBlock {
        $share = Get-SmbShare -Name $using:FSLogixShareName -ScopeName $using:SOFSAccessPoint -ErrorAction SilentlyContinue
        if (-not $share) { return [PSCustomObject]@{ Error = "Share not found"; Aces = @(); Path = '' } }
        $acl  = Get-Acl $share.Path -ErrorAction SilentlyContinue
        $aces = $acl.Access | ForEach-Object {
            [PSCustomObject]@{
                Identity = $_.IdentityReference.Value
                Rights   = "$($_.FileSystemRights)"
                Type     = "$($_.AccessControlType)"
            }
        }
        return [PSCustomObject]@{ Error = ''; Path = $share.Path; Aces = $aces }
    }

    if ($p9verify.Error) {
        Write-Log "FATAL: Phase 9 verification — $($p9verify.Error)" "FAIL"
        exit 1
    }

    Write-Log "  ACL on: $($p9verify.Path)"
    $p9verify.Aces | ForEach-Object { Write-Log "    $($_.Identity)  [$($_.Rights)]  $($_.Type)" }

    $expectedACEs = @(
        'CREATOR OWNER',
        "$DomainNetBIOS\Domain Users",
        "$DomainNetBIOS\Domain Admins",
        'NT AUTHORITY\SYSTEM'
    )
    $p9ok = $true
    foreach ($ace in $expectedACEs) {
        $found = $p9verify.Aces | Where-Object { $_.Identity -match [regex]::Escape($ace) }
        if ($found) {
            Write-Log "  [PASS] ACE present : $ace" "PASS"
        } else {
            Write-Log "  [FAIL] ACE MISSING : $ace" "FAIL"
            $p9ok = $false
        }
    }

    if (-not $p9ok) {
        Write-Log "FATAL: Phase 9 verification failed — required ACEs missing. See above." "FAIL"
        exit 1
    }

    Write-Log "Phase 9 complete and verified." "PASS"
} else {
    Write-Log "  [WhatIf] Would run Phase 9 scheduled task on $($VMNames[0])." "WARN"
}

# ===========================================================================
# PHASE 10: Antivirus Exclusion Guidance
# ===========================================================================

Write-Log "Phase 10 — Antivirus Exclusion Guidance" "HEADER"

$avGuidance = @"
  Configure the following AV exclusions on ALL SOFS VMs:
    - Entire CSV volume path containing the FSLogix share
    - *.VHD and *.VHDX file extensions
    - SMB-related processes if your AV inspects network traffic

  When AVD session hosts are deployed, also exclude:
    - Processes: frxsvc.exe, frxdrv.sys, frxccd.sys
    - Paths: %ProgramFiles%\FSLogix\Apps\*
    - Paths: %TEMP%\intlMountPoints\*
    - File types: *.VHD, *.VHDX
"@

Write-Log $avGuidance "WARN"

# ===========================================================================
# PHASE 11: Validation
# ===========================================================================

Write-Log "Phase 11 — Validation" "HEADER"

$ShareUNC = "\\$SOFSAccessPoint\$FSLogixShareName"

# Run all validation from SOFS-01 — management workstation is not on the compute network
Invoke-OnFirstNode -ScriptBlock {
    Write-Host "`n  --- Cluster Nodes ---" -ForegroundColor Cyan
    Get-ClusterNode | Format-Table Name, State -AutoSize

    Write-Host "  --- Cluster Shared Volumes ---" -ForegroundColor Cyan
    Get-ClusterSharedVolume | Format-Table Name, State -AutoSize

    Write-Host "  --- Virtual Disks ---" -ForegroundColor Cyan
    Get-VirtualDisk | Format-Table FriendlyName, ResiliencySettingName, OperationalStatus, HealthStatus -AutoSize

    Write-Host "  --- SOFS Role ---" -ForegroundColor Cyan
    $sofsGroup = Get-ClusterGroup | Where-Object { $_.GroupType -eq "ScaleOutFileServer" }
    $sofsGroup | Format-Table Name, OwnerNode, State -AutoSize

    if (($sofsGroup | Where-Object { $_.State -ne 'Online' }).Count -gt 0) {
        Write-Host "  [FAIL] SOFS role is not Online!" -ForegroundColor Red
    }

    Write-Host "  --- SOFS Share properties ---" -ForegroundColor Cyan
    Get-SmbShare -Name $using:FSLogixShareName -ScopeName $using:SOFSAccessPoint -ErrorAction SilentlyContinue |
        Format-Table Name, ScopeName, ContinuouslyAvailable, CachingMode, Path -AutoSize

    Write-Host "  --- Share ACL (access list) ---" -ForegroundColor Cyan
    $shareAcl = Get-SmbShareAccess -Name $using:FSLogixShareName -ScopeName $using:SOFSAccessPoint -ErrorAction SilentlyContinue
    if ($shareAcl) {
        $shareAcl | Format-Table Name, ScopeName, AccountName, AccessControlType, AccessRight -AutoSize
        Write-Host "  [PASS] Share ACL retrieved — $using:ShareUNC is present and queryable." -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Could not retrieve share ACL for $using:ShareUNC." -ForegroundColor Red
    }
}

# Sanity check role state — fail loud if SOFS role is not Online
$sofsState = Invoke-OnFirstNode -ScriptBlock {
    # Cast to string — ClusterGroupState enum deserializes as int (0=Online) over WinRM basic auth
    [string](Get-ClusterGroup -Name $using:SOFSAccessPoint -ErrorAction SilentlyContinue).State
}
if ($sofsState -ne 'Online') {
    Write-Log "FATAL: SOFS role '$SOFSAccessPoint' is '$sofsState' — share will not be accessible." "FAIL"
    Write-Log "  Check cluster events: Get-WinEvent -LogName 'Microsoft-Windows-FailoverClustering/Operational'" "FAIL"
    exit 1
}

if ($AntiAffinityEnabled) {
    Write-Log "Verifying anti-affinity on Azure Local cluster..."
    if (Get-Module -Name FailoverClusters -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Get-ClusterGroup -Cluster $AzureLocalClusterName |
                Where-Object { $_.Name -in $VMNames } |
                Format-Table Name, OwnerNode, State -AutoSize
        }
        catch {
            Write-Log "Could not verify anti-affinity placement: $_" "WARN"
        }
    } else {
        Write-Log "FailoverClusters module not installed — skipping anti-affinity verification." "WARN"
    }
}

Write-Log "Validation complete." "PASS"

# ===========================================================================
# TRUSTEDHOSTS CLEANUP
# ===========================================================================

if ($RemoveTrustedHosts -and $trustedHostsEntries.Count -gt 0) {
    Write-Log "Cleaning up TrustedHosts..." "HEADER"
    $currentTH = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
    if ($currentTH) {
        $existingEntries = $currentTH -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $cleanedEntries = $existingEntries | Where-Object { $_ -notin $trustedHostsEntries }
        $newValue = $cleanedEntries -join ','
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value $newValue -Force
        Write-Log "  Removed SOFS entries from TrustedHosts." "PASS"
    }
}

# ===========================================================================
# SUMMARY
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "SOFS DEPLOYMENT COMPLETE" "PASS"
Write-Log "========================================" "HEADER"
Write-Log "  Guest Cluster:       $GuestClusterName ($GuestClusterIP)"
Write-Log "  SOFS Access Point:   $SOFSAccessPoint"
Write-Log "  FSLogix Share:       \\$SOFSAccessPoint\$FSLogixShareName"
Write-Log "  S2D Volume:          $S2DVolumeName ($S2DVolumeSize, ${S2DNumberOfDataCopies}-way mirror)"
Write-Log "  Cloud Witness:       $WitnessStorageAccount"
Write-Log "  Anti-Affinity:       $AntiAffinityRuleName (enabled=$AntiAffinityEnabled)"
Write-Log "  Domain:              $DomainFQDN ($DomainNetBIOS)"
Write-Log "  Log File:            $logFile"
Write-Log ""
Write-Log "NEXT STEPS:" "HEADER"
Write-Log "  1. Configure AV exclusions (see Phase 10 guidance above)"
Write-Log "  2. When deploying AVD session hosts, set FSLogix VHDLocations to:"
Write-Log "     \\$SOFSAccessPoint\$FSLogixShareName"
Write-Log "  3. Optionally configure Cloud Cache for DR to Azure Blob"
