# SOFS on Azure Local — Ansible Deployment

![Status: Untested](https://img.shields.io/badge/status-untested-red)

## Overview

Two-playbook approach for deploying and configuring the SOFS guest cluster:

| Playbook | Target | Purpose |
|----------|--------|---------|
| `deploy-azure-resources.yml` | `localhost` | Creates Azure resources via `az` CLI (VMs, NICs, disks, witness) |
| `configure-sofs-cluster.yml` | `sofs_nodes` (WinRM) | Configures guest OS: clustering, S2D, SOFS role, SMB share |

## Prerequisites

- Python packages: `pywinrm`, `requests-kerberos` (for WinRM/Kerberos)
- Azure CLI authenticated (`az login`)
- `ansible.windows` collection installed:
  ```bash
  ansible-galaxy collection install ansible.windows
  ```

## Files

| File | Purpose |
|------|---------|
| `inventory.yml` | Host inventory + all SOFS variables |
| `deploy-azure-resources.yml` | Playbook 1: Azure resource deployment (localhost) |
| `configure-sofs-cluster.yml` | Playbook 2: Guest cluster config (WinRM to SOFS VMs) |
| `README.md` | This file |

## Usage

### 1. Configure Inventory

Copy `inventory.yml` and update:
- Azure subscription ID and resource IDs
- VM IPs in the `sofs_nodes` group
- WinRM credentials (use `ansible-vault` for passwords)

### 2. Deploy Azure Resources

```bash
# Dry run
ansible-playbook -i inventory.yml deploy-azure-resources.yml --check

# Deploy
ansible-playbook -i inventory.yml deploy-azure-resources.yml \
  --extra-vars "sofs_admin_password=<password>"
```

### 3. Configure Guest Cluster

After VMs are deployed and domain-joined:

```bash
# Dry run
ansible-playbook -i inventory.yml configure-sofs-cluster.yml --check

# Configure
ansible-playbook -i inventory.yml configure-sofs-cluster.yml \
  --extra-vars "sofs_witness_key=<witness-storage-key>"
```

### 4. End-to-End

```bash
# Full deployment (both playbooks)
ansible-playbook -i inventory.yml deploy-azure-resources.yml \
  --extra-vars "sofs_admin_password=<password>"

# Wait for VMs to be domain-joined, then:
ansible-playbook -i inventory.yml configure-sofs-cluster.yml \
  --extra-vars "sofs_witness_key=<witness-storage-key>"
```

## Variable Mapping

All variables in `inventory.yml` correspond to `wsfc_sofs_*` entries in `configs/variables/assets/master-registry.yaml`.

## References

- [Bicep deployment](../bicep/) — Subscription-scope Bicep wrapper
- [Terraform deployment](../terraform/) — azapi provider module
- [PowerShell scripts](../powershell/) — Azure CLI deploy + guest OS configuration
- [SOFS Deployment Guide](../SOFS-Deployment-Guide.md)
