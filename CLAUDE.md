# azurelocal-sofs-fslogix — Claude Code Context

## What this repo is

This repo contains the IaC templates, configuration, and deployment scripts for provisioning Scale-Out File Server (SOFS) on Azure Local as a high-availability FSLogix profile storage backend for Azure Virtual Desktop. It covers ARM templates, Bicep modules, Ansible playbooks, and PowerShell deployment scripts. It is not an application repo — it contains no runtime code, only infrastructure definitions and deployment automation.

---

## ADO project details

- **ADO org:** https://dev.azure.com/hybridcloudsolutions
- **ADO project:** Azure Local
- **Area path:** Platform Engineering\Onboarding
- **Work item format:** `AB#<id>` in commit messages and PR descriptions

---

## Standards

This repo follows all HCS platform standards defined in the Platform Engineering repo:

| Standard | Reference |
|---|---|
| Governance | [docs/standards/governance.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/governance.md) |
| Scripting (PowerShell 7) | [docs/standards/scripting.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/scripting.md) |
| Automation | [docs/standards/automation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/automation.md) |
| Variables and naming | [docs/standards/variables.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/variables.md) |
| Documentation | [docs/standards/documentation.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/documentation.md) |
| Claude Code | [docs/standards/claude-code.md](https://dev.azure.com/hybridcloudsolutions/Platform%20Engineering/_git/Platform%20Engineering?path=/docs/standards/claude-code.md) |

Key rules:
- All scripts: PowerShell 7+ only. `#Requires -Version 7.0`, `Set-StrictMode -Version Latest`, ` $ErrorActionPreference = 'Stop'`.
- All docs: Markdown only. No Word documents in any repo.
- Commit format: `type(scope): short description` — types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`
- No secrets, tokens, or credentials committed to any file.

---

## Key facts

| Fact | Value |
|---|---|
| Primary language | ARM / Bicep / PowerShell 7 |
| GitHub org | AzureLocal |
| Azure login | kris@hybridsolutions.cloud |
| Key Vault | kv-hcs-vault-01 |

### Environment variables expected

| Variable | Source | Purpose |
|---|---|---|
| `GITHUB_TOKEN` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | GitHub CLI and git operations |
| `AZURE_DEVOPS_EXT_PAT` | kv-hcs-vault-01 via Load-HCSEnvironment.ps1 | ADO CLI (`az boards`, `az devops`) |
Load before starting a session:
```powershell
. D:\git\platform\scripts\Load-HCSEnvironment.ps1
```

### Build and test commands

```
mkdocs build
mkdocs serve  # http://127.0.0.1:8000
```

---

## Repo structure

```
azurelocal-sofs-fslogix/
├── .claude/
    └── settings.json
├── .github/
    ├── workflows/
    └── CODEOWNERS
├── config/
    ├── variables/
    └── README.md
├── docs/
    ├── architecture/
    ├── assets/
    ├── configuration/
    ├── deployment/
    └── operations/
├── examples/
    ├── configs/
    ├── pipelines/
    ├── secrets/
    └── README.md
├── logs/
    └── .gitkeep
├── repo-management/
    ├── scripts/
    ├── automation.md
    ├── canonical-variable-migration.md
    ├── README.md
    └── setup.md
├── scripts/
    ├── configure-arc-extensions.sh
    ├── deploy-prerequisites.sh
    └── README.md
├── src/
    ├── ansible/
    ├── arm/
    ├── bicep/
    ├── powershell/
    └── terraform/
├── styles/
    └── Microsoft/
├── tests/
    ├── terraform/
    ├── README.md
    ├── Test-SOFSDeployment.ps1
    ├── Test-SOFSDeployment.Tests.ps1
    └── Test-ToolSmokeTests.ps1
├── .azurelocal-platform.yml
├── .gitignore
├── .release-please-manifest.json
├── .vale.ini
├── avd-fslogix-entra-kerberos-resolution.md
├── azurelocal-sofs-fslogix.code-workspace
├── CHANGELOG.md
└── ...
```

---

## Claude Code actions

**Run autonomously:**
- Read, search, and grep any file in this repo
- Write and edit files in this repo
- `git add`, `git commit`, `git push`
- `gh issue`, `gh pr`, `gh run` CLI commands
- `mkdocs build` and `mkdocs serve`
- `pip install` for MkDocs plugins

**Always confirm before:**
- Creating or deleting Azure resources
- Any `az` CLI write operation that modifies Azure state
- Running destructive operations
- Making API calls to external services


---

## Subagents available in this repo

- `azurelocal-sofs-fslogix-engineer` (model: sonnet) — IaC engineer for SOFS/FSLogix deployment: ARM templates, Bicep modules, Ansible playbooks, PowerShell deployment scripts.

User-level agents (every repo): `triage-lookup`, `markdown-prose-editor`, `azurelocal-domain-expert`, `mkdocs-material-doctor`, `turner-module-scaffold-engineer`, `mms-2026-demo-presenter`.

Platform repo agents (when working in `D:\git\platform`): `orchestration-pm`, `security-waf-caf`, `terraform-validator`, `bicep-validator`, `arm-validator`, `ansible-linter`, `powershell-linter`, `reviewer`, `security-reviewer`, `documenter`, `coder`, `planner`, `operator`, `investigator`, `test-writer`, `router`.

---

## Owner

**Kristopher Turner**
kris@hybridsolutions.cloud
Senior Product Technology Architect, TierPoint | Microsoft MVP (Azure) | MCT
Owner, Hybrid Cloud Solutions LLC — hybridsolutions.cloud
Country Cloud Boy — thisismydemo.cloud

---

## HCS Orchestration Profile

**Validation profile:** iac-arm — see `D:\git\platform\profiles\iac-arm.yaml`

This repo is a **pilot** for the `iac-arm` type in the HCS multi-agent orchestration system.
Run `/dispatch iac-arm` (or `/dispatch` for all pilots) to validate this repo.

**Repo-specific notes for validators:**
Entry point: `src/arm/azuredeploy.json`. Parameters file: `src/arm/azuredeploy.parameters.example.json`. ARM-TTK must pass. No `az deployment` commands in this repo — templates only.
