# Roadmap

> **Last updated:** 2026-03-14

This document tracks planned work, upcoming features, and improvements for the Azure Local SOFS for FSLogix project. Items are organized by priority and grouped into milestones.

---

## Milestone 1 — Repository Cleanup & Foundation

Finalize the tool-based repo structure under `src/` and remove legacy artifacts.

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#5](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/5) | Remove `sofs/` from git tracking (`git rm -r --cached`) | chore | Done |
| [#6](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/6) | Consolidate all automation code under `src/` organised by tool | chore | Done |
| [#7](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/7) | Consolidate Azure CLI scripts into `scripts/` | chore | Done |
| [#8](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/8) | Consolidate `tests/` — move `Test-SOFSDeployment.ps1` into `tests/` with proper Pester structure | chore | Planned |
| [#9](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/9) | Populate `examples/` with sample config files and usage patterns | docs | Planned |
| — | Adopt Conventional Commits across all contributors | chore | In Progress |

## Milestone 2 — Documentation Overhaul

Replace placeholder content with production-quality documentation using IIC examples throughout.

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#11](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/11) | Rewrite `README.md` with project overview, quickstart, and badges | docs | Planned |
| [#12](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/12) | Flesh out `docs/architecture.md` with SOFS topology diagrams | docs | Planned |
| [#13](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/13) | Create architecture diagrams in `docs/assets/diagrams/` (draw.io) | docs | Planned |
| [#14](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/14) | Update `docs/getting-started.md` with end-to-end walkthrough | docs | Planned |
| [#15](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/15) | Update all docs and scripts to use IIC naming (replace contoso/fabrikam) | docs | Done |
| [#16](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/16) | Add variable reference docs from `config/README.md` into MkDocs site | docs | Planned |
| [#17](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/17) | Add troubleshooting guide under `docs/guides/` | docs | Planned |

## Milestone 3 — Infrastructure as Code

Validate, test, and document the IaC modules for production use.

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#19](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/19) | Validate Bicep templates deploy end-to-end | infra | Planned |
| [#20](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/20) | Validate Terraform modules deploy end-to-end | infra | Planned |
| [#21](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/21) | Add Bicep/Terraform input validation and defaults | infra | Planned |
| [#22](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/22) | Add CI workflow for Bicep lint (`az bicep build`) | ci | Planned |
| [#23](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/23) | Add CI workflow for Terraform validate + fmt check | ci | Planned |
| [#24](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/24) | Parameterize Ansible playbooks to read from `config/variables.yml` | infra | Planned |

## Milestone 4 — Testing & CI/CD

Build out automated testing and continuous integration pipelines.

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#26](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/26) | Create Pester test suite for `Deploy-SOFS-Azure.ps1` | test | Planned |
| [#27](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/27) | Create Pester test suite for `Configure-SOFS-Cluster.ps1` | test | Planned |
| [#28](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/28) | Add CI workflow for PowerShell linting (PSScriptAnalyzer) | ci | Planned |
| [#29](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/29) | Add CI workflow for YAML/Markdown linting | ci | Planned |
| [#30](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/30) | Add CI workflow for MkDocs build validation | ci | Planned |

## Milestone 5 — FSLogix Integration

Extend the repo beyond SOFS to cover FSLogix profile container configuration.

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#32](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/32) | Add FSLogix GPO/registry configuration scripts | feat | Planned |
| [#33](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/33) | Add FSLogix profile container sizing guide | docs | Planned |
| [#34](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/34) | Add FSLogix + SOFS end-to-end deployment playbook | feat | Planned |
| [#35](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/35) | Add Ansible role for FSLogix agent deployment | feat | Planned |

## Milestone 6 — Advanced Features

| Issue | Item | Type | Status |
|-------|------|------|--------|
| [#37](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/37) | Add monitoring/alerting templates (Azure Monitor) | feat | Planned |
| [#38](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/38) | Add disaster recovery / failover documentation | docs | Planned |
| [#39](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/39) | Add multi-site SOFS deployment support | feat | Planned |
| [#40](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/40) | Publish reusable Bicep modules to a module registry | feat | Planned |

---

## How This Connects to the Changelog

Each roadmap item maps to one or more GitHub issues. When work is completed and merged to `main` using [Conventional Commits](https://www.conventionalcommits.org/), Release Please automatically generates changelog entries:

| Commit Prefix | Changelog Section | Example |
|---------------|------------------|---------|
| `feat:` | Features | `feat: add FSLogix GPO configuration script` |
| `fix:` | Bug Fixes | `fix: correct S2D pool naming in cluster config` |
| `docs:` | Documentation | `docs: rewrite architecture page with diagrams` |
| `infra:` | Infrastructure | `infra: add Terraform validation CI workflow` |
| `ci:` | Miscellaneous | `ci: add PSScriptAnalyzer linting workflow` |
| `chore:` | Miscellaneous | `chore: remove legacy sofs/ folder from tracking` |
