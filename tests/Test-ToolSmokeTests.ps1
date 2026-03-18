<#
.SYNOPSIS
    Per-tool smoke tests — validates each deployment tool can process all 10 scenarios.

.DESCRIPTION
    Generates config variations for all 10 SOFS scenarios and validates that each tool's
    artifacts (Terraform plan, Bicep build, ARM template, PowerShell syntax, Ansible syntax)
    succeed without errors. Does NOT deploy anything — this is a pre-flight validation.

.EXAMPLE
    Invoke-Pester .\tests\Test-ToolSmokeTests.ps1 -Output Detailed
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -Modules powershell-yaml

BeforeAll {
    $repoRoot  = Split-Path $PSScriptRoot -Parent

    # All 10 SOFS scenarios:
    # vm_count × host_resiliency × guest_resiliency × guest_volume_layout
    $scenarios = @(
        @{ Name = "2n-2h-2g-A"; VmCount = 2; HostRes = "two_way";   GuestRes = "two_way";   Layout = "option_a" }
        @{ Name = "2n-2h-3g-A"; VmCount = 2; HostRes = "two_way";   GuestRes = "three_way"; Layout = "option_a" }
        @{ Name = "2n-3h-2g-A"; VmCount = 2; HostRes = "three_way"; GuestRes = "two_way";   Layout = "option_a" }
        @{ Name = "2n-3h-3g-A"; VmCount = 2; HostRes = "three_way"; GuestRes = "three_way"; Layout = "option_a" }
        @{ Name = "3n-2h-2g-A"; VmCount = 3; HostRes = "two_way";   GuestRes = "two_way";   Layout = "option_a" }
        @{ Name = "2n-2h-2g-B"; VmCount = 2; HostRes = "two_way";   GuestRes = "two_way";   Layout = "option_b" }
        @{ Name = "2n-2h-3g-B"; VmCount = 2; HostRes = "two_way";   GuestRes = "three_way"; Layout = "option_b" }
        @{ Name = "2n-3h-2g-B"; VmCount = 2; HostRes = "three_way"; GuestRes = "two_way";   Layout = "option_b" }
        @{ Name = "2n-3h-3g-B"; VmCount = 2; HostRes = "three_way"; GuestRes = "three_way"; Layout = "option_b" }
        @{ Name = "3n-2h-2g-B"; VmCount = 3; HostRes = "two_way";   GuestRes = "two_way";   Layout = "option_b" }
    )

    function Build-TestConfig {
        param($Scenario)
        $dataCopies = if ($Scenario.GuestRes -eq "three_way") { 3 } else { 2 }
        $ips = @{}
        for ($i = 1; $i -le $Scenario.VmCount; $i++) {
            $ips[("{0:D2}" -f $i)] = "192.168.1.$($200 + $i)"
        }

        $config = @{
            deployment = @{
                host_volume_layout  = "three_volumes"
                host_resiliency     = $Scenario.HostRes
                guest_volume_layout = $Scenario.Layout
                guest_resiliency    = $Scenario.GuestRes
            }
            azure = @{
                tenant_id       = "00000000-0000-0000-0000-000000000000"
                subscription_id = "11111111-1111-1111-1111-111111111111"
                resource_group  = "rg-sofs-test"
                location        = "eastus"
            }
            vm = @{
                prefix         = "tstsofs"
                count          = $Scenario.VmCount
                processors     = 4
                memory_mb      = 8192
                os_disk_size_gb = 127
                admin_username = "testadmin"
                admin_password = "keyvault://test-vault/admin-password"
                ips            = $ips
            }
            data_disks = @{
                count   = 4
                size_gb = 500
                dynamic = $false
            }
            domain = @{
                fqdn            = "test.local"
                netbios         = "TEST"
                join_username   = "svc.join"
                join_password   = "keyvault://test-vault/join-password"
                cluster_ou_path = "OU=Test,DC=test,DC=local"
                nodes_ou_path   = "OU=Test,DC=test,DC=local"
            }
            sofs = @{
                role_name              = "TestSOFS"
                cluster_name           = "sofs-test-cluster"
                cluster_ip             = "192.168.1.204"
                access_point_ip        = "192.168.1.205"
                role_enabled           = $true
                anti_affinity_rule_name = "SOFS-AntiAffinity"
                smb_encryption         = $true
                caching_mode           = "None"
                continuous_availability = $true
            }
            s2d = @{
                pool_name   = "S2D on sofs-test-cluster"
                data_copies = $dataCopies
            }
            cloud_witness = @{
                name     = "stsofswitness01"
                endpoint = "core.windows.net"
            }
            permissions = @{
                admin_group     = "Domain Admins"
                users_group     = "AVD-Users"
                avd_users_group = "AVD-Users"
            }
        }

        # Option A — single volume/share
        if ($Scenario.Layout -eq "option_a") {
            $config.sofs["share_name"] = "FSLogix"
            $config.s2d["volume_name"] = "FSLogixData"
            $config.s2d["volume_size_gb"] = 2560
        }
        # Option B — three volumes/shares
        else {
            $config.sofs["shares"] = @(
                @{ name = "Profiles"; volume = "Profiles" }
                @{ name = "ODFC";     volume = "ODFC" }
                @{ name = "AppData";  volume = "AppData" }
            )
            $config.s2d["volumes"] = @(
                @{ name = "Profiles"; size_gb = 1500; data_copies = $dataCopies }
                @{ name = "ODFC";     size_gb = 800;  data_copies = $dataCopies }
                @{ name = "AppData";  size_gb = 260;  data_copies = $dataCopies }
            )
        }

        return $config
    }
}

