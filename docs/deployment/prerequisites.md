# Prerequisites

## Overview

Before deploying the SOFS guest cluster, ensure all infrastructure, licensing, identity, and tooling prerequisites are in place. Missing a prerequisite — especially licensing — can halt the deployment mid-way.

---

## Infrastructure

### Azure Local Cluster

- Azure Local cluster with **at least 3 physical nodes**
- Nodes registered with Azure Arc and healthy
- Sufficient raw physical capacity for the SOFS storage volumes (see [Capacity Planning](../architecture/capacity-planning.md)):

| Guest Mirror | Azure Local Volume (Usable) | Raw Physical Required |
|-------------|----------------------------|-----------------------|
| Two-way     | ~12.5 TB (for 5.5 TB usable) | **~25 TB** |
| Three-way   | ~17 TB (for 5.5 TB usable) | **~34 TB** |

### Azure Local Host Volumes

Azure Local CSV host volumes must be **pre-created** before running any automation tool. The automation tools create VMs and disks — they assume the underlying storage volumes already exist.

- **Three volumes (recommended):** One per SOFS VM for fault isolation
- **Single volume (alternative):** One large volume for all three VMs

See [Storage Design](../architecture/storage-design.md) for the design rationale and sizing.

!!! info "Host volume creation is a manual step"
    Creating Azure Local CSV volumes requires PowerShell on a cluster node (`New-Volume`). This is an infrastructure operation, not something IaC tools can automate through the Azure control plane. Future automation for this step is planned.

### Gallery Image

A **Windows Server 2025 Datacenter: Azure Edition Core (Gen2)** gallery image must be registered on the Azure Local cluster.

- Marketplace SKU: `2025-datacenter-azure-edition-core`
- The image must be downloaded and available as a gallery image before VM creation

### Logical Network

A compute logical network must be configured on the Azure Local cluster for the SOFS VMs. This is typically the same network used by AVD session hosts.

### Storage Paths

Azure resource-level storage paths must be created for each CSV volume so that VMs and data disks can be placed on the correct volume. Storage paths map Azure resource IDs to local CSV paths (e.g., `C:\ClusterStorage\SOFS-Vol-01`).

---

## Licensing

!!! warning "Do not skip this section"
    Licensing is the most commonly overlooked prerequisite. Getting it wrong means the SOFS VMs cannot run Storage Spaces Direct.

### Windows Server 2025 Datacenter

**Storage Spaces Direct (S2D) requires Windows Server Datacenter edition.** Standard edition does not support S2D. Each of the 3 SOFS VMs must be licensed for Windows Server 2025 Datacenter.

### Guest Licensing Rights

If your Azure Local hosts are licensed with **Windows Server Datacenter with Software Assurance** or you have an active **Azure Local subscription** that includes Windows Server guest licensing, your guest VM rights **may** already cover the SOFS VMs.

This is **not always included** and depends on:

- How the Azure Local cluster was purchased
- Your volume licensing agreement
- Whether you have Software Assurance or Azure Local per-core subscription

**Check with your Microsoft licensing contact** before assuming guest rights are covered. Without existing guest rights, you need 3 additional Windows Server 2025 Datacenter licenses.

---

## Active Directory and DNS

### Domain Requirements

- Active Directory domain environment (e.g., `improbability.cloud`)
- DNS configured and functional for the domain
- Domain controllers reachable from the compute network where SOFS VMs will reside

### Service Account Permissions

A domain account (or service account) with the following permissions:

| Permission | Required For |
|------------|-------------|
| Create Computer Objects in target OU | Failover Cluster CNO (`iic-sofs`) and SOFS access point (`iic-fslogix`) |
| Join computers to the domain | Domain-joining the 3 SOFS VMs |
| Register DNS A records | Cluster name and SOFS access point DNS registration |
| Create and manage SMB shares | SOFS share creation on the cluster |

### Pre-Staging (Optional but Recommended)

If your environment restricts dynamic Computer Object creation, pre-stage these objects in Active Directory:

| Object | Type | Purpose |
|--------|------|---------|
| `iic-sofs` | Computer | Failover Cluster CNO |
| `iic-fslogix` | Computer | SOFS client access point |

Grant the cluster CNO (`iic-sofs$`) full control over the SOFS access point (`iic-fslogix`) Computer Object. Also create DNS A records manually if dynamic DNS updates are restricted.

---

## Azure RBAC

The identity running the deployment (user, service principal, or managed identity) needs:

| Role | Scope | Required For |
|------|-------|-------------|
| **Contributor** | Resource group | Creating VMs, NICs, disks, storage accounts |
| **Azure Stack HCI VM Contributor** (or equivalent) | Custom location | Creating Arc VMs on Azure Local |
| **Key Vault Secrets User** | Key Vault (if using KV for secrets) | Resolving admin and domain join passwords |

