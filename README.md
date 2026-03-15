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
├── src/                       # All automation code, organised by tool
│   ├── bicep/                 #   Azure Bicep templates
│   ├── arm/                   #   ARM JSON templates
│   ├── terraform/             #   Terraform configuration
│   ├── ansible/               #   Ansible playbooks & inventory
│   └── powershell/            #   PowerShell deploy & configure scripts
├── config/                    # Central variables — single source of truth
├── docs/                      # Architecture, getting-started, contributing guide
├── tests/                     # Deployment validation
├── scripts/                   # Standalone utilities (Arc extensions, prerequisites)
├── examples/                  # Scenarios & walkthroughs (future)
└── logs/                      # Runtime logs (gitignored)
```

---

## Deployment Workflow

```
1. config/              →  Set your variables (single source of truth)
2. src/<tool>/          →  Deploy Azure resources — pick one IaC tool
3. src/powershell/      →  Create SOFS cluster role + SMB share
4. src/powershell/ or   →  Set permissions & FSLogix settings
   src/ansible/
5. tests/               →  Validate the deployment
```

---

## Quick Start

### 1. Configure Variables

```bash
cp config/variables.example.yml config/variables.yml
# Edit config/variables.yml with your environment values
```

### 2. Deploy Azure Infrastructure (choose one)

| Tool | Location | Guide |
|------|----------|-------|
| Bicep _(recommended)_ | [`src/bicep/`](./src/bicep/) | [README](./src/bicep/README.md) |
| ARM | [`src/arm/`](./src/arm/) | [README](./src/arm/README.md) |
| Terraform | [`src/terraform/`](./src/terraform/) | [README](./src/terraform/README.md) |

### 3. Deploy SOFS

| Tool | Location | Guide |
|------|----------|-------|
| PowerShell | [`src/powershell/`](./src/powershell/) | [README](./src/powershell/README.md) |

### 4. Configure (choose one)

| Tool | Location | Guide |
|------|----------|-------|
| PowerShell | [`src/powershell/`](./src/powershell/) | [README](./src/powershell/README.md) |
| Ansible | [`src/ansible/`](./src/ansible/) | [README](./src/ansible/README.md) |

### 5. Validate

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
