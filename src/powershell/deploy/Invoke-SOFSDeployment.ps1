<#
.SYNOPSIS
    Invoke-SOFSDeployment.ps1 — Orchestrator for end-to-end SOFS deployment.

.DESCRIPTION
    Wrapper script that runs the full SOFS deployment pipeline in sequence:
      Phase 1: Deploy-SOFS-Azure.ps1    — Azure resource deployment (RG, witness, NICs, VMs, disks)
      Phase 2: Configure-SOFS-Cluster.ps1 — Guest OS configuration over WinRM (cluster, S2D, SOFS, shares)

    Tracks each phase in a JSON state file so that a failed run can be resumed
    from the last incomplete phase without re-running completed work.

    Also supports:
      -Destroy  — tears down all Azure resources via Remove-SOFSDeployment.ps1
      -SkipDeploy  — skip Phase 1, run only Phase 2 (VMs already exist)
      -SkipConfigure — skip Phase 2, run only Phase 1

.PARAMETER SolutionConfigPath
    Path to variables.yml. Default: config\variables.yml relative to CWD.

.PARAMETER Credential
    PSCredential override — passed to both Deploy and Configure scripts.

.PARAMETER WinRMTransport
    WinRM transport for Configure phase: basic (default) or kerberos.

.PARAMETER DomainJoinWaitMinutes
    Max minutes to wait for VMs to become domain-joined before starting Phase 2.
    Default: 15. Set to 0 to skip the wait (VMs already joined).

.PARAMETER SkipDeploy
    Skip Phase 1 (Azure resource deployment). Use when VMs already exist.

.PARAMETER SkipConfigure
    Skip Phase 2 (guest OS configuration). Use when you only need infra.

.PARAMETER Destroy
    Run Remove-SOFSDeployment.ps1 instead of the deployment pipeline.

.PARAMETER RemoveResourceGroup
    When used with -Destroy, also deletes the resource group.

.PARAMETER Force
    Resume from the last incomplete phase, ignoring the state file lock.

.PARAMETER WhatIf
    Dry-run mode — passed through to child scripts.

.PARAMETER LogPath
    Override log directory. Default: logs\sofs\

.EXAMPLE
    # Full end-to-end deployment
    .\Invoke-SOFSDeployment.ps1

    # Resume after a failed Configure phase
    .\Invoke-SOFSDeployment.ps1 -Force

    # Deploy infra only (no guest config)
    .\Invoke-SOFSDeployment.ps1 -SkipConfigure

    # Configure only (VMs already exist and are domain-joined)
    .\Invoke-SOFSDeployment.ps1 -SkipDeploy -DomainJoinWaitMinutes 0

    # Tear down everything
    .\Invoke-SOFSDeployment.ps1 -Destroy

.NOTES
    Author:  Hybrid Cloud Solutions LLC
    Version: 1.0
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]       $SolutionConfigPath      = "",
    [PSCredential] $Credential              = $null,
    [string]       $WinRMTransport          = "basic",
    [int]          $DomainJoinWaitMinutes   = 15,
    [switch]       $SkipDeploy,
    [switch]       $SkipConfigure,
    [switch]       $Destroy,
    [switch]       $RemoveResourceGroup,
    [switch]       $Force,
    [switch]       $WhatIf,
    [string]       $LogPath                 = ""
)

$ErrorActionPreference = "Stop"

# ===========================================================================
# PATHS
# ===========================================================================

$scriptDir = $PSScriptRoot
$repoRoot  = (Get-Location).Path
$stateFile = Join-Path $repoRoot "logs\sofs\deployment-state.json"
$logDir    = if ($LogPath -ne "") { $LogPath } else { Join-Path $repoRoot "logs\sofs" }
$logFile   = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')_Invoke-SOFSDeployment.log"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# ===========================================================================
# LOGGING
# ===========================================================================

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
# STATE MANAGEMENT
# ===========================================================================

function Get-DeploymentState {
    if (Test-Path $stateFile) {
        try { return Get-Content $stateFile -Raw | ConvertFrom-Json }
        catch { return $null }
    }
    return $null
}

function Save-DeploymentState {
    param([object]$State)
    $State | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding utf8
}

function New-DeploymentState {
    return [PSCustomObject]@{
        started_at     = (Get-Date).ToString("o")
        updated_at     = (Get-Date).ToString("o")
        config_path    = $SolutionConfigPath
        phases         = [PSCustomObject]@{
            deploy    = [PSCustomObject]@{ status = "not_started"; started_at = $null; completed_at = $null; exit_code = $null; log_file = $null }
            configure = [PSCustomObject]@{ status = "not_started"; started_at = $null; completed_at = $null; exit_code = $null; log_file = $null }
        }
        overall_status = "in_progress"
    }
}

# ===========================================================================
# PHASE RUNNER
# ===========================================================================

