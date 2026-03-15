<#
.SYNOPSIS
    Deploy SOFS VMs on Azure Local via Bicep.

.DESCRIPTION
    Deploys Azure-side resources for a Scale-Out File Server cluster on Azure Local:
      Step 1. Resolves VM admin credentials from Key Vault (keyvault:// URI)
      Step 2. Deploys N SOFS VMs + data disks + cloud witness via Bicep template

    The template deploys at SUBSCRIPTION scope (targetScope = 'subscription').
    It creates the target resource group automatically if it doesn't exist,
    then deploys resources into that RG via Bicep modules.

    All deployment parameters are sourced from:
      - solutions/sofs/solution-sofs.yml   → SOFS-specific config (resource IDs, VM sizing, credentials)
      - configs/infrastructure-<env>.yml   → shared config (site, identity)

    Bicep templates (subscription-scope wrapper → resource-group-scope module):
      - main.bicep                → creates RG → sofs-resources.bicep + witness-storage.bicep

    The .bicepparam file is EXAMPLE ONLY — this script builds
    -TemplateParameterObject at runtime. Never commit secrets to params files.

    Post-deployment guest OS configuration (S2D, failover clustering, SOFS role,
    SMB share, NTFS permissions) is handled by:
      ../powershell/Configure-SOFS-Cluster.ps1

.PARAMETER SolutionConfigPath
    Path to the generated solution config YAML.
    Default: solutions/sofs/solution-sofs.yml (relative to repo root).

.PARAMETER ConfigPath
    Path to infrastructure YAML for shared variables (AD, identity, site).
    Default: auto-detected from solution config _generated.source_files.

.PARAMETER WhatIf
    Dry-run mode — validates templates without deploying.

.EXAMPLE
    # Full deployment:
    .\Deploy-SOFS-Azure.ps1

    # Dry run (validates template):
    .\Deploy-SOFS-Azure.ps1 -WhatIf

    # Explicit config paths:
    .\Deploy-SOFS-Azure.ps1 -SolutionConfigPath ".\solutions\sofs\solution-sofs.yml" -ConfigPath ".\config\variables.yml"
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string] $SolutionConfigPath = "",
    [string] $ConfigPath         = "",
    [switch] $WhatIf
)

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
$bicepDir      = $PSScriptRoot
$bicepTemplate = Join-Path $bicepDir "main.bicep"

if (-not (Test-Path $bicepTemplate)) {
    Write-Error "Bicep template not found: $bicepTemplate"
    exit 1
}

# ---------------------------------------------------------------------------
# Load solution config (PRIMARY source for all SOFS-specific values)
# ---------------------------------------------------------------------------
$repoRoot = (Get-Location).Path

if ($SolutionConfigPath -eq "") {
    $SolutionConfigPath = Join-Path $repoRoot "solutions\sofs\solution-sofs.yml"
}
if (-not (Test-Path $SolutionConfigPath)) {
    Write-Error "Solution config not found: $SolutionConfigPath`nGenerate it first: .\tools\Generate-SolutionConfig.ps1 -Solution sofs-azure-local -Environment <env>"
    exit 1
}

try {
    $sol = Get-Content $SolutionConfigPath -Raw | ConvertFrom-Yaml
    Write-Host "[INFO] Loaded solution config: $SolutionConfigPath" -ForegroundColor Cyan
} catch {
    Write-Error "Could not parse solution YAML: $_"
    exit 1
}

# Extract solution sections
$sofsCfg = $sol.compute_wsfc                                             # compute.wsfc variables

if (-not $sofsCfg) {
    Write-Error "Solution config missing 'compute_wsfc' section. Regenerate with Generate-SolutionConfig.ps1."
    exit 1
}

# ---------------------------------------------------------------------------
# Load infrastructure YAML (SUPPLEMENTAL — for values not in solution config)
# ---------------------------------------------------------------------------
$cfg = $null
if ($ConfigPath -eq "") {
    $sourceFiles = $sol._generated.source_files
    if ($sourceFiles) {
        $infraFile = $sourceFiles | Where-Object { $_ -match 'infrastructure-' }
        if ($infraFile) {
            $ConfigPath = Join-Path $repoRoot $infraFile
        }
    }
}
if ($ConfigPath -ne "" -and (Test-Path $ConfigPath)) {
    try {
        $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Yaml
        Write-Host "[INFO] Loaded infra config: $ConfigPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "Could not parse infrastructure YAML: $_"
    }
}

