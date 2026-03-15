# azurelocal-sofs-fslogix

> **⚠️ Under Active Development** — This repository is a work in progress. Scripts, templates, and automation are **not guaranteed to work** at this time. Use at your own risk and expect breaking changes.

Scripts and automation for deploying a **Scale Out File Server (SOFS)** on **Azure Local** to host **FSLogix** profile containers for **Azure Virtual Desktop (AVD)** session hosts running on Azure Local.

---

## Overview

This repository provides infrastructure-as-code and automation samples for standing up a highly available Scale Out File Server on Azure Local. The SOFS acts as the centralized, SMB-based file share used by FSLogix to store and serve user profile containers (VHD/VHDX) for AVD session hosts.

For the AVD session-host side of the deployment, see the sister repository: [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/aurelocal-avd).

---

## Repository Structure

```
azurelocal-sofs-fslogix/
├── config/                    # Central variables — single source of truth
├── docs/                      # Architecture, getting-started, contributing guide
├── infrastructure/            # Phase 1 — Azure resource provisioning (Bicep / ARM / Terraform / CLI)
├── deploy/                    # Phase 2 — SOFS cluster role + SMB share creation
├── configure/                 # Phase 3 — Share permissions & FSLogix settings (PowerShell / Ansible)
├── tests/                     # Phase 4 — Deployment validation
├── scripts/                   # Standalone utilities (Arc extensions, etc.)
├── examples/                  # Scenarios & walkthroughs (future)
└── sofs/                      # Advanced orchestrated solution (future)
```

---

## Deployment Workflow

```
1. config/           →  Set your variables (single source of truth)
2. infrastructure/   →  Deploy Azure resources — pick one IaC tool
3. deploy/           →  Create SOFS cluster role + SMB share
4. configure/        →  Set permissions & FSLogix settings — pick PowerShell or Ansible
5. tests/            →  Validate the deployment
```

---

## Quick Start

### 1. Configure Variables

```bash
cp config/variables.example.yml config/variables.yml
# Edit config/variables.yml with your environment values
```

### 2. Deploy Azure Infrastructure (Phase 1 — choose one)

| Tool | Location | Guide |
|------|----------|-------|
| Bicep _(recommended)_ | [`infrastructure/bicep/`](./infrastructure/bicep/) | [README](./infrastructure/bicep/README.md) |
| ARM | [`infrastructure/arm/`](./infrastructure/arm/) | [README](./infrastructure/arm/README.md) |
| Terraform | [`infrastructure/terraform/`](./infrastructure/terraform/) | [README](./infrastructure/terraform/README.md) |
| Azure CLI | [`infrastructure/azure-cli/`](./infrastructure/azure-cli/) | [README](./infrastructure/azure-cli/README.md) |

### 3. Deploy SOFS (Phase 2)

| Tool | Location | Guide |
|------|----------|-------|
| PowerShell | [`deploy/`](./deploy/) | [README](./deploy/README.md) |

### 4. Configure (Phase 3 — choose one)

| Tool | Location | Guide |
|------|----------|-------|
| PowerShell | [`configure/powershell/`](./configure/powershell/) | [README](./configure/README.md) |
| Ansible | [`configure/ansible/`](./configure/ansible/) | [README](./configure/README.md) |

### 5. Validate (Phase 4)

| Tool | Location | Guide |
|------|----------|-------|
| PowerShell | [`tests/`](./tests/) | [README](./tests/README.md) |

---

## Documentation

- [Architecture Overview](./docs/architecture.md)
- [Getting Started](./docs/getting-started.md)
- [Contributing](./docs/contributing.md)
- [Variable Reference](./config/README.md)

---

## Prerequisites

- An existing **Azure Local** cluster (formerly Azure Stack HCI)
- Azure subscription with appropriate RBAC permissions
- For PowerShell: Az PowerShell module and RSAT-Clustering tools
- For Bicep / ARM: Azure CLI >= 2.50 or Azure PowerShell >= 9.0
- For Terraform: Terraform >= 1.5, AzureRM provider >= 3.75
- For Ansible: Ansible >= 2.14, `azure.azcollection` collection

---

## Contributing

See [CONTRIBUTING.md](./docs/contributing.md) for coding standards, branch strategy, and PR guidelines.

---

## Sister Repositories

| Repository | Description |
|------------|-------------|
| [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/aurelocal-avd) | Azure Virtual Desktop session host deployment on Azure Local |

---

## License

See [LICENSE](./LICENSE) for details.