function Invoke-Phase {
    param(
        [string]$PhaseName,
        [string]$ScriptPath,
        [hashtable]$Arguments
    )

    $state.phases.$PhaseName.status     = "running"
    $state.phases.$PhaseName.started_at = (Get-Date).ToString("o")
    $state.updated_at = (Get-Date).ToString("o")
    Save-DeploymentState $state

    Write-Log "========================================" "HEADER"
    Write-Log "PHASE: $PhaseName — START" "HEADER"
    Write-Log "Script: $ScriptPath" "INFO"
    Write-Log "========================================" "HEADER"

    $phaseLogFile = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd_HHmmss')_${PhaseName}.log"
    $Arguments['LogPath'] = $phaseLogFile
    $state.phases.$PhaseName.log_file = $phaseLogFile

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = 0

    try {
        & $ScriptPath @Arguments
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE }
    } catch {
        Write-Log "Phase '$PhaseName' threw an exception: $_" "FAIL"
        $exitCode = 1
    }

    $sw.Stop()
    $elapsed = $sw.Elapsed.ToString("hh\:mm\:ss")

    $state.phases.$PhaseName.exit_code    = $exitCode
    $state.phases.$PhaseName.completed_at = (Get-Date).ToString("o")

    if ($exitCode -eq 0) {
        $state.phases.$PhaseName.status = "completed"
        Write-Log "PHASE: $PhaseName — COMPLETED ($elapsed)" "PASS"
    } else {
        $state.phases.$PhaseName.status = "failed"
        Write-Log "PHASE: $PhaseName — FAILED (exit code $exitCode, $elapsed)" "FAIL"
        Write-Log "  Log: $phaseLogFile" "FAIL"
    }

    $state.updated_at = (Get-Date).ToString("o")
    Save-DeploymentState $state

    return $exitCode
}

# ===========================================================================
# DOMAIN JOIN WAIT
# ===========================================================================

