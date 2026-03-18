<#
.SYNOPSIS
    Compiles the Bicep source into the ARM JSON template.
.DESCRIPTION
    Runs 'az bicep build' against src/bicep/main.bicep and writes the output
    to src/arm/azuredeploy.json.  This script should be run whenever the Bicep
    source changes to keep the ARM artefact in sync.
.EXAMPLE
    .\Build-ARM-Template.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot   = (Resolve-Path "$PSScriptRoot\..\..").Path
$bicepFile  = Join-Path $repoRoot 'src\bicep\main.bicep'
$armFile    = Join-Path $repoRoot 'src\arm\azuredeploy.json'

if (-not (Test-Path $bicepFile)) {
    throw "Bicep source not found: $bicepFile"
}

Write-Host "Compiling $bicepFile -> $armFile" -ForegroundColor Cyan
az bicep build -f $bicepFile --outfile $armFile
if ($LASTEXITCODE -ne 0) {
    throw "Bicep compilation failed (exit code $LASTEXITCODE)"
}

Write-Host "ARM template updated: $armFile" -ForegroundColor Green
