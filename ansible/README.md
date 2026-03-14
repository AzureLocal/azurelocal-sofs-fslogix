# Ansible – SOFS & FSLogix Configuration

Ansible playbooks for Day-2 configuration of the SOFS cluster and FSLogix settings on Azure Local and AVD session hosts.

---

## Playbooks

| Playbook | Description |
|----------|-------------|
| `playbooks/configure-sofs.yml` | Configures SMB share settings and optimisations on the SOFS cluster |
| `playbooks/configure-fslogix.yml` | Applies FSLogix registry settings to AVD session hosts |

---

## Prerequisites

- **Ansible** >= 2.14
- `azure.azcollection` collection:
  ```bash
  ansible-galaxy collection install azure.azcollection
  ```
- WinRM configured on Windows target hosts, or use `ansible_connection: psrp` (PowerShell Remoting).
- Python `pywinrm` on the Ansible control node:
  ```bash
  pip install pywinrm
  ```

---

## Quick Start

1. Copy the example inventory file and fill in your hosts:
   ```bash
   cp inventory/hosts.example.yml inventory/hosts.yml
   # Edit inventory/hosts.yml
   ```

2. Run the SOFS configuration playbook:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/configure-sofs.yml
   ```

3. Run the FSLogix configuration playbook on session hosts:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/configure-fslogix.yml
   ```

---

## Inventory Reference

See `inventory/hosts.example.yml` for inventory structure and variable descriptions.