# ---------------------------------------------------------------------------
# Resolve deployment parameters from solution config
# ---------------------------------------------------------------------------
$VmCount             = [int]$sofsCfg.wsfc_sofs_vm_count                  # compute.wsfc.wsfc_sofs_vm_count
$VmPrefix            = $sofsCfg.wsfc_sofs_vm_prefix                      # compute.wsfc.wsfc_sofs_vm_prefix
$VmProcessors        = [int]$sofsCfg.wsfc_sofs_vm_processors             # compute.wsfc.wsfc_sofs_vm_processors
$VmMemoryMB          = [int]$sofsCfg.wsfc_sofs_vm_memory_mb              # compute.wsfc.wsfc_sofs_vm_memory_mb
$DataDiskCount       = [int]$sofsCfg.wsfc_sofs_data_disk_count           # compute.wsfc.wsfc_sofs_data_disk_count
$DataDiskSizeGB      = [int]$sofsCfg.wsfc_sofs_data_disk_size_gb         # compute.wsfc.wsfc_sofs_data_disk_size_gb
$SubscriptionId      = $sofsCfg.wsfc_sofs_subscription_id                # compute.wsfc.wsfc_sofs_subscription_id
$ResourceGroup       = $sofsCfg.wsfc_sofs_resource_group                 # compute.wsfc.wsfc_sofs_resource_group
$Location            = $sofsCfg.wsfc_sofs_location                       # compute.wsfc.wsfc_sofs_location
$CustomLocationId    = $sofsCfg.wsfc_sofs_custom_location_id             # compute.wsfc.wsfc_sofs_custom_location_id
$LogicalNetworkId    = $sofsCfg.wsfc_sofs_logical_network_id             # compute.wsfc.wsfc_sofs_logical_network_id
$GalleryImageName    = $sofsCfg.wsfc_sofs_gallery_image_name             # compute.wsfc.wsfc_sofs_gallery_image_name
$StoragePathId       = $sofsCfg.wsfc_sofs_storage_path_id                # compute.wsfc.wsfc_sofs_storage_path_id
$AdminUsername       = $sofsCfg.wsfc_sofs_vm_admin_username              # compute.wsfc.wsfc_sofs_vm_admin_username
$AdminPassUri        = $sofsCfg.wsfc_sofs_vm_admin_password              # compute.wsfc.wsfc_sofs_vm_admin_password
$CloudWitnessName    = $sofsCfg.wsfc_sofs_cloud_witness_name             # compute.wsfc.wsfc_sofs_cloud_witness_name

# Validate required values
$requiredValues = @{
    "VmCount"          = $VmCount
    "VmPrefix"         = $VmPrefix
    "SubscriptionId"   = $SubscriptionId
    "ResourceGroup"    = $ResourceGroup
    "Location"         = $Location
    "CustomLocationId" = $CustomLocationId
    "LogicalNetworkId" = $LogicalNetworkId
    "GalleryImageName" = $GalleryImageName
    "StoragePathId"    = $StoragePathId
    "AdminUsername"    = $AdminUsername
    "AdminPassUri"     = $AdminPassUri
    "CloudWitnessName" = $CloudWitnessName
}
$missing = $requiredValues.GetEnumerator() | Where-Object { [string]::IsNullOrWhiteSpace($_.Value) -or $_.Value -eq 0 }
if ($missing) {
    Write-Error "Missing required values from solution config: $($missing.Key -join ', ')`nRegenerate: .\tools\Generate-SolutionConfig.ps1 -Solution sofs-azure-local -Environment <env>"
    exit 1
}

$TotalDisks   = $VmCount * $DataDiskCount
$TotalPoolGB  = $VmCount * $DataDiskCount * $DataDiskSizeGB
$TotalPoolTB  = [math]::Round($TotalPoolGB / 1024, 1)

Write-Host ""
Write-Host "=== SOFS Deployment Parameters (from solution config) ===" -ForegroundColor Cyan
Write-Host "  Resource Group:    $ResourceGroup"
Write-Host "  Subscription:      $SubscriptionId"
Write-Host "  Location:          $Location"
Write-Host "  VMs:               $VmCount × $VmPrefix-01..$VmPrefix-$('{0:D2}' -f $VmCount)"
Write-Host "  VM Size:           ${VmProcessors} vCPU / ${VmMemoryMB} MB"
Write-Host "  Data Disks:        $DataDiskCount × ${DataDiskSizeGB} GB per VM ($TotalDisks total)"
Write-Host "  S2D Pool:          $TotalPoolTB TB raw"
Write-Host "  Cloud Witness:     $CloudWitnessName"
Write-Host "  Gallery Image:     $GalleryImageName"
Write-Host ""

# ---------------------------------------------------------------------------
# Key Vault helper — resolves keyvault://<vault>/<secret> URIs
# ---------------------------------------------------------------------------
function Resolve-KeyVaultRef {
    param([string]$KvUri)
    if ($KvUri -notmatch '^keyvault://([^/]+)/(.+)$') { Write-Host "  Not a Key Vault URI: $KvUri" -ForegroundColor Yellow; return $null }
    $vaultName  = $Matches[1]
    $secretName = $Matches[2]

    if (Get-Module -Name Az.KeyVault -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Write-Host "  Retrieving '$secretName' from '$vaultName' (Az.KeyVault)..."
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name $secretName -AsPlainText -ErrorAction Stop
            if ($secret) { Write-Host "  Secret retrieved." -ForegroundColor Green; return $secret }
            Write-Host "  Az.KeyVault returned no secret." -ForegroundColor Yellow
        } catch { Write-Host "  Az.KeyVault failed: $_" -ForegroundColor Yellow }
        Write-Host "  Falling back to Azure CLI..." -ForegroundColor Yellow
    } else {
        Write-Host "  Az.KeyVault module not found — trying Azure CLI..." -ForegroundColor Yellow
    }

    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if (-not $azCmd) { Write-Host "  Azure CLI (az) not found." -ForegroundColor Yellow; return $null }
        Write-Host "  Retrieving '$secretName' from '$vaultName' (az CLI)..."
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $val    = (& az keyvault secret show --vault-name $vaultName --name $secretName --query value --output tsv --only-show-errors 2>$tmpErr)
        $azErr  = (Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue).Trim()
        Remove-Item $tmpErr -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($val)) {
            $errDetail = if ($azErr) { ": $azErr" } else { " (exit $LASTEXITCODE)" }
            Write-Host "  az CLI failed$errDetail." -ForegroundColor Yellow
            return $null
        }
        Write-Host "  Secret retrieved (az CLI)." -ForegroundColor Green
        return $val
    } catch { Write-Host "  az CLI failed: $_" -ForegroundColor Yellow; return $null }
}

