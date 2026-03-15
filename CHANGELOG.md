# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