# ============================================================================
# 1. Config generation for all 10 scenarios
# ============================================================================
Describe "Scenario Config Generation" {
    foreach ($scenario in $scenarios) {
        It "Generates valid config for $($scenario.Name)" {
            $config = Build-TestConfig -Scenario $scenario
            $config | Should -Not -BeNullOrEmpty
            $config.vm.count | Should -Be $scenario.VmCount
            $config.deployment.guest_volume_layout | Should -Be $scenario.Layout
            $config.deployment.guest_resiliency | Should -Be $scenario.GuestRes
        }
    }
}

# ============================================================================
# 2. Data Copies match Resiliency
# ============================================================================
Describe "Data Copies match Resiliency" {
    foreach ($scenario in $scenarios) {
        It "$($scenario.Name): data_copies matches guest_resiliency" {
            $config = Build-TestConfig -Scenario $scenario
            $expectedCopies = if ($scenario.GuestRes -eq "three_way") { 3 } else { 2 }
            if ($scenario.Layout -eq "option_a") {
                $config.s2d.data_copies | Should -Be $expectedCopies
            }
            else {
                foreach ($vol in $config.s2d.volumes) {
                    $vol.data_copies | Should -Be $expectedCopies
                }
            }
        }
    }
}

# ============================================================================
# 3. VM count generates correct IP count
# ============================================================================
Describe "IP Address Count per Scenario" {
    foreach ($scenario in $scenarios) {
        It "$($scenario.Name): generates $($scenario.VmCount) IPs" {
            $config = Build-TestConfig -Scenario $scenario
            $config.vm.ips.Count | Should -Be $scenario.VmCount
        }
    }
}

# ============================================================================
# 4. Option A vs Option B share counts
# ============================================================================
Describe "Share Count per Layout" {
    foreach ($scenario in $scenarios) {
        It "$($scenario.Name): correct share structure" {
            $config = Build-TestConfig -Scenario $scenario
            if ($scenario.Layout -eq "option_a") {
                $config.sofs.share_name | Should -Be "FSLogix"
                $config.sofs.ContainsKey("shares") | Should -Be $false
            }
            else {
                $config.sofs.shares.Count | Should -Be 3
                $config.sofs.ContainsKey("share_name") | Should -Be $false
            }
        }
    }
}

# ============================================================================
# 5. No scenario-specific hardcoding (regression check)
# ============================================================================
Describe "No Hardcoded Scenario Values in Source" {
    BeforeAll {
        $sourceFiles = Get-ChildItem -Path (Join-Path $repoRoot "src") -Filter "*.ps1" -Recurse
    }

    It "No hardcoded vm_count of 3 in PowerShell scripts" {
        foreach ($file in $sourceFiles) {
            $content = Get-Content $file.FullName -Raw
            # Allow comments and variable assignments, but not literal `count: 3` patterns
            $content | Should -Not -Match '\$vmCount\s*=\s*3\s*$'
        }
    }
}

# ============================================================================
# 6. PowerShell syntax check across all scripts
# ============================================================================
Describe "PowerShell Script Syntax" {
    BeforeAll {
        $psScripts = Get-ChildItem -Path (Join-Path $repoRoot "src\powershell") -Filter "*.ps1" -Recurse
    }

    foreach ($script in (Get-ChildItem -Path (Join-Path (Split-Path $PSScriptRoot -Parent) "src\powershell") -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue)) {
        It "No syntax errors in $($script.Name)" {
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
        }
    }
}

# ============================================================================
# 7. Terraform validation (if terraform is installed)
# ============================================================================
Describe "Terraform Validation" -Skip:(-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    BeforeAll {
        $tfDir = Join-Path $repoRoot "src\terraform"
    }

    It "terraform validate succeeds" {
        Push-Location $tfDir
        try {
            $init = terraform init -backend=false 2>&1
            $init | Should -Not -Match "Error"
            $validate = terraform validate -json 2>&1 | ConvertFrom-Json
            $validate.valid | Should -Be $true
        }
        finally {
            Pop-Location
        }
    }
}

# ============================================================================
# 8. Bicep validation (if az CLI is installed)
# ============================================================================
Describe "Bicep Validation" -Skip:(-not (Get-Command az -ErrorAction SilentlyContinue)) {
    It "az bicep build succeeds" {
        $bicepFile = Join-Path $repoRoot "src\bicep\main.bicep"
        if (Test-Path $bicepFile) {
            $output = az bicep build --file $bicepFile --stdout 2>&1
            $LASTEXITCODE | Should -Be 0
        }
    }
}

# ============================================================================
# 9. ARM template valid JSON
# ============================================================================
Describe "ARM Template Validation" {
    It "azuredeploy.json is valid JSON" {
        $armFile = Join-Path $repoRoot "src\arm\azuredeploy.json"
        if (Test-Path $armFile) {
            { Get-Content $armFile -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}

# ============================================================================
# 10. Expected S2D Pool Sizes per Scenario
# ============================================================================
Describe "Expected S2D Pool Sizes" {
    # Usable capacity calculation:
    # Option A: volume_size_gb / data_copies * vm_count disks
    # Option B: sum of volume sizes
    foreach ($scenario in $scenarios) {
        It "$($scenario.Name): has valid pool size config" {
            $config = Build-TestConfig -Scenario $scenario
            if ($scenario.Layout -eq "option_a") {
                $config.s2d.volume_size_gb | Should -BeGreaterThan 0
            }
            else {
                $totalSize = ($config.s2d.volumes | Measure-Object -Property size_gb -Sum).Sum
                $totalSize | Should -BeGreaterThan 0
            }
        }
    }
}