---

## Tooling

Different deployment domains require different tools. Choose your automation tool for Azure resource provisioning and guest configuration. See [Deployment Paths](paths.md) for valid combinations.

### Azure-Side Provisioning

Pick one:

| Tool | Prerequisites |
|------|--------------|
| **Terraform** | Terraform >= 1.5, `azapi` + `azurerm` providers |
| **Bicep** | Azure CLI >= 2.50 with Bicep CLI |
| **ARM** | Azure CLI >= 2.50 or Az PowerShell >= 9.0 |
| **PowerShell** | Azure CLI with `stack-hci-vm` extension |
| **Ansible** | Python 3.9+, Azure CLI, `azure.azcollection` |

### Guest OS Configuration

Pick one:

| Tool | Prerequisites |
|------|--------------|
| **PowerShell** | WinRM access from management workstation to SOFS VMs, RSAT Failover Clustering tools |
| **Ansible** | Python packages: `pywinrm`, `requests-kerberos`; `ansible.windows` collection |

### Host Volume Creation (Manual)

| Tool | Prerequisites |
|------|--------------|
| **PowerShell** | Direct or remote PowerShell access to an Azure Local cluster node |

### Common Requirements

All approaches require:

- **Azure CLI** installed on the management workstation:
    ```powershell
    winget install --id Microsoft.AzureCLI --source winget
    ```
- **`stack-hci-vm` extension** for Arc VM operations:
    ```powershell
    az extension add --name stack-hci-vm --upgrade
    ```
- **RSAT** (Remote Server Administration Tools) for cluster management:
    ```powershell
    Get-WindowsCapability -Name RSAT* -Online |
        Where-Object { $_.State -ne 'Installed' } |
        Add-WindowsCapability -Online
    ```

---

## Deployment Phases Overview

The deployment follows 11 phases across two domains. This table shows what the **current code** implements — see [Deployment Paths](paths.md) for full tool capabilities.

| Phase | Description | Domain | Terraform | Bicep | ARM | PowerShell | Ansible |
|-------|-------------|--------|:---------:|:-----:|:---:|:----------:|:-------:|
| 1 | Azure resource provisioning | Azure | :material-check: | :material-check: | :material-check: | :material-check: | :material-check: |
| 2 | VM creation (NICs, disks) | Azure | :material-check: | :material-check: | :material-check: | :material-check: | :material-check: |
| 3 | Anti-affinity rules | Guest | — | — | — | :material-check: | — |
| 4 | Domain join (Arc extension) | Azure | —¹ | —¹ | —¹ | :material-check: | —¹ |
| 5 | Roles and features | Guest | — | — | — | :material-check: | :material-check: |
| 6 | Cluster creation + cloud witness | Guest | — | — | — | :material-check: | :material-check: |
| 7 | S2D enable + tuning | Guest | — | — | — | :material-check: | :material-check: |
| 8 | SOFS role + SMB shares | Guest | — | — | — | :material-check: | :material-check: |
| 9 | NTFS permissions | Guest | — | — | — | :material-check: | :material-check: |
| 10 | Antivirus exclusions | Guest | — | — | — | :material-check: | :material-check: |
| 11 | Validation | Guest | — | — | — | :material-check: | :material-check: |

¹ Domain join is an Azure-side operation (deploying the `JsonADDomainExtension` Arc extension). All tools **can** do this — the current code only implements it in PowerShell. These are implementation TODOs, not tool limitations.

!!! note
    Terraform, Bicep, and ARM handle **Azure resource provisioning** (Phases 1–2, and potentially Phase 4). Guest OS configuration (Phases 3, 5–11) requires the PowerShell script or Ansible playbook — IaC tools cannot configure Windows Failover Clustering or S2D inside guest VMs.

---

## Pre-Deployment Checklist

- [ ] Azure Local cluster healthy with 3+ nodes
- [ ] Sufficient raw capacity for SOFS volumes
- [ ] Azure Local host CSV volumes created
- [ ] Storage paths created in Azure
- [ ] Windows Server 2025 gallery image registered
- [ ] Compute logical network configured
- [ ] Windows Server Datacenter licensing confirmed
- [ ] AD domain functional, DNS working
- [ ] Service account with required permissions
- [ ] Cluster CNO and SOFS access point pre-staged (if required)
- [ ] Azure RBAC roles assigned
- [ ] Chosen automation tool installed and configured
- [ ] IP addresses reserved for SOFS VMs, cluster, and SOFS access point

---

## Next Steps

- [Variables](variables.md) — Configure the central variable file that drives all deployment tools
- [Deployment Paths](paths.md) — Choose your tool combination
- Choose your deployment tool: [Terraform](terraform.md) | [Bicep](bicep.md) | [ARM](arm.md) | [PowerShell](powershell.md) | [Ansible](ansible.md)
