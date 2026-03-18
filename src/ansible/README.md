# SOFS on Azure Local — Ansible Deployment

![Status: Untested](https://img.shields.io/badge/status-untested-red)

## Overview

End-to-end Ansible deployment covering Phases 1–11 of the SOFS/FSLogix solution.
Supports all 10 scenarios via `sofs_guest_volume_layout` (Option A / B) and
resiliency settings.

| Playbook | Target | Phases |
|----------|--------|--------|
| `deploy-azure-resources.yml` | `localhost` | 1 (Azure resources) + 2 (domain join) |
| `configure-sofs-cluster.yml` | `sofs_nodes` + `host_cluster` | 3 (anti-affinity) + 5–9c + 11 (validation) |
| `configure-fslogix.yml` | `avd_session_hosts` | FSLogix registry settings |
| `configure-sofs.yml` | `sofs_nodes` | SMB share optimisation |

## Prerequisites

- Python packages: `pywinrm`, `requests-kerberos`
- Azure CLI authenticated (`az login`)
- Install required collections:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

## Files

| File | Purpose |
|------|---------|
| `requirements.yml` | Pinned Ansible collection versions |
| `.ansible-lint` | Linter configuration |
| `inventory/inventory.yml` | Full inventory with all SOFS variables |
| `inventory/hosts.example.yml` | Minimal host template |
| `playbooks/*.yml` | Deployment playbooks |
| `molecule/` | Molecule test scenarios |

## Usage

### 1. Install Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure Inventory

Copy `inventory/inventory.yml` and update:
- Azure subscription ID and resource IDs
- VM IPs in `sofs_nodes`, host IPs in `host_cluster`
- Vault-encrypted credentials

### 3. Deploy Azure Resources + Domain Join

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy-azure-resources.yml \
  --extra-vars "sofs_admin_password=<password> sofs_domain_join_password=<password>"
```

### 4. Configure Guest Cluster (Phases 3, 5–11)

```bash
ansible-playbook -i inventory/inventory.yml playbooks/configure-sofs-cluster.yml \
  --extra-vars "sofs_witness_key=<witness-storage-key>"
```

### 5. Configure FSLogix on AVD Hosts

```bash
ansible-playbook -i inventory/inventory.yml playbooks/configure-fslogix.yml
```

## Testing

```bash
# Lint
ansible-lint src/ansible/

# Molecule (syntax validation)
cd src/ansible && molecule test
```

## Variable Mapping

All `sofs_*` variables in inventory correspond to entries in
`config/variables.yml` and the Terraform inventory template.
