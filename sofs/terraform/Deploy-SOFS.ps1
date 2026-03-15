#Requires -Version 7.0
<#
.SYNOPSIS
    SOFS deployment — Terraform only. Ansible runs automatically via cloud-init.

.DESCRIPTION
    Single-phase deployment: terraform init → plan → apply.

    Terraform provisions:
      - Azure Local SOFS VMs (azapi_resource)
      - Cloud witness storage account
      - Ansible controller VM (when guest_config_engine = ansible_create)
        Cloud-init installs Ansible, writes the inventory + playbook, and
        runs ansible-playbook — fully autonomous, no SSH from laptop required.
      - Generated Ansible inventory (local file for reference/debug)

    No SSH. No PSRemoting. No prompts. Everything is config-driven.

.PARAMETER WhatIf
    Dry-run mode: terraform plan only, no apply.

.EXAMPLE
    .\Deploy-SOFS.ps1

.EXAMPLE
    .\Deploy-SOFS.ps1 -WhatIf

.NOTES
    Prerequisites: Terraform >= 1.0, Azure CLI (az).
    Run from any directory — uses $PSScriptRoot for path resolution.
#>
[CmdletBinding()]
param(
    [switch] $WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TerraformDir = Join-Path $PSScriptRoot "terraform"
$TfVarsFile   = Join-Path $TerraformDir "terraform.tfvars"

# ---------------------------------------------------------------------------
# Terraform — provisions everything; cloud-init runs Ansible automatically
# ---------------------------------------------------------------------------
Write-Host "`n[----] Terraform — Deploy SOFS" -ForegroundColor Cyan

Push-Location $TerraformDir
try {
    terraform init -upgrade
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed (exit $LASTEXITCODE)" }

    terraform plan "-var-file=$TfVarsFile" -out=tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed (exit $LASTEXITCODE)" }

    if (-not $WhatIf) {
        terraform apply tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform apply failed (exit $LASTEXITCODE)" }
        Remove-Item tfplan -ErrorAction SilentlyContinue
    } else {
        Write-Host "[WhatIf] Plan generated — skipping apply." -ForegroundColor Yellow
        Remove-Item tfplan -ErrorAction SilentlyContinue
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$controllerName = (terraform -chdir="$TerraformDir" output -raw ansible_controller_admin_username 2>$null)
$controllerRg   = (terraform -chdir="$TerraformDir" output -raw resource_group_name 2>$null)

Write-Host "`n[PASS] Terraform apply complete." -ForegroundColor Green
Write-Host "[INFO] Guest cluster config runs automatically via cloud-init on the Ansible controller." -ForegroundColor Gray
Write-Host "[INFO] To check Ansible progress:" -ForegroundColor Gray
Write-Host "  az vm run-command invoke --command-id RunShellScript --name vm-ansible-sofs-eus-01 --resource-group $controllerRg --scripts 'tail -50 /home/$controllerName/sofs/ansible-run.log'" -ForegroundColor DarkGray
