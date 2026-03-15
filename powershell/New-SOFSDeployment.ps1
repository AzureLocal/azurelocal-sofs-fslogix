<#
.SYNOPSIS
    Deploys a Scale Out File Server (SOFS) cluster role on an Azure Local failover cluster.

.DESCRIPTION
    This script:
      1. Enables the File Server cluster role on the specified failover cluster.
      2. Adds the SOFS cluster role (continuously available file server).
      3. Creates a Clustered Shared Volume directory for FSLogix profile containers.
      4. Creates and configures an SMB share for FSLogix.

.PARAMETER ParametersFile
    Path to a parameters.ps1 file containing environment-specific values.
    See parameters.example.ps1 for the expected variables.

.PARAMETER ClusterName
    Network name of the Azure Local failover cluster.

.PARAMETER SOFSName
    Name for the Scale Out File Server cluster role (client access point).

.PARAMETER ShareName
    Name of the SMB share to create (e.g. FSLogixProfiles).

.PARAMETER SharePath
    Local path on the Clustered Shared Volume where profile VHDs will be stored.

.EXAMPLE
    .\New-SOFSDeployment.ps1 -ParametersFile .\parameters.ps1

.EXAMPLE
    .\New-SOFSDeployment.ps1 -ClusterName "AZLHCI-CLUSTER" -SOFSName "SOFS01" `
        -ShareName "FSLogixProfiles" -SharePath "C:\ClusterStorage\Volume1\FSLogixProfiles"

.NOTES
    Requires RSAT-Clustering tools and domain credentials with cluster management permissions.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$SOFSName,

    [Parameter(Mandatory = $false)]
    [string]$ShareName,

    [Parameter(Mandatory = $false)]
    [string]$SharePath
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

# Allow CLI parameters to override the parameters file values
if (-not $ClusterName)  { $ClusterName  = $script:ClusterName }
if (-not $SOFSName)     { $SOFSName     = $script:SOFSName }
if (-not $ShareName)    { $ShareName    = $script:ShareName }
if (-not $SharePath)    { $SharePath    = $script:SharePath }
#endregion

#region Validate required parameters
foreach ($param in @("ClusterName","SOFSName","ShareName","SharePath")) {
    if (-not (Get-Variable -Name $param -ValueOnly -ErrorAction SilentlyContinue)) {
        throw "Required parameter '$param' is not set. Use -$param or provide a parameters file."
    }
}
#endregion

Write-Host "=== SOFS Deployment: $SOFSName on cluster $ClusterName ===" -ForegroundColor Cyan

#region Verify cluster connectivity
Write-Host "Verifying cluster connectivity..." -ForegroundColor Yellow
try {
    $cluster = Get-Cluster -Name $ClusterName
    Write-Host "  Connected to cluster: $($cluster.Name)" -ForegroundColor Green
}
catch {
    throw "Cannot connect to cluster '$ClusterName'. Ensure RSAT-Clustering is installed and you have network/domain access. Error: $_"
}
#endregion

#region Create SOFS cluster role
Write-Host "Adding Scale Out File Server cluster role '$SOFSName'..." -ForegroundColor Yellow
$existingRole = Get-ClusterGroup -Cluster $ClusterName -Name $SOFSName -ErrorAction SilentlyContinue
if ($existingRole) {
    Write-Host "  SOFS role '$SOFSName' already exists – skipping creation." -ForegroundColor DarkYellow
}
else {
    if ($PSCmdlet.ShouldProcess($ClusterName, "Add SOFS cluster role '$SOFSName'")) {
        Add-ClusterScaleOutFileServerRole -Cluster $ClusterName -Name $SOFSName
        Write-Host "  SOFS role '$SOFSName' created." -ForegroundColor Green
    }
}
#endregion

#region Create share directory on CSV
Write-Host "Creating share directory: $SharePath ..." -ForegroundColor Yellow
# Run the directory creation on a cluster node so the path resolves correctly
$clusterNode = (Get-ClusterNode -Cluster $ClusterName | Select-Object -First 1).Name
Invoke-Command -ComputerName $clusterNode -ScriptBlock {
    param($Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "  Directory created: $Path"
    }
    else {
        Write-Host "  Directory already exists: $Path"
    }
} -ArgumentList $SharePath
#endregion

#region Create SMB share
Write-Host "Creating SMB share '\\$SOFSName\$ShareName'..." -ForegroundColor Yellow
Invoke-Command -ComputerName $clusterNode -ScriptBlock {
    param($SOFSName, $ShareName, $SharePath)
    $existingShare = Get-SmbShare -Name $ShareName -ScopeName $SOFSName -ErrorAction SilentlyContinue
    if ($existingShare) {
        Write-Host "  SMB share '$ShareName' already exists on scope '$SOFSName' – skipping."
    }
    else {
        New-SmbShare -Name $ShareName `
                     -Path $SharePath `
                     -ScopeName $SOFSName `
                     -ContinuouslyAvailable $true `
                     -FolderEnumerationMode AccessBased `
                     -EncryptData $true
        Write-Host "  SMB share '\\$SOFSName\$ShareName' created."
    }
} -ArgumentList $SOFSName, $ShareName, $SharePath
#endregion

Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host "Share path: \\$SOFSName\$ShareName" -ForegroundColor Cyan
Write-Host "Run Test-SOFSDeployment.ps1 to validate the deployment." -ForegroundColor Cyan
