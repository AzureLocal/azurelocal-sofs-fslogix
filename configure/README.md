# Configure — Phase 3: Post-Deployment Configuration

Configure share permissions, SMB settings, and FSLogix registry settings after the SOFS cluster role is deployed.

> **Choose** PowerShell or Ansible — both achieve the same result.

---

## Options

| Tool | Path | Description |
|------|------|-------------|
| [**PowerShell**](./powershell/) | `configure/powershell/` | Direct WinRM from a Windows workstation |
| [**Ansible**](./ansible/) | `configure/ansible/` | Idempotent, repeatable, cross-platform |

---

## What Gets Configured

| Setting | Tool |
|---------|------|
| NTFS + SMB share permissions for AVD users | PowerShell / Ansible |
| SMB encryption on the SOFS | PowerShell / Ansible |
| Access-based enumeration | PowerShell / Ansible |
| FSLogix registry settings on AVD session hosts | Ansible only |

---

## Quick Start — PowerShell

```powershell
.\configure\powershell\Set-FSLogixShare.ps1 `
  -SOFSName "SOFS01" `
  -ShareName "FSLogixProfiles" `
  -SharePath "C:\ClusterStorage\Volume1\FSLogixProfiles" `
  -AVDUsersGroup "AVD-Users" `
  -ClusterName "AZLHCI-CLUSTER"
```

## Quick Start — Ansible

```bash
# SOFS share settings
ansible-playbook -i configure/ansible/inventory/hosts.yml configure/ansible/playbooks/configure-sofs.yml

# FSLogix on session hosts
ansible-playbook -i configure/ansible/inventory/hosts.yml configure/ansible/playbooks/configure-fslogix.yml
```

---

## Configuration

All tools read parameters from `config/variables.yml`. See [`config/README.md`](../config/README.md) for the full variable reference.

---

## Next Step

After configuration, proceed to [**Phase 4: Tests**](../tests/) to validate the deployment.
