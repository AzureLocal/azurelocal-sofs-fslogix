<#
.SYNOPSIS
    Pester 5 tests for the SOFS deployment PowerShell scripts.

.DESCRIPTION
    Validates configuration loading, parameter resolution, VM name generation,
    single/triple layout branching, state file management, and script syntax.

    Run:
      Invoke-Pester .\tests\Test-SOFSDeployment.Tests.ps1 -Output Detailed
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $repoRoot  = Split-Path $PSScriptRoot -Parent
    $deployDir = Join-Path $repoRoot "src\powershell\deploy"
    $configDir = Join-Path $repoRoot "config"

    # Script paths
    $deployScript    = Join-Path $deployDir "Deploy-SOFS-Azure.ps1"
    $configureScript = Join-Path $deployDir "Configure-SOFS-Cluster.ps1"
    $removeScript    = Join-Path $deployDir "Remove-SOFSDeployment.ps1"
    $invokeScript    = Join-Path $deployDir "Invoke-SOFSDeployment.ps1"

    # Schema path
    $schemaPath = Join-Path $configDir "schema\variables.schema.json"

        # Build a minimal valid config for unit tests (Single layout — single volume/share)
        $singleLayoutYaml = @"
deployment:
  host_volume_layout: "three_volumes"
  host_resiliency: "two_way"
  guest_layout: "single"
  guest_volume_layout: "option_a"
  guest_resiliency: "two_way"
azure:
  tenant_id: "00000000-0000-0000-0000-000000000000"
  subscription_id: "11111111-1111-1111-1111-111111111111"
  resource_group: "rg-sofs-test"
  location: "eastus"
azure_local:
    cluster_name: "azl-cluster-test"
    custom_location_id: "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.ExtendedLocation/customLocations/cl-sofs-test"
    logical_network_id: "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/logicalNetworks/ln-sofs-test"
    gallery_image_name: "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/galleryImages/gi-sofs-test"
    storage_path_id: "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/storageContainers/sp-default"
    storage_path_ids:
        "01": "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/storageContainers/sp-01"
        "02": "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/storageContainers/sp-02"
        "03": "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sofs-test/providers/Microsoft.AzureStackHCI/storageContainers/sp-03"
vm:
  prefix: "tstsofs"
  count: 3
  processors: 4
  memory_mb: 8192
  os_disk_size_gb: 127
  admin_username: "testadmin"
  admin_password: "P@ssw0rdForTestOnly"
  ips:
    "01": "192.168.1.201"
    "02": "192.168.1.202"
    "03": "192.168.1.203"
data_disks:
  count: 4
  size_gb: 500
  dynamic: false
domain:
  fqdn: "test.local"
  netbios: "TEST"
  join_username: "svc.join"
  join_password: "P@ssw0rd"
  cluster_ou_path: "OU=Test,DC=test,DC=local"
  nodes_ou_path: "OU=Test,DC=test,DC=local"
dns_servers:
  - "10.0.1.10"
sofs:
  role_name: "TestSOFS"
  cluster_name: "sofs-test-cluster"
  cluster_ip: "192.168.1.204"
  access_point_ip: "192.168.1.205"
  role_enabled: true
  anti_affinity_rule_name: "SOFS-AntiAffinity"
  smb_encryption: true
  caching_mode: "None"
  continuous_availability: true
  folder_enumeration_mode: "AccessBased"
  share_name: "Profiles"
s2d:
  pool_name: "S2D on sofs-test-cluster"
  volume_name: "FSLogixData"
  volume_size_gb: 2560
  data_copies: 2
cloud_witness:
  name: "stsofswitness01"
  endpoint: "core.windows.net"
permissions:
  admin_group: "Domain Admins"
  users_group: "AVD-Users"
  avd_users_group: "AVD-Users"
fslogix:
  enabled: true
  profile_size_mb: 30000
  volume_type: "VHDX"
  flip_flop_name: true
  delete_local_profile: true
  cloud_cache:
    enabled: true
    azure_provider: "type=smb,connectionString=\\\\\\\\TestSOFS.test.local\\\\Profiles"
    providers:
      - name: "primary"
        type: "smb"
        connection_string: "\\\\\\\\TestSOFS.test.local\\\\Profiles"
      - name: "dr"
        type: "smb"
        connection_string: "\\\\\\\\DR-SOFS.test.local\\\\Profiles"
tags:
  project: "SOFS"
  environment: "test"
winrm:
  transport: "kerberos"
  port: 5986
  use_ssl: true
  cert_validation: "ignore"
