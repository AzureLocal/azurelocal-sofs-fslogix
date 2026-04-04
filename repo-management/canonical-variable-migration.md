# Canonical Variable Migration Checklist — azurelocal-sofs-fslogix

## Status: Wave 1

## Prerequisites
- [x] CanonicalVariable.psm1 deployed to `src/powershell/common/`
- [ ] Validate `config/variables.example.yml` against canonical schema
- [ ] Confirm CI pipeline passes with no regressions

## Migration Steps

### Step 1: Create Centralized Loader
Currently each script does inline `ConvertFrom-Yaml`. Create a shared loader that wraps `CanonicalVariable.psm1`:
- Move inline loading to a common dot-sourceable script
- Add canonical path resolution

### Step 2: Script-by-Script Migration (6 scripts)

| Script | Complexity | Status |
|--------|-----------|--------|
| src/powershell/deploy/Deploy-SOFS-Azure.ps1 | Medium — inline YAML + dual fallback | [ ] |
| src/powershell/deploy/Remove-SOFSDeployment.ps1 | Low | [ ] |
| src/powershell/deploy/Invoke-SOFSDeployment.ps1 | Low — orchestrator | [ ] |
| src/powershell/deploy/Configure-SOFS-Cluster.ps1 | Medium — inline YAML | [ ] |
| src/bicep/Deploy-SOFS-Azure.ps1 | High — loads solution + infrastructure YAML | [ ] |
| src/powershell/utilities/New-SOFSDeployment.ps1 | Special — dot-sources PS1 params | [ ] |

### Step 3: Variable Path Mapping
Key paths used in SOFS scripts → canonical equivalents:

| Legacy SOFS Path | Canonical Path |
|-----------------|---------------|
| `$sol.compute_wsfc.*` | `compute.wsfc.*` |
| `$sol.azure.*` | `azure_platform.*` |
| `$sol.identity.*` | `identity.*` |
| `$sol.sofs.*` | `storage.sofs.*` |
| `$cfg.identity.*` | `identity.*` |
| `$cfg.networking.*` | `networking.*` |

### Step 4: Legacy Fallback Cleanup
- [ ] Remove `solutions/sofs/solution-sofs.yml` fallback path (consolidate to `config/variables.yml`)
- [ ] Remove inline `ConvertFrom-Yaml` patterns in favor of module

### Step 5: PS1 Utility Scripts
The `utilities/` scripts use dot-sourced `parameters.example.ps1`:
- [ ] Evaluate whether to migrate to YAML-based config or leave as-is
- [ ] If migrating, add `CanonicalVariable.psm1` import to utility scripts

### Step 6: Validation Gate
- [ ] Run canonical schema validator against `config/variables.example.yml`
- [ ] Confirm zero unknown paths
- [ ] Add CI check

## Notes
- Dual config path (`config/variables.yml` + `solutions/sofs/solution-sofs.yml`) should be consolidated
- Infrastructure YAML (`configs/infrastructure-<env>.yml`) loaded by bicep deploy script is separate from canonical variables
