# Getting Started

This guide walks you through deploying a Scale Out File Server (SOFS) on Azure Local for FSLogix profile containers from scratch.

---

## Prerequisites

Before you begin, ensure you have the following in place:

### Azure Local Cluster
- An **Azure Local cluster** (version 22H2 or later) that is registered with Azure Arc.
- At least **2 cluster nodes** with Storage Spaces Direct (S2D) enabled.
- Available **Clustered Shared Volume (CSV)** capacity for profile storage.
- The cluster nodes joined to an Active Directory domain.

### Client Machine / Jump Host
- **PowerShell 5.1** or later (Windows Server / Windows 10+).
- **RSAT – Failover Clustering** tools installed (`Install-WindowsFeature RSAT-Clustering`).
- **Azure CLI** >= 2.50 _or_ **Az PowerShell** >= 9.0 (for Azure-side operations).
- Network connectivity to the Azure Local cluster management interface.

### Permissions
- Local Administrator on the Azure Local cluster nodes.
- Active Directory permissions to create computer objects in the designated OU (for the SOFS cluster name).
- Azure RBAC **Contributor** or higher on the Azure subscription / resource group.

---

## Deployment Steps

### 1. Choose Your Automation Tool

Pick the approach that best fits your team's workflow:

| Tool | Phase | When to use |
|------|-------|-------------|
| [Bicep](../infrastructure/bicep/README.md) | 1 — Infrastructure | Azure-native IaC, **recommended** for new deployments |
| [ARM](../infrastructure/arm/README.md) | 1 — Infrastructure | Legacy IaC or tooling that requires JSON templates |
| [Terraform](../infrastructure/terraform/README.md) | 1 — Infrastructure | Multi-cloud IaC, GitOps workflows |
| [Azure CLI](../infrastructure/azure-cli/README.md) | 1 — Infrastructure | Cross-platform CLI, CI/CD pipelines |
| [PowerShell (deploy)](../deploy/README.md) | 2 — Deploy | SOFS cluster role creation |
| [PowerShell (configure)](../configure/README.md) | 3 — Configure | Share permissions, SMB settings |
| [Ansible](../configure/ansible/README.md) | 3 — Configure | Configuration management, Day-2 operations |

### 2. Configure Parameters

All tools read from a central variables file. Copy the example and fill in your values:

```bash
cp config/variables.example.yml config/variables.yml
```

Each tool folder also contains its own example parameters file for tool-specific use.

Key parameters to set:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `ClusterName` | Failover cluster network name | `AZLHCI-CLUSTER` |
| `SOFSName` | SOFS cluster role name | `SOFS01` |
| `ShareName` | SMB share name for profiles | `FSLogixProfiles` |
| `SharePath` | Local path on the CSV | `C:\ClusterStorage\Volume1\FSLogixProfiles` |
| `ResourceGroup` | Azure resource group | `rg-azurelocal-prod` |
| `Location` | Azure region | `eastus` |

### 3. Deploy the SOFS

Follow the README in your chosen tool's folder for step-by-step commands.

### 4. Configure FSLogix on Session Hosts

After the SOFS share is available, configure FSLogix on each AVD session host:

**Via Group Policy (recommended):**

1. Create a GPO linked to the OU containing the session hosts.
2. Navigate to **Computer Configuration → Administrative Templates → FSLogix → Profile Containers**.
3. Set **Enabled** to `Enabled`.
4. Set **VHD Location** to `\\<SOFSName>\<ShareName>`.

**Via PowerShell (quick test):**

```powershell
$RegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
New-Item -Path $RegPath -Force | Out-Null
Set-ItemProperty -Path $RegPath -Name "Enabled"          -Value 1 -Type DWord
Set-ItemProperty -Path $RegPath -Name "VHDLocations"     -Value "\\SOFS01\FSLogixProfiles"
Set-ItemProperty -Path $RegPath -Name "FlipFlopProfileDirectoryName" -Value 1 -Type DWord
```

### 5. Validate

Run the validation script to confirm the share is accessible and FSLogix settings are correct:

```powershell
.\tests\Test-SOFSDeployment.ps1 -SOFSName "SOFS01" -ShareName "FSLogixProfiles"
```

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| SMB share not reachable | Firewall / network | Open TCP 445 between session hosts and cluster nodes |
| Profile VHD fails to mount | Permissions on share | Grant AVD users Full Control on `\\SOFS\FSLogixProfiles` |
| SOFS role offline | CSV not online | Bring CSV online via Failover Cluster Manager |
| Slow profile load | Insufficient storage IOPS | Review CSV performance counters; consider NVMe-backed CSV |

---

## Next Steps

- Review the [Architecture Overview](./architecture.md) for design details.
- See [Contributing](./contributing.md) to add improvements to this repo.