function Wait-DomainJoin {
    param([int]$TimeoutMinutes)

    if ($TimeoutMinutes -le 0) {
        Write-Log "Domain join wait skipped (DomainJoinWaitMinutes = 0)." "INFO"
        return $true
    }

    Write-Log "Waiting up to $TimeoutMinutes min for domain join extensions to complete..." "HEADER"

    # Load config to get VM names and RG
    if (-not $script:sol) {
        Import-Module powershell-yaml -ErrorAction Stop
        $cfgPath = $SolutionConfigPath
        if ($cfgPath -eq "") {
            $cfgPath = Join-Path $repoRoot "config\variables.yml"
        }
        $script:sol = Get-Content $cfgPath -Raw | ConvertFrom-Yaml
    }

    $vmPrefix = $script:sol.vm.prefix
    $vmCount  = [int]$script:sol.vm.count
    $rg       = $script:sol.azure.resource_group

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $allJoined = $false

    while ((Get-Date) -lt $deadline) {
        $joinedCount = 0
        for ($i = 1; $i -le $vmCount; $i++) {
            $vmName = "{0}-{1:D2}" -f $vmPrefix, $i
            $extStatus = az connectedmachine extension show `
                --resource-group $rg `
                --machine-name $vmName `
                --name JsonADDomainExtension `
                --query "provisioningState" -o tsv 2>$null
            if ($extStatus -eq "Succeeded") { $joinedCount++ }
        }

        Write-Log "  Domain join: $joinedCount / $vmCount VMs ready."
        if ($joinedCount -ge $vmCount) {
            $allJoined = $true
            break
        }

        Start-Sleep -Seconds 30
    }

    if ($allJoined) {
        Write-Log "All $vmCount VMs domain-joined." "PASS"
        return $true
    } else {
        Write-Log "Timed out waiting for domain join ($TimeoutMinutes min)." "FAIL"
        return $false
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

Write-Log "========================================" "HEADER"
Write-Log "SOFS DEPLOYMENT ORCHESTRATOR" "HEADER"
Write-Log "========================================" "HEADER"
Write-Log "Log file: $logFile"

$overallSw = [System.Diagnostics.Stopwatch]::StartNew()

# --- DESTROY MODE ---
if ($Destroy) {
    Write-Log "Mode: DESTROY" "WARN"
    $removeScript = Join-Path $scriptDir "Remove-SOFSDeployment.ps1"
    if (-not (Test-Path $removeScript)) {
        Write-Log "Remove script not found: $removeScript" "FAIL"
        exit 1
    }

    $removeArgs = @{}
    if ($SolutionConfigPath -ne "") { $removeArgs['SolutionConfigPath'] = $SolutionConfigPath }
    if ($RemoveResourceGroup)       { $removeArgs['RemoveResourceGroup'] = $true }
    if ($WhatIf)                    { $removeArgs['WhatIf'] = $true }

    & $removeScript @removeArgs
    exit $LASTEXITCODE
}

# --- RESOLVE STATE ---
$state = Get-DeploymentState

if ($state -and $state.overall_status -eq "completed" -and -not $Force) {
    Write-Log "Previous deployment completed successfully. Use -Force to re-run." "WARN"
    Write-Log "  State file: $stateFile" "INFO"
    exit 0
}

if ($state -and $state.overall_status -eq "in_progress" -and -not $Force) {
    # Check which phase failed and offer resume
    $failedPhase = $null
    if ($state.phases.deploy.status -eq "failed")    { $failedPhase = "deploy" }
    if ($state.phases.configure.status -eq "failed")  { $failedPhase = "configure" }

    if ($failedPhase) {
        Write-Log "Previous run has a failed phase: $failedPhase. Resuming with -Force..." "WARN"
        # Fall through to resume logic below
    } elseif ($state.phases.deploy.status -eq "running" -or $state.phases.configure.status -eq "running") {
        Write-Log "A deployment appears to be in progress. Use -Force to override." "FAIL"
        Write-Log "  State file: $stateFile" "INFO"
        exit 1
    }
}

# Create fresh state or resume
if (-not $state -or $Force -and $state.overall_status -eq "completed") {
    $state = New-DeploymentState
    Save-DeploymentState $state
}

# --- BUILD COMMON ARGS ---
$commonArgs = @{}
if ($SolutionConfigPath -ne "") { $commonArgs['SolutionConfigPath'] = $SolutionConfigPath }
if ($Credential)                { $commonArgs['Credential'] = $Credential }
if ($WhatIf)                    { $commonArgs['WhatIf'] = $true }

# --- PHASE 1: DEPLOY ---
$deployNeeded = (-not $SkipDeploy) -and ($state.phases.deploy.status -ne "completed")

if ($SkipDeploy) {
    Write-Log "Phase 1 (Deploy) — SKIPPED by user." "WARN"
    $state.phases.deploy.status = "skipped"
    $state.updated_at = (Get-Date).ToString("o")
    Save-DeploymentState $state
} elseif ($state.phases.deploy.status -eq "completed") {
    Write-Log "Phase 1 (Deploy) — Already completed. Skipping." "PASS"
} elseif ($deployNeeded) {
    $deployScript = Join-Path $scriptDir "Deploy-SOFS-Azure.ps1"
    if (-not (Test-Path $deployScript)) {
        Write-Log "Deploy script not found: $deployScript" "FAIL"
        exit 1
    }

    $deployExitCode = Invoke-Phase -PhaseName "deploy" -ScriptPath $deployScript -Arguments $commonArgs
    if ($deployExitCode -ne 0) {
        Write-Log "Deployment pipeline stopped — Phase 1 failed." "FAIL"
        $state.overall_status = "in_progress"
        Save-DeploymentState $state
        exit 1
    }
}

# --- DOMAIN JOIN WAIT ---
if (-not $SkipConfigure -and $state.phases.configure.status -ne "completed" -and -not $WhatIf) {
    if (-not $SkipDeploy -and $DomainJoinWaitMinutes -gt 0) {
        $joined = Wait-DomainJoin -TimeoutMinutes $DomainJoinWaitMinutes
        if (-not $joined) {
            Write-Log "Cannot proceed to Phase 2 — domain join incomplete." "FAIL"
            $state.overall_status = "in_progress"
            Save-DeploymentState $state
            exit 1
        }
    }
}

# --- PHASE 2: CONFIGURE ---
$configureNeeded = (-not $SkipConfigure) -and ($state.phases.configure.status -ne "completed")

if ($SkipConfigure) {
    Write-Log "Phase 2 (Configure) — SKIPPED by user." "WARN"
    $state.phases.configure.status = "skipped"
    $state.updated_at = (Get-Date).ToString("o")
    Save-DeploymentState $state
} elseif ($state.phases.configure.status -eq "completed") {
    Write-Log "Phase 2 (Configure) — Already completed. Skipping." "PASS"
} elseif ($configureNeeded) {
    $configureScript = Join-Path $scriptDir "Configure-SOFS-Cluster.ps1"
    if (-not (Test-Path $configureScript)) {
        Write-Log "Configure script not found: $configureScript" "FAIL"
        exit 1
    }

    $configureArgs = $commonArgs.Clone()
    $configureArgs['WinRMTransport'] = $WinRMTransport

    $configureExitCode = Invoke-Phase -PhaseName "configure" -ScriptPath $configureScript -Arguments $configureArgs
    if ($configureExitCode -ne 0) {
        Write-Log "Deployment pipeline stopped — Phase 2 failed." "FAIL"
        $state.overall_status = "in_progress"
        Save-DeploymentState $state
        exit 1
    }
}

# --- SUMMARY ---
$overallSw.Stop()
$totalElapsed = $overallSw.Elapsed.ToString("hh\:mm\:ss")

$state.overall_status = "completed"
$state.updated_at     = (Get-Date).ToString("o")
Save-DeploymentState $state

Write-Log "" "INFO"
Write-Log "========================================" "HEADER"
Write-Log "DEPLOYMENT COMPLETE" "PASS"
Write-Log "========================================" "HEADER"
Write-Log "  Total Time:    $totalElapsed"
Write-Log "  Phase 1:       $($state.phases.deploy.status)"
Write-Log "  Phase 2:       $($state.phases.configure.status)"
Write-Log "  State File:    $stateFile"
Write-Log "  Log File:      $logFile"

foreach ($phase in @("deploy", "configure")) {
    $p = $state.phases.$phase
    if ($p.log_file -and (Test-Path $p.log_file)) {
        Write-Log "  ${phase} log:   $($p.log_file)"
    }
}
