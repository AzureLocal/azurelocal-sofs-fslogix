# azurelocal-sofs-fslogix

Scripts and automation for deploying a **Scale Out File Server (SOFS)** on **Azure Local** to host **FSLogix** profile containers for **Azure Virtual Desktop (AVD)** session hosts running on Azure Local.

---

## Overview

This repository provides infrastructure-as-code and automation samples for standing up a highly available Scale Out File Server on Azure Local. The SOFS acts as the centralized, SMB-based file share used by FSLogix to store and serve user profile containers (VHD/VHDX) for AVD session hosts.

A companion repository contains examples specifically for the AVD session-host side of the deployment.

---

## Repository Structure

```
azurelocal-sofs-fslogix/
├── docs/                   # Architecture diagrams, getting-started guide, and contributing guide
├── powershell/             # PowerShell scripts for SOFS and FSLogix deployment
├── azure-cli/              # Azure CLI / Bash scripts for deployment
├── bicep/                  # Bicep templates (recommended IaC path for Azure Local)
├── arm/                    # ARM JSON templates
├── terraform/              # Terraform configurations (AzureRM / AzAPI provider)
└── ansible/                # Ansible playbooks for post-deployment configuration
```

---

## Quick-Start by Tool

| Tool | Location | Guide |
|------|-----------|-------|
| PowerShell | [`powershell/`](./powershell/) | [README](./powershell/README.md) |
| Azure CLI | [`azure-cli/`](./azure-cli/) | [README](./azure-cli/README.md) |
| Bicep | [`bicep/`](./bicep/) | [README](./bicep/README.md) |
| ARM | [`arm/`](./arm/) | [README](./arm/README.md) |
| Terraform | [`terraform/`](./terraform/) | [README](./terraform/README.md) |
| Ansible | [`ansible/`](./ansible/) | [README](./ansible/README.md) |

---

## Documentation

- [Architecture Overview](./docs/architecture.md)
- [Getting Started](./docs/getting-started.md)
- [Contributing](./docs/contributing.md)

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

## License

See [LICENSE](./LICENSE) for details.