# ---------------------------------------------------------------------------
# Step 1 — Resolve VM admin credentials
# ---------------------------------------------------------------------------
Write-Host "=== Step 1: Resolve VM Admin Credentials ===" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "[DRY RUN] Using placeholder credentials for validation" -ForegroundColor Yellow
    $adminPassPlain = "WHATIF-PLACEHOLDER-ADMIN-PASSWORD"
} else {
    Write-Host "  Resolving admin password from Key Vault..."
    $adminPassPlain = Resolve-KeyVaultRef -KvUri $AdminPassUri
    if (-not $adminPassPlain) {
        Write-Host "  [WARN] KV unavailable — prompting for admin password" -ForegroundColor Yellow
        $adminPassPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(
                (Read-Host -AsSecureString -Prompt "Enter local admin password for SOFS VMs")))
    }
}

Write-Host "[PASS] Credentials ready" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2 — Deploy Bicep template
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Step 2: Deploy Bicep Template ===" -ForegroundColor Cyan
Write-Host "  Template:  $bicepTemplate"
Write-Host "  Target RG: $ResourceGroup"
Write-Host "  Subscription: $SubscriptionId"
Write-Host ""

# Set subscription context
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

$deploymentName = "sofs-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployParams = @{
    Name                    = $deploymentName
    Location                = $Location
    TemplateFile            = $bicepTemplate
    TemplateParameterObject = @{
        resourceGroupName = $ResourceGroup
        location          = $Location
        vmCount           = $VmCount
        vmPrefix          = $VmPrefix
        vmProcessors      = $VmProcessors
        vmMemoryMB        = $VmMemoryMB
        dataDiskCount     = $DataDiskCount
        dataDiskSizeGB    = $DataDiskSizeGB
        customLocationId  = $CustomLocationId
        logicalNetworkId  = $LogicalNetworkId
        galleryImageId    = $GalleryImageName
        storagePathId     = $StoragePathId
        adminUsername     = $AdminUsername
        adminPassword     = $adminPassPlain
        cloudWitnessName  = $CloudWitnessName
        tags              = @{
            project  = "SOFS"
            workload = "FSLogix"
            solution = "sofs-azure-local"
        }
    }
}

if ($WhatIf) {
    Write-Host "[DRY RUN] Validating template (WhatIf mode)..." -ForegroundColor Yellow
    $validateParams = $deployParams.Clone()
    $validateParams.Remove('Name')
    $result = Test-AzDeployment @validateParams
    if ($result) {
        Write-Host "[FAIL] Validation errors:" -ForegroundColor Red
        $result | Format-List
        exit 1
    } else {
        Write-Host "[PASS] Template validation passed" -ForegroundColor Green
    }
} else {
    Write-Host "Deploying $deploymentName ..." -ForegroundColor White
    try {
        $deployment = New-AzSubscriptionDeployment @deployParams -Verbose
        Write-Host ""
        Write-Host "[PASS] Deployment completed: $($deployment.ProvisioningState)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Deployed VMs:" -ForegroundColor Cyan
        $deployment.Outputs.deployedVMs.Value | ForEach-Object {
            Write-Host "  - $($_.vmName) (Arc: $($_.arcMachineId))"
        }
        Write-Host ""
        Write-Host "  S2D Pool:        $($deployment.Outputs.s2dPoolSizeGB.Value / 1024) TB ($($deployment.Outputs.totalDataDisks.Value) disks)"
        Write-Host "  Cloud Witness:   $($deployment.Outputs.witnessStorageAccountName.Value)"
    } catch {
        Write-Error "Deployment failed: $_"
        Write-Host ""
        Write-Host "Check deployment operations:" -ForegroundColor Yellow
        Write-Host "  az deployment sub list --subscription $SubscriptionId -o table"
        Write-Host "  az deployment operation sub list --name $deploymentName --subscription $SubscriptionId -o table"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
$adminPassPlain = $null
[System.GC]::Collect()

Write-Host ""
Write-Host @"

  NEXT STEPS:
    1. Verify VMs are domain-joined and on the compute network
    2. Run the guest cluster configuration script:
       .\solutions\sofs\powershell\Configure-SOFS-Cluster.ps1

"@ -ForegroundColor Green
