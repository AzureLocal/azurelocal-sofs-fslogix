# azurelocal-sofs-fslogix

![Azure Local SOFS for FSLogix](docs/assets/images/azurelocal-sofs-fslogix-banner.svg)

[![Azure Local](https://img.shields.io/badge/Azure%20Local-azurelocal.cloud-0078D4?logo=microsoft-azure)](https://azurelocal.cloud)

Documentation: [azurelocal.cloud](https://azurelocal.cloud) | Solutions: [Azure Local Solutions](https://azurelocal.cloud)

> **⚠️ Under Active Development** — This repository is a work in progress. Scripts, templates, and automation are **not guaranteed to work** at this time. Use at your own risk and expect breaking changes.

Automation and Infrastructure-as-Code for deploying a **Scale Out File Server (SOFS)** on **Azure Local** to host **FSLogix** profile containers for **Azure Virtual Desktop (AVD)** session hosts.

---

## Overview

Three Windows Server VMs form a guest Storage Spaces Direct cluster on Azure Local, presenting a Scale-Out File Server role with continuously available SMB shares for FSLogix profile containers. Anti-affinity rules keep each VM on a separate physical node for host-level resiliency.

For the AVD session-host side of the deployment, see the sister repository: [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/azurelocal-avd).

---

## Documentation

Full documentation is published via MkDocs:

| Section | Description |
|---------|-------------|
| [Architecture](./docs/architecture/overview.md) | Design decisions, storage layout, capacity planning, AVD considerations, worked scenarios |
| [Deployment](./docs/deployment/prerequisites.md) | Prerequisites, variables, tool-specific guides (Terraform, Bicep, ARM, PowerShell, Ansible), validation |
| [Configuration](./docs/configuration/fslogix.md) | FSLogix registry settings, NTFS/SMB permissions, antivirus exclusions |
| [Operations](./docs/operations/troubleshooting.md) | Troubleshooting, CI/CD pipelines, runner setup, secrets management |

---

## Repository Structure

```
azurelocal-sofs-fslogix/
├── src/                       # Automation code by tool
│   ├── terraform/             #   Terraform (azapi + azurerm) — Untested
│   ├── bicep/                 #   Bicep (subscription-scope) — In Progress
│   ├── arm/                   #   ARM JSON templates — Untested
│   ├── powershell/            #   PowerShell scripts (all phases) — Tested
│   └── ansible/               #   Ansible playbooks (WinRM/Kerberos) — Untested
├── config/                    # Central variables.yml — single source of truth
├── docs/                      # Documentation site (MkDocs Material)
│   ├── architecture/          #   Design decisions & capacity planning
│   ├── deployment/            #   Prerequisites, tool guides, validation
│   ├── configuration/         #   FSLogix, permissions, antivirus
│   ├── operations/            #   Troubleshooting, CI/CD, secrets
│   └── reference/             #   Deployment guide, variables reference
├── tests/                     # Deployment validation scripts
├── scripts/                   # Standalone utilities
└── examples/                  # Pipeline examples & sample configs
```

---

## Quick Start

### 1. Configure Variables

```bash
cp config/variables.example.yml config/variables.yml
# Edit config/variables.yml with your environment values
```

### 2. Deploy Azure Infrastructure (choose one)

| Tool | Location | Status | Guide |
|------|----------|--------|-------|
| Terraform | [`src/terraform/`](./src/terraform/) | Untested | [Terraform Guide](./docs/deployment/terraform.md) |
| Bicep | [`src/bicep/`](./src/bicep/) | In Progress | [Bicep Guide](./docs/deployment/bicep.md) |
| ARM | [`src/arm/`](./src/arm/) | Untested | [ARM Guide](./docs/deployment/arm.md) |
| PowerShell | [`src/powershell/`](./src/powershell/) | Tested | [PowerShell Guide](./docs/deployment/powershell.md) |
| Ansible | [`src/ansible/`](./src/ansible/) | Untested | [Ansible Guide](./docs/deployment/ansible.md) |

### 3. Configure Guest Cluster (Phases 3–11)

```powershell
.\src\powershell\Configure-SOFS-Cluster.ps1 -ConfigFile .\config\variables.yml
```

### 4. Validate

```powershell
.\tests\Test-SOFSDeployment.ps1 -SOFSAccessPoint "FSLogixSOFS" -ShareNames @("FSLogix")
```

---

## Prerequisites

- An existing **Azure Local** cluster registered with Azure Arc
- Azure subscription with Contributor RBAC
- Windows Server 2025 Datacenter: Azure Edition Core (Gen2) gallery image
- AD domain with permissions to create computer objects
- For full prerequisites, see [Prerequisites](./docs/deployment/prerequisites.md)

---

## Contributing

See [CONTRIBUTING.md](./docs/contributing.md) for coding standards, branch strategy, and PR guidelines.

---

## Sister Repositories

| Repository | Description |
|------------|-------------|
| [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/azurelocal-avd) | Azure Virtual Desktop session host deployment on Azure Local |

---

## License

See [LICENSE](./LICENSE) for details.