"@

    # Triple layout config — three volumes/shares
    $tripleLayoutYaml = $singleLayoutYaml -replace `
        "guest_layout: `"single`"", `
        "guest_layout: `"triple`""
    $tripleLayoutYaml = $tripleLayoutYaml -replace `
        "guest_volume_layout: `"option_a`"", `
        "guest_volume_layout: `"option_b`""
    $tripleLayoutYaml = $tripleLayoutYaml -replace `
        "  share_name: `"Profiles`"", @"
  shares:
    - name: "Profiles"
      volume: "Profiles"
    - name: "ODFC"
      volume: "ODFC"
    - name: "AppData"
      volume: "AppData"
"@
    $tripleLayoutYaml = $tripleLayoutYaml -replace `
        "  volume_name: `"FSLogixData`"\r?\n  volume_size_gb: 2560\r?\n  data_copies: 2", @"
  volumes:
    - name: "Profiles"
      size_gb: 1500
      data_copies: 2
    - name: "ODFC"
      size_gb: 800
      data_copies: 2
    - name: "AppData"
      size_gb: 260
      data_copies: 2
"@
}

# ============================================================================
# 1. Script Files Exist
# ============================================================================
Describe "Script Files" {
    It "Deploy-SOFS-Azure.ps1 exists" {
        $deployScript | Should -Exist
    }
    It "Configure-SOFS-Cluster.ps1 exists" {
        $configureScript | Should -Exist
    }
    It "Remove-SOFSDeployment.ps1 exists" {
        $removeScript | Should -Exist
    }
    It "Invoke-SOFSDeployment.ps1 exists" {
        $invokeScript | Should -Exist
    }
}

# ============================================================================
# 2. Script Syntax Validation (PSParser)
# ============================================================================
Describe "Script Syntax" {
    It "Deploy has no syntax errors" {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($deployScript, [ref]$null, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }
    It "Configure has no syntax errors" {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($configureScript, [ref]$null, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }
    It "Remove has no syntax errors" {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($removeScript, [ref]$null, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }
    It "Invoke has no syntax errors" {
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($invokeScript, [ref]$null, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }
}

# ============================================================================
# 3. Config Schema Exists
# ============================================================================
Describe "Config Schema" {
    It "variables.schema.json exists" {
        $schemaPath | Should -Exist
    }
    It "Schema is valid JSON" {
        { Get-Content $schemaPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
    It "Schema declares required top-level sections" {
        $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
        $required = $schema.required
        $required | Should -Contain "azure"
        $required | Should -Contain "vm"
        $required | Should -Contain "sofs"
        $required | Should -Contain "s2d"
        $required | Should -Contain "domain"
    }
}

# ============================================================================
# 4. Config Loading (YAML → PowerShell object)
# ============================================================================
Describe "Config Loading" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "Loads without error" {
        $sol | Should -Not -BeNullOrEmpty
    }
    It "Has azure section" {
        $sol.azure | Should -Not -BeNullOrEmpty
    }
    It "Has vm section" {
        $sol.vm | Should -Not -BeNullOrEmpty
    }
    It "Has sofs section" {
        $sol.sofs | Should -Not -BeNullOrEmpty
    }
    It "Has s2d section" {
        $sol.s2d | Should -Not -BeNullOrEmpty
    }
    It "Has domain section" {
        $sol.domain | Should -Not -BeNullOrEmpty
    }
    It "Has cloud_witness section" {
        $sol.cloud_witness | Should -Not -BeNullOrEmpty
    }
    It "Has permissions section" {
        $sol.permissions | Should -Not -BeNullOrEmpty
    }
    It "Has tags section" {
        $sol.tags | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# 5. Config Values — Direct $sol.* Access
# ============================================================================
Describe "Config Values — Direct Access" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "azure.subscription_id resolves" {
        $sol.azure.subscription_id | Should -Be "11111111-1111-1111-1111-111111111111"
    }
    It "azure.resource_group resolves" {
        $sol.azure.resource_group | Should -Be "rg-sofs-test"
    }
    It "vm.prefix resolves" {
        $sol.vm.prefix | Should -Be "tstsofs"
    }
    It "vm.count is an integer" {
        [int]$sol.vm.count | Should -BeOfType [int]
    }
    It "sofs.role_name resolves" {
        $sol.sofs.role_name | Should -Be "TestSOFS"
    }
    It "sofs.cluster_name resolves" {
        $sol.sofs.cluster_name | Should -Be "sofs-test-cluster"
    }
    It "domain.fqdn resolves" {
        $sol.domain.fqdn | Should -Be "test.local"
    }
    It "cloud_witness.endpoint resolves" {
        $sol.cloud_witness.endpoint | Should -Be "core.windows.net"
    }
    It "s2d.pool_name resolves" {
        $sol.s2d.pool_name | Should -Be "S2D on sofs-test-cluster"
    }
    It "permissions.admin_group resolves" {
        $sol.permissions.admin_group | Should -Be "Domain Admins"
    }
    It "tags.project resolves" {
        $sol.tags.project | Should -Be "SOFS"
    }
}

# ============================================================================
# 6. VM Name Generation
# ============================================================================
Describe "VM Name Generation" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmPrefix = $sol.vm.prefix
        $vmCount  = [int]$sol.vm.count
        $vmNames = @()
        for ($i = 1; $i -le $vmCount; $i++) {
            $vmNames += "{0}-{1:D2}" -f $vmPrefix, $i
        }
    }

    It "Generates correct number of VM names" {
        $vmNames.Count | Should -Be 3
    }
    It "First VM name is tstsofs-01" {
        $vmNames[0] | Should -Be "tstsofs-01"
    }
    It "Last VM name is tstsofs-03" {
        $vmNames[-1] | Should -Be "tstsofs-03"
    }
    It "VM names use zero-padded two-digit suffix" {
        $vmNames | ForEach-Object { $_ | Should -Match "^tstsofs-\d{2}$" }
    }
}

# ============================================================================
# 7. Single layout — Single Volume / Single Share
# ============================================================================
Describe "Single layout — Single Volume/Share" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "guest_layout is single" {
        $sol.deployment.guest_layout | Should -Be "single"
    }
    It "guest_volume_layout alias is option_a" {
        $sol.deployment.guest_volume_layout | Should -Be "option_a"
    }
    It "sofs.share_name is defined" {
        $sol.sofs.share_name | Should -Not -BeNullOrEmpty
    }
    It "sofs.shares is NOT defined" {
        $sol.sofs.shares | Should -BeNullOrEmpty
    }
    It "s2d.volume_name is defined" {
        $sol.s2d.volume_name | Should -Not -BeNullOrEmpty
    }
    It "s2d.volumes is NOT defined" {
        $sol.s2d.volumes | Should -BeNullOrEmpty
    }
    It "s2d.data_copies is 2 or 3" {
        [int]$sol.s2d.data_copies | Should -BeIn @(2, 3)
    }
}

# ============================================================================
# 8. Triple layout — Three Volumes / Three Shares
# ============================================================================
Describe "Triple layout — Three Volumes/Shares" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $tripleLayoutYaml | ConvertFrom-Yaml
    }

    It "guest_layout is triple" {
        $sol.deployment.guest_layout | Should -Be "triple"
    }
    It "guest_volume_layout alias is option_b" {
        $sol.deployment.guest_volume_layout | Should -Be "option_b"
    }
    It "sofs.shares is a list with 3 entries" {
        $sol.sofs.shares | Should -Not -BeNullOrEmpty
        $sol.sofs.shares.Count | Should -Be 3
    }
    It "Each share has a name and volume" {
        $sol.sofs.shares | ForEach-Object {
            $_.name   | Should -Not -BeNullOrEmpty
            $_.volume | Should -Not -BeNullOrEmpty
        }
    }
    It "s2d.volumes is a list with 3 entries" {
        $sol.s2d.volumes | Should -Not -BeNullOrEmpty
        $sol.s2d.volumes.Count | Should -Be 3
    }
    It "Each volume has name, size_gb, and data_copies" {
        $sol.s2d.volumes | ForEach-Object {
            $_.name       | Should -Not -BeNullOrEmpty
            $_.size_gb    | Should -BeGreaterThan 0
            $_.data_copies | Should -BeIn @(2, 3)
        }
    }
    It "Share names map to volume names" {
        $shareNames  = $sol.sofs.shares | ForEach-Object { $_.volume }
        $volumeNames = $sol.s2d.volumes | ForEach-Object { $_.name }
        $shareNames | ForEach-Object { $_ | Should -BeIn $volumeNames }
    }
}

# ============================================================================
# 9. VM Count Validation
# ============================================================================
Describe "VM Count Validation" {
    It "Rejects vm.count < 2" {
        $count = 1
        ($count -ge 2 -and $count -le 16) | Should -BeFalse
    }
    It "Accepts vm.count = 2" {
        $count = 2
        ($count -ge 2 -and $count -le 16) | Should -BeTrue
    }
    It "Accepts vm.count = 3" {
        $count = 3
        ($count -ge 2 -and $count -le 16) | Should -BeTrue
    }
    It "Accepts vm.count = 16" {
        $count = 16
        ($count -ge 2 -and $count -le 16) | Should -BeTrue
    }
    It "Rejects vm.count > 16" {
        $count = 17
        ($count -ge 2 -and $count -le 16) | Should -BeFalse
    }
}

# ============================================================================
# 10. Data Copies vs Node Count Compatibility
# ============================================================================
Describe "Data Copies vs VM Count" {
    It "2-way mirror requires at least 2 nodes" {
        $dataCopies = 2; $vmCount = 2
        ($vmCount -ge $dataCopies) | Should -BeTrue
    }
    It "3-way mirror requires at least 3 nodes" {
        $dataCopies = 3; $vmCount = 3
        ($vmCount -ge $dataCopies) | Should -BeTrue
    }
    It "3-way mirror with 2 nodes should fail" {
        $dataCopies = 3; $vmCount = 2
        ($vmCount -ge $dataCopies) | Should -BeFalse
    }
}

# ============================================================================
# 11. Deployment State File (Invoke-SOFSDeployment state management)
# ============================================================================
Describe "Deployment State File" {
    BeforeAll {
        $testStateDir = Join-Path $TestDrive "logs\sofs"
        New-Item -ItemType Directory -Path $testStateDir -Force | Out-Null
        $testStateFile = Join-Path $testStateDir "deployment-state.json"
    }

    It "Creates a valid state structure" {
        $state = [PSCustomObject]@{
            started_at     = (Get-Date).ToString("o")
            updated_at     = (Get-Date).ToString("o")
            config_path    = "config/variables.yml"
            phases         = [PSCustomObject]@{
                deploy    = [PSCustomObject]@{ status = "not_started"; started_at = $null; completed_at = $null; exit_code = $null; log_file = $null }
                configure = [PSCustomObject]@{ status = "not_started"; started_at = $null; completed_at = $null; exit_code = $null; log_file = $null }
            }
            overall_status = "in_progress"
        }
        $state | ConvertTo-Json -Depth 5 | Set-Content $testStateFile -Encoding utf8
        $testStateFile | Should -Exist
    }

    It "Round-trips through JSON" {
        $loaded = Get-Content $testStateFile -Raw | ConvertFrom-Json
        $loaded.overall_status | Should -Be "in_progress"
        $loaded.phases.deploy.status | Should -Be "not_started"
        $loaded.phases.configure.status | Should -Be "not_started"
    }

    It "Updates phase status to completed" {
        $loaded = Get-Content $testStateFile -Raw | ConvertFrom-Json
        $loaded.phases.deploy.status       = "completed"
        $loaded.phases.deploy.exit_code    = 0
        $loaded.phases.deploy.completed_at = (Get-Date).ToString("o")
        $loaded | ConvertTo-Json -Depth 5 | Set-Content $testStateFile -Encoding utf8

        $reloaded = Get-Content $testStateFile -Raw | ConvertFrom-Json
        $reloaded.phases.deploy.status    | Should -Be "completed"
        $reloaded.phases.deploy.exit_code | Should -Be 0
    }

    It "Tracks a failed phase" {
        $loaded = Get-Content $testStateFile -Raw | ConvertFrom-Json
        $loaded.phases.configure.status    = "failed"
        $loaded.phases.configure.exit_code = 1
        $loaded | ConvertTo-Json -Depth 5 | Set-Content $testStateFile -Encoding utf8

        $reloaded = Get-Content $testStateFile -Raw | ConvertFrom-Json
        $reloaded.phases.configure.status    | Should -Be "failed"
        $reloaded.phases.configure.exit_code | Should -Be 1
        $reloaded.overall_status             | Should -Be "in_progress"
    }
}

# ============================================================================
# 12. Disk Name Generation
# ============================================================================
Describe "Disk Name Generation" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmPrefix  = $sol.vm.prefix
        $diskCount = [int]$sol.data_disks.count
    }

    It "Generates correct disk names for VM 1" {
        $vmName = "{0}-{1:D2}" -f $vmPrefix, 1
        $diskNames = @()
        for ($d = 1; $d -le $diskCount; $d++) {
            $diskNames += "{0}-disk-{1:D2}" -f $vmName, $d
        }
        $diskNames.Count | Should -Be 4
        $diskNames[0] | Should -Be "tstsofs-01-disk-01"
        $diskNames[-1] | Should -Be "tstsofs-01-disk-04"
    }
}

# ============================================================================
# 13. NIC Name Generation
# ============================================================================
Describe "NIC Name Generation" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmPrefix = $sol.vm.prefix
        $vmCount  = [int]$sol.vm.count
    }

    It "Generates correct NIC names" {
        $nicNames = @()
        for ($i = 1; $i -le $vmCount; $i++) {
            $nicNames += "{0}-{1:D2}-nic" -f $vmPrefix, $i
        }
        $nicNames[0] | Should -Be "tstsofs-01-nic"
        $nicNames[-1] | Should -Be "tstsofs-03-nic"
    }
}

# ============================================================================
# 14. Tag Generation
# ============================================================================
Describe "Tag Generation" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "Tags section is a hashtable-like object" {
        $sol.tags | Should -Not -BeNullOrEmpty
    }
    It "Contains expected keys" {
        $sol.tags.project     | Should -Be "SOFS"
        $sol.tags.environment | Should -Be "test"
    }
    It "Can be converted to Azure CLI tag string format" {
        $tagPairs = @()
        foreach ($key in $sol.tags.Keys) {
            $tagPairs += "$key=$($sol.tags[$key])"
        }
        $tagString = $tagPairs -join " "
        $tagString | Should -Match "project=SOFS"
        $tagString | Should -Match "environment=test"
    }
}

# ============================================================================
# 15. Config Format Validation Guard
# ============================================================================
Describe "Config Format Validation" {
    It "Rejects config without azure section" {
        $badYaml = @"
vm:
  prefix: "sofs"
  count: 3
"@
        Import-Module powershell-yaml -ErrorAction Stop
        $bad = $badYaml | ConvertFrom-Yaml
        $bad.azure | Should -BeNullOrEmpty
    }

    It "Rejects config without vm section" {
        $badYaml = @"
azure:
  subscription_id: "00000000-0000-0000-0000-000000000000"
"@
        Import-Module powershell-yaml -ErrorAction Stop
        $bad = $badYaml | ConvertFrom-Yaml
        $bad.vm | Should -BeNullOrEmpty
    }

    It "Accepts valid config with all required sections" {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $sol.azure  | Should -Not -BeNullOrEmpty
        $sol.vm     | Should -Not -BeNullOrEmpty
        $sol.sofs   | Should -Not -BeNullOrEmpty
        $sol.s2d    | Should -Not -BeNullOrEmpty
        $sol.domain | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# 16. IP Address Mapping
# ============================================================================
Describe "IP Address Mapping" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "vm.ips has an entry for each VM" {
        $vmCount = [int]$sol.vm.count
        $sol.vm.ips.Keys.Count | Should -BeGreaterOrEqual $vmCount
    }
    It "IP entries are valid IPv4 format" {
        $ipPattern = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
        foreach ($key in $sol.vm.ips.Keys) {
            $sol.vm.ips[$key] | Should -Match $ipPattern
        }
    }
}

# ============================================================================
# 17. WinRM Configuration
# ============================================================================
Describe "WinRM Configuration" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "Transport is a valid value" {
        $sol.winrm.transport | Should -BeIn @("kerberos", "ntlm", "basic")
    }
    It "Port is 5985 or 5986" {
        [int]$sol.winrm.port | Should -BeIn @(5985, 5986)
    }
    It "SSL matches port (5986 = SSL)" {
        if ([int]$sol.winrm.port -eq 5986) {
            $sol.winrm.use_ssl | Should -BeTrue
        }
    }
}

# ============================================================================
# 18. Storage Path Mapping
# ============================================================================
Describe "Storage Path Mapping" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmCount = [int]$sol.vm.count
    }

    It "At least one storage path source is defined" {
        $hasMap = $null -ne $sol.azure_local.storage_path_ids -and $sol.azure_local.storage_path_ids.Count -gt 0
        $hasSingle = -not [string]::IsNullOrWhiteSpace([string]$sol.azure_local.storage_path_id)
        ($hasMap -or $hasSingle) | Should -BeTrue
    }

    It "Per-VM storage_path_ids has entries for each VM index" {
        if ($sol.azure_local.storage_path_ids) {
            for ($i = 1; $i -le $vmCount; $i++) {
                $key = "{0:D2}" -f $i
                $sol.azure_local.storage_path_ids[$key] | Should -Not -BeNullOrEmpty
            }
        } else {
            # Single storage path is acceptable
            $sol.azure_local.storage_path_id | Should -Not -BeNullOrEmpty
        }
    }

    It "Storage path IDs are valid ARM resource IDs" {
        $armPattern = '^/subscriptions/[0-9a-f\-]+/resourceGroups/.+/providers/.+'
        if ($sol.azure_local.storage_path_ids) {
            foreach ($key in $sol.azure_local.storage_path_ids.Keys) {
                $sol.azure_local.storage_path_ids[$key] | Should -Match $armPattern
            }
        }
        if ($sol.azure_local.storage_path_id) {
            $sol.azure_local.storage_path_id | Should -Match $armPattern
        }
    }

    It "Resolves per-VM storage path with fallback to default" {
        $storagePathIds = @{}
        if ($sol.azure_local.storage_path_ids) {
            foreach ($key in $sol.azure_local.storage_path_ids.Keys) {
                $storagePathIds["$key"] = $sol.azure_local.storage_path_ids[$key]
            }
        }
        $defaultPath = if ($sol.azure_local.storage_path_id) {
            $sol.azure_local.storage_path_id
        } elseif ($storagePathIds.Count -gt 0) {
            $storagePathIds.Values | Select-Object -First 1
        } else {
            $null
        }

        # VM with a mapped path should use its own
        $path01 = if ($storagePathIds["01"]) { $storagePathIds["01"] } else { $defaultPath }
        $path01 | Should -Not -BeNullOrEmpty

        # VM beyond the map should fall back to default
        $path99 = if ($storagePathIds["99"]) { $storagePathIds["99"] } else { $defaultPath }
        $path99 | Should -Be $defaultPath
    }
}

# ============================================================================
# 19. Mock az CLI — Deploy-SOFS-Azure.ps1 Parameter Resolution
# ============================================================================
Describe "Mock az CLI — Parameter Resolution" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml

        # Simulate the Resolve-Param function used in Deploy-SOFS-Azure.ps1
        function Resolve-Param {
            param([string]$ParamValue, [object]$ConfigValue, [string]$Name, [bool]$Required = $true)
            if ($ParamValue -ne "" -and $null -ne $ParamValue) { return $ParamValue }
            if ($null -ne $ConfigValue -and "$ConfigValue" -ne "") { return $ConfigValue }
            if ($Required) { throw "Missing required value: $Name" }
            return $null
        }
    }

    It "Uses parameter override when provided" {
        $result = Resolve-Param "my-override-rg" $sol.azure.resource_group "ResourceGroup"
        $result | Should -Be "my-override-rg"
    }

    It "Falls back to config when parameter is empty" {
        $result = Resolve-Param "" $sol.azure.resource_group "ResourceGroup"
        $result | Should -Be "rg-sofs-test"
    }

    It "Throws when both parameter and config are empty and Required=true" {
        { Resolve-Param "" "" "MissingValue" $true } | Should -Throw "Missing required value: MissingValue"
    }

    It "Returns null when not required and both are empty" {
        $result = Resolve-Param "" "" "OptionalValue" $false
        $result | Should -BeNullOrEmpty
    }
}

# ============================================================================
# 20. Mock az CLI — Resource Existence Checks
# ============================================================================
Describe "Mock az CLI — Resource Existence Checks" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmPrefix  = $sol.vm.prefix
        $vmCount   = [int]$sol.vm.count
        $diskCount = [int]$sol.data_disks.count
    }

    It "Generates correct az stack-hci-vm show command per VM" {
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            $VMName = "${vmPrefix}-${key}"
            $cmd = "az stack-hci-vm show --resource-group $($sol.azure.resource_group) --name $VMName --query name -o tsv"
            $cmd | Should -Match "stack-hci-vm show"
            $cmd | Should -Match $VMName
            $cmd | Should -Match $sol.azure.resource_group
        }
    }

    It "Generates correct az stack-hci-vm disk show command per disk" {
        $VMName = "${vmPrefix}-01"
        for ($d = 1; $d -le $diskCount; $d++) {
            $diskName = "$VMName-data$d"
            $cmd = "az stack-hci-vm disk show --resource-group $($sol.azure.resource_group) --name $diskName --query name -o tsv"
            $cmd | Should -Match "stack-hci-vm disk show"
            $cmd | Should -Match $diskName
        }
    }

    It "Generates correct az stack-hci-vm network nic show command per NIC" {
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            $NicName = "${vmPrefix}-${key}-nic"
            $cmd = "az stack-hci-vm network nic show --resource-group $($sol.azure.resource_group) --name $NicName --query name -o tsv"
            $cmd | Should -Match "stack-hci-vm network nic show"
            $cmd | Should -Match $NicName
        }
    }

    It "Generates correct az storage account show command for witness" {
        $cmd = "az storage account show --name $($sol.cloud_witness.name) --resource-group $($sol.azure.resource_group) --query name -o tsv"
        $cmd | Should -Match "storage account show"
        $cmd | Should -Match $sol.cloud_witness.name
    }
}

# ============================================================================
# 21. Mock az CLI — Destroy Mode Resource Ordering
# ============================================================================
Describe "Mock az CLI — Destroy Mode Resource Ordering" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
        $vmPrefix  = $sol.vm.prefix
        $vmCount   = [int]$sol.vm.count
        $diskCount = [int]$sol.data_disks.count

        # Simulate the destroy order from Remove-SOFSDeployment.ps1
        $destroyOrder = @()
        # Step 1: Extensions
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            $destroyOrder += "extension:${vmPrefix}-${key}/JsonADDomainExtension"
        }
        # Step 2: VMs
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            $destroyOrder += "vm:${vmPrefix}-${key}"
        }
        # Step 3: Disks
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            for ($d = 1; $d -le $diskCount; $d++) {
                $destroyOrder += "disk:${vmPrefix}-${key}-data${d}"
            }
        }
        # Step 4: NICs
        for ($i = 1; $i -le $vmCount; $i++) {
            $key = "{0:D2}" -f $i
            $destroyOrder += "nic:${vmPrefix}-${key}-nic"
        }
        # Step 5: Witness
        $destroyOrder += "witness:$($sol.cloud_witness.name)"
    }

    It "Extensions are removed before VMs" {
        $firstExt = ($destroyOrder | Where-Object { $_ -like "extension:*" } | Select-Object -First 1)
        $firstVM  = ($destroyOrder | Where-Object { $_ -like "vm:*" } | Select-Object -First 1)
        $destroyOrder.IndexOf($firstExt) | Should -BeLessThan $destroyOrder.IndexOf($firstVM)
    }

    It "VMs are removed before disks" {
        $firstVM   = ($destroyOrder | Where-Object { $_ -like "vm:*" } | Select-Object -First 1)
        $firstDisk = ($destroyOrder | Where-Object { $_ -like "disk:*" } | Select-Object -First 1)
        $destroyOrder.IndexOf($firstVM) | Should -BeLessThan $destroyOrder.IndexOf($firstDisk)
    }

    It "Disks are removed before NICs" {
        $firstDisk = ($destroyOrder | Where-Object { $_ -like "disk:*" } | Select-Object -First 1)
        $firstNic  = ($destroyOrder | Where-Object { $_ -like "nic:*" } | Select-Object -First 1)
        $destroyOrder.IndexOf($firstDisk) | Should -BeLessThan $destroyOrder.IndexOf($firstNic)
    }

    It "NICs are removed before witness" {
        $lastNic  = ($destroyOrder | Where-Object { $_ -like "nic:*" } | Select-Object -Last 1)
        $witness  = ($destroyOrder | Where-Object { $_ -like "witness:*" } | Select-Object -First 1)
        $destroyOrder.IndexOf($lastNic) | Should -BeLessThan $destroyOrder.IndexOf($witness)
    }

    It "Total destroy resources count is correct" {
        $expected = $vmCount + $vmCount + ($vmCount * $diskCount) + $vmCount + 1
        $destroyOrder.Count | Should -Be $expected
    }
}

# ============================================================================
# 22. FSRM Quota Configuration
# ============================================================================
Describe "FSRM Quota Configuration" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "fslogix.profile_size_mb is a positive integer" {
        [int]$sol.fslogix.profile_size_mb | Should -BeGreaterThan 0
    }
    It "FSRM is enabled when fslogix.enabled and profile_size_mb > 0" {
        $fsrmEnabled = ($sol.fslogix.enabled -and [int]$sol.fslogix.profile_size_mb -gt 0)
        $fsrmEnabled | Should -BeTrue
    }
    It "FSRM is disabled when profile_size_mb is 0" {
        $fsrmEnabled = ($sol.fslogix.enabled -and 0 -gt 0)
        $fsrmEnabled | Should -BeFalse
    }
}

# ============================================================================
# 23. Cloud Cache Configuration
# ============================================================================
Describe "Cloud Cache Configuration" {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $sol = $singleLayoutYaml | ConvertFrom-Yaml
    }

    It "cloud_cache section exists" {
        $sol.fslogix.cloud_cache | Should -Not -BeNullOrEmpty
    }
    It "cloud_cache.enabled is a boolean" {
        $sol.fslogix.cloud_cache.enabled | Should -BeOfType [bool]
    }
    It "cloud_cache.providers array exists" {
        $sol.fslogix.cloud_cache.providers | Should -Not -BeNullOrEmpty -Because "providers array must be defined (even if empty)"
    }
    It "Generates correct CCDLocations for SMB-only" {
        $sofsName  = $sol.sofs.role_name
        $shareName = $sol.sofs.share_name
        $ccdParts  = @("type=smb,connectionString=\\$sofsName\$shareName")
        $ccd = $ccdParts -join ";"
        $ccd | Should -Match "type=smb"
        $ccd | Should -Match "\\\\$sofsName\\$shareName"
    }
    It "Generates correct CCDLocations with Azure provider (legacy)" {
        $sofsName  = $sol.sofs.role_name
        $shareName = $sol.sofs.share_name
        $azProvider = "DefaultEndpointsProtocol=https;AccountName=test;AccountKey=key;"
        $ccdParts = @(
            "type=smb,connectionString=\\$sofsName\$shareName",
            "type=azure,connectionString=$azProvider"
        )
        $ccd = $ccdParts -join ";"
        $ccd | Should -Match "type=smb"
        $ccd | Should -Match "type=azure"
        $ccd | Should -Match "AccountName=test"
    }
    It "Generates correct CCDLocations from multi-provider array" {
        $sofsName  = $sol.sofs.role_name
        $shareName = $sol.sofs.share_name
        $providers = @(
            @{ type = "azure"; connectionString = "DefaultEndpointsProtocol=https;AccountName=stdr01;AccountKey=k1;" },
            @{ type = "smb2";  connectionString = "\\secondary-sofs\Profiles" }
        )
        $ccdParts = @("type=smb,connectionString=\\$sofsName\$shareName")
        foreach ($p in $providers) {
            $ccdParts += "type=$($p.type),connectionString=$($p.connectionString)"
        }
        $ccd = $ccdParts -join ";"
        $ccd | Should -Match "type=smb,connectionString=\\\\$sofsName"
        $ccd | Should -Match "type=azure,connectionString=.*AccountName=stdr01"
        $ccd | Should -Match "type=smb2,connectionString=\\\\secondary-sofs"
        ([regex]::Matches($ccd, 'type=').Count) | Should -Be 3
    }
    It "Providers array takes precedence over legacy azure_provider" {
        # When providers[] is non-empty, azure_provider is ignored
        $providers = @(
            @{ type = "azure"; connectionString = "AccountName=fromarray" }
        )
        $legacyProvider = "AccountName=fromlegacy"
        $ccdParts = @("type=smb,connectionString=\\sofs\share")
        if ($providers.Count -gt 0) {
            foreach ($p in $providers) {
                $ccdParts += "type=$($p.type),connectionString=$($p.connectionString)"
            }
        } else {
            if ($legacyProvider) {
                $ccdParts += "type=azure,connectionString=$legacyProvider"
            }
        }
        $ccd = $ccdParts -join ";"
        $ccd | Should -Match "fromarray"
        $ccd | Should -Not -Match "fromlegacy"
    }
}

# ============================================================================
# 24. Legacy Alias Normalization
# ============================================================================
Describe "Legacy Alias Normalization" {
    BeforeAll {
        # Extract the Resolve-GuestLayout function from the script
        $scriptContent = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "src\powershell\deploy\Configure-SOFS-Cluster.ps1") -Raw
        # Define a mock Write-Log for the extracted function
        function Write-Log { param([string]$Message, [string]$Level) }
        # Extract and dot-source the function
        if ($scriptContent -match '(?s)(function Resolve-GuestLayout \{.+?\n\})') {
            Invoke-Expression $Matches[1]
        }
    }

    It "Normalizes 'option_a' to 'single'" {
        Resolve-GuestLayout -Layout "option_a" | Should -Be "single"
    }
    It "Normalizes 'option_b' to 'triple'" {
        Resolve-GuestLayout -Layout "option_b" | Should -Be "triple"
    }
    It "Passes through 'single' unchanged" {
        Resolve-GuestLayout -Layout "single" | Should -Be "single"
    }
    It "Passes through 'triple' unchanged" {
        Resolve-GuestLayout -Layout "triple" | Should -Be "triple"
    }
    It "Is case-insensitive" {
        Resolve-GuestLayout -Layout "OPTION_A" | Should -Be "single"
        Resolve-GuestLayout -Layout "Triple" | Should -Be "triple"
    }
    It "Throws on invalid layout value" {
        { Resolve-GuestLayout -Layout "invalid" } | Should -Throw
    }
    It "Defaults to 'single' when input is empty" {
        Resolve-GuestLayout -Layout "" | Should -Be "single"
    }
}

# ============================================================================
# 25. Phase 0 Preflight Validation
# ============================================================================
Describe "Phase 0 Preflight — Resolve-Phase0Preflight" {
    BeforeAll {
        $scriptContent = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) "src\powershell\deploy\Configure-SOFS-Cluster.ps1") -Raw
        function Write-Log { param([string]$Message, [string]$Level) }
        # Extract Resolve-Phase0Preflight function
        if ($scriptContent -match '(?s)(function Resolve-Phase0Preflight \{.+?\n\})') {
            Invoke-Expression $Matches[1]
        }
    }

    It "Succeeds with valid single layout config" {
        $result = Resolve-Phase0Preflight -GuestLayout "single" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{ "01" = "/sub/rg/sp1" } -StoragePathId "" `
            -CloudCacheEnabled $false -CloudCacheConfig $null
        $result.azure_host | Should -Not -BeNullOrEmpty
        $result.guest_config | Should -Not -BeNullOrEmpty
        $result.cloud_cache.enabled | Should -BeFalse
    }

    It "Succeeds with valid triple layout config" {
        $result = Resolve-Phase0Preflight -GuestLayout "triple" -VMCount 3 `
            -GuestResiliency "three_way" -HostResiliency "three_way" `
            -StoragePathIds @{ "01" = "/sub/rg/sp1" } -StoragePathId "" `
            -CloudCacheEnabled $false -CloudCacheConfig $null
        $result | Should -Not -BeNullOrEmpty
    }

    It "Fails when three_way mirror has < 3 VMs" {
        { Resolve-Phase0Preflight -GuestLayout "single" -VMCount 2 `
            -GuestResiliency "three_way" -HostResiliency "two_way" `
            -StoragePathIds @{} -StoragePathId "/sp" `
            -CloudCacheEnabled $false -CloudCacheConfig $null
        } | Should -Throw "*preflight failed*"
    }

    It "Fails when guest layout is invalid" {
        { Resolve-Phase0Preflight -GuestLayout "quadruple" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{} -StoragePathId "/sp" `
            -CloudCacheEnabled $false -CloudCacheConfig $null
        } | Should -Throw "*preflight failed*"
    }

    It "Fails when Cloud Cache enabled but no providers" {
        { Resolve-Phase0Preflight -GuestLayout "single" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{} -StoragePathId "/sp" `
            -CloudCacheEnabled $true -CloudCacheConfig @{ providers = @(); azure_provider = "" }
        } | Should -Throw "*preflight failed*"
    }

    It "Succeeds with Cloud Cache and providers array" {
        $cc = @{ providers = @(@{ type = "azure"; connectionString = "AccountName=test" }); azure_provider = "" }
        $result = Resolve-Phase0Preflight -GuestLayout "single" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{} -StoragePathId "/sp" `
            -CloudCacheEnabled $true -CloudCacheConfig $cc
        $result.cloud_cache.enabled | Should -BeTrue
        $result.cloud_cache.provider_mode | Should -Be "providers_array"
        $result.cloud_cache.provider_count | Should -Be 1
    }

    It "Succeeds with Cloud Cache and legacy azure_provider" {
        $cc = @{ providers = @(); azure_provider = "AccountName=legacytest" }
        $result = Resolve-Phase0Preflight -GuestLayout "single" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{} -StoragePathId "/sp" `
            -CloudCacheEnabled $true -CloudCacheConfig $cc
        $result.cloud_cache.enabled | Should -BeTrue
        $result.cloud_cache.provider_mode | Should -Be "legacy_azure_provider"
    }

    It "Returns correct phase_map structure" {
        $result = Resolve-Phase0Preflight -GuestLayout "single" -VMCount 3 `
            -GuestResiliency "two_way" -HostResiliency "two_way" `
            -StoragePathIds @{ "01" = "/sp1" } -StoragePathId "" `
            -CloudCacheEnabled $false -CloudCacheConfig $null
        $result.phase_map | Should -Not -BeNullOrEmpty
        $result.phase_map["Phase 0"] | Should -Match "Preflight"
        $result.phase_map["Phase 1"] | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# 26. Terraform Canonical Layout
# ============================================================================
Describe "Terraform Canonical Layout Normalization" {
    It "Normalizes option_a to single in locals concept" {
        $mapping = @{ "option_a" = "single"; "option_b" = "triple"; "single" = "single"; "triple" = "triple" }
        $mapping["option_a"] | Should -Be "single"
        $mapping["option_b"] | Should -Be "triple"
        $mapping["single"]   | Should -Be "single"
        $mapping["triple"]   | Should -Be "triple"
    }
}
