# Azure Local SOFS for FSLogix

!!! warning "Under Active Development"
    This repository is a work in progress. Scripts, templates, and automation are **not guaranteed to work** at this time. Use at your own risk and expect breaking changes.

Automation and Infrastructure-as-Code for deploying a **Scale Out File Server (SOFS)** on **Azure Local** to host **FSLogix** profile containers for **Azure Virtual Desktop (AVD)** session hosts.

**Sister repo:** [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/aurelocal-avd) — AVD session host deployment on Azure Local.

---

## Architecture at a Glance

![SOFS Architecture — Three Volume Option B](assets/images/sofs-arch-3vol-option-b.png)

Three Windows Server VMs form a guest **Storage Spaces Direct** cluster on Azure Local. An anti-affinity rule keeps each VM on a separate physical node for host-level resiliency. The guest S2D cluster presents a **Scale-Out File Server** role with continuously available SMB shares that FSLogix uses to store user profile VHDXs.

<div class="grid cards" markdown>

-   :material-vector-triangle:{ .lg .middle } __Architecture__

    ---

    Design decisions, storage layout, capacity planning, AVD considerations, and worked scenarios

    [:octicons-arrow-right-24: Overview](architecture/overview.md)

-   :material-rocket-launch:{ .lg .middle } __Deployment__

    ---

    Prerequisites, variables, tool-specific guides (Terraform, Bicep, ARM, PowerShell, Ansible), and validation

    [:octicons-arrow-right-24: Get Started](deployment/prerequisites.md)

-   :material-wrench:{ .lg .middle } __Configuration__

    ---

    FSLogix registry settings, NTFS/SMB permissions, and antivirus exclusions

    [:octicons-arrow-right-24: Configure](configuration/fslogix.md)

-   :material-tools:{ .lg .middle } __Operations__

    ---

    Troubleshooting, CI/CD pipelines, runner setup, and secrets management

    [:octicons-arrow-right-24: Operate](operations/troubleshooting.md)

</div>

---

## Quick Start

### 1. Configure Variables

```bash
cp config/variables.example.yml config/variables.yml
```

See [Variables Reference](deployment/variables.md) for every parameter.

### 2. Deploy Azure Infrastructure

Choose one tool to create resource group, VMs, NICs, data disks, and cloud witness:

| Tool | Path | Status |
|------|------|--------|
| [Terraform](deployment/terraform.md) | `src/terraform/` | ![Untested](https://img.shields.io/badge/-Untested-6c757d) |
| [Bicep](deployment/bicep.md) | `src/bicep/` | ![In Progress](https://img.shields.io/badge/-In_Progress-ffc107) |
| [ARM](deployment/arm.md) | `src/arm/` | ![Untested](https://img.shields.io/badge/-Untested-6c757d) |
| [PowerShell](deployment/powershell.md) | `src/powershell/` | ![Tested](https://img.shields.io/badge/-Tested-28a745) |
| [Ansible](deployment/ansible.md) | `src/ansible/` | ![Untested](https://img.shields.io/badge/-Untested-6c757d) |

### 3. Configure Guest Cluster (Phases 3–11)

PowerShell covers all phases; Ansible covers phases 5–11:

=== "PowerShell"

    ```powershell
    .\src\powershell\Configure-SOFS-Cluster.ps1 -ConfigFile .\config\variables.yml
    ```

=== "Ansible"

    ```bash
    ansible-playbook -i inventory/hosts.yml \
        src/ansible/playbooks/configure-sofs-cluster.yml
    ```

### 4. Validate

```powershell
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("FSLogix") `
    -ClusterName "sofs-cluster"
```

See [Validation](deployment/validation.md) for the full checklist.

---

## Repository Structure

```
├── src/                   # Automation code by tool
│   ├── terraform/         #   Terraform (azapi + azurerm)
│   ├── bicep/             #   Bicep (subscription-scope)
│   ├── arm/               #   ARM JSON templates
│   ├── powershell/        #   PowerShell scripts (all phases)
│   └── ansible/           #   Ansible playbooks (WinRM/Kerberos)
├── config/                # Central variables.yml — single source of truth
├── docs/                  # This documentation site (MkDocs)
│   ├── architecture/      #   Design decisions & capacity planning
│   ├── deployment/        #   Prerequisites, tool guides, validation
│   ├── configuration/     #   FSLogix, permissions, antivirus
│   ├── operations/        #   Troubleshooting, CI/CD, secrets
│   └── reference/         #   Deployment guide, variables reference
├── tests/                 # Deployment validation scripts
├── scripts/               # Standalone utilities
└── examples/              # Pipeline examples & sample configs
```

## Prerequisites

- An existing **Azure Local** cluster registered with Azure Arc
- Azure subscription with Contributor RBAC
- Windows Server 2025 Datacenter: Azure Edition Core (Gen2) gallery image
- PowerShell 5.1+ with RSAT-Clustering tools
- AD domain with permissions to create computer objects
- For full prerequisites, see [Prerequisites](deployment/prerequisites.md)
