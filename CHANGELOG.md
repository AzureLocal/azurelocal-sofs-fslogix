# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.0.0 (2026-06-17)


### Features

* **#60, #61:** Config/schema expansion + PowerShell scripts, tests, cleanup for all 10 SOFS scenarios ([daa4d22](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/daa4d22550e03186591b558b64c7f83c15e86472))
* **#62:** Terraform AVM modules, domain join, variable parity, native tests ([cfa9328](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/cfa93288325fe1b7737fb809cd66c35eebd1b45b))
* **#64:** Bicep AVM modules, domain join, per-VM storage paths, variable parity ([070573a](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/070573a12bc8604c15a4af7510d934e60c422d4a)), closes [#64](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/64)
* **#66:** Cloud Cache DR support — multi-provider CCDLocations across all 5 tools ([#75](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/75)) ([f2a585f](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/f2a585f77d6ca171b08a8abe4fba7013f766a90f)), closes [#66](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/66)
* **#68:** add CI/CD validation workflow and ARM pipeline templates ([#77](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/77)) ([91d366f](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/91d366f548afd80a910bf2c80cc0abd50ff31db5))
* **#69:** E2E validation framework, smoke tests, and validation matrix ([#78](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/78)) ([fdfa0e6](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/fdfa0e633c8e1c8a80ae122641fb5b65437a66c9)), closes [#69](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/69)
* add correctly named icon SVG, banner SVG, and update docs home page ([fbd8029](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/fbd8029564e1b5cd4e9a43e959d21c93654fc4e5)), closes [#86](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/86)
* add Keller SOFS design document with 11 architecture diagrams ([9599d4e](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/9599d4e3ea793d0e70a5e4750adb1ab5bfbd5830))
* add unique project ID field automation (SOFS-N prefix) ([5193703](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/51937037870f4f42912d659cf0d7dafb50e08883))
* **ansible:** end-to-end playbooks with Option A/B, anti-affinity, domain join, molecule ([#63](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/63)) ([#74](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/74)) ([3877a57](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/3877a575810f2dcecdc3fc7b14ded86ed4890bb6))
* **arm:** compile Bicep to ARM JSON, update params & build script ([#65](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/65)) ([#73](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/73)) ([bdb57c0](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/bdb57c07bcf529f8fbc212129c1e00c7ff70f851))
* **claude:** add Claude Code scaffold ([97c8395](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/97c83957fe621bcb7fca0ba6d0fc4349e0f102fb))
* **epic-59:** implement phase-driven compliance across all toolchains ([#60](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/60)-[#69](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/69)) ([#82](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/82)) ([f0df7be](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/f0df7bede9fd596184208a7302748a17dbb7f64f))
* GitHub Project & Repo Standardization (Plan 1) ([7215a34](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/7215a34364b337b8fb62908ddea8b58fa5c5354c))
* restructure repo, add CI/CD examples, fix naming, add changelog ([ec3a8d9](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/ec3a8d9ffde8fbf8d271c7d5434eca0870160867))


### Bug Fixes

* add reopened trigger to add-to-project workflow ([9c8a24e](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/9c8a24e2969de9ace491167dadbe266da27b0698))
* close audit gaps from epic [#59](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/59) review ([#79](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/79)) ([6239e23](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/6239e235786332a482fc6c26335aea020d2864ba))
* correct config validation workflow script indentation ([6332555](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/6332555a9c01aa9f4e1d08c7514eee136865c6aa))
* make set-fields resilient to add-to-project failures ([4643622](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/4643622af30d6745f73ba03c9f4b5e97bc5921ee))
* pin actions/add-to-project to v1.0.2 ([3085123](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/3085123310cb88592eee38025054fb943e99db01))
* remove broken links in getting-started.md for MkDocs strict build ([fa6fd30](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/fa6fd30a2a44414050ae50e68a2dcbaebfb551b5))
* remove broken links in getting-started.md for MkDocs strict build ([#2](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/2)) ([1456216](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/14562167ad346d2c507854f2ff39ebf22647a941))
* remove invalid sitemap plugin, move gtag to preset options ([2ba797e](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/2ba797e0c799b786e490334ebb41139b4a415ef7))
* repair stale config paths in validate-automation workflow and Pester tests ([cb0e0c8](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/cb0e0c8800eb79dec4e946b56ac163f7907a2ac5))
* resolve MkDocs strict build failures and Release Please token ([#43](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/43)) ([54be99f](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/54be99f4bec311357b0151266be04b16b16949a9))
* restore docs standards and repair validation workflows ([d9bccc8](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/d9bccc8661febf7c72635635bed1966831f7a240))
* **standards:** update canonical path to docs/standards/ in platform ([e2aec68](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/e2aec68db7df77168ec6818c289804efe793fc82))
* update schema for new variable sections (deployment, host_volumes, permissions, fslogix) ([9ac1a00](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/9ac1a007f721145c8421135d34f5ecf7db79e7ae))
* update Solution field option IDs after Toolkit option added to Project [#3](https://github.com/AzureLocal/azurelocal-sofs-fslogix/issues/3) ([2078abd](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/2078abdb4c8bea285b34412d2ce3a49b9c72bad1))
* use action output for item ID, fix stale solution field option IDs ([7f2e703](https://github.com/AzureLocal/azurelocal-sofs-fslogix/commit/7f2e7030ce8ce77960bcc873b3607edec0f1dac8))

## [Unreleased]

### Features

- Restructure repo to `src/` layout with flat tool-based subfolders (`src/terraform`, `src/bicep`, `src/arm`, `src/ansible`, `src/powershell`)
- Add CI/CD pipeline examples for GitHub Actions, GitLab CI, and Azure DevOps (12 pipeline files)
- Add secrets management docs for GitHub Secrets, GitLab Variables, Azure DevOps Variable Groups, and Key Vault integration
- Add variables reference with complete secret/variable inventory
- Add environment config examples for production and staging
- Add docs guides: CI/CD Pipelines, Runner & Agent Setup, Secrets Management
- Integrate SOFS solution into phase-oriented repo structure (Terraform, Bicep, PowerShell, Ansible)

### Bug Fixes

- Replace all TierPoint, tplabs, and contoso references with IIC / Hybrid Cloud Solutions LLC
- Remove broken links in `getting-started.md` for MkDocs strict build
- Fix CODEOWNERS: remove Copilot, keep only repo owner

### Documentation

- Standardize fictional identity (IIC) and author attribution (Hybrid Cloud Solutions)
- Add roadmap with linked GitHub issues (6 milestones, 31 issues)
- Add SOFS Deployment Guide under `docs/guides/`
- Update mkdocs.yml nav with CI/CD, Runner Setup, and Secrets Management guides

### Infrastructure

- Add Release Please config for automated changelog and versioning
- Add CODEOWNERS file with owner assignment

## [0.1.0] - 2026-03-14

### Features

- Initial repo structure for SOFS/FSLogix automation tools and documentation
- Terraform, Bicep, ARM, Ansible, and PowerShell automation scaffolding
- MkDocs Material site with standards, reference, and contributing docs
- Central configuration via `config/variables.example.yml` with `keyvault://` URI support
