# Getting Started

This guide walks you through a complete SOFS deployment — from prerequisites to validated, production-ready FSLogix shares. Follow each section in order.

---

## Prerequisites

Before you begin, ensure the following are in place.

### Infrastructure

| Requirement | Details |
|-------------|---------|
| **Azure Local cluster** | Registered with Azure Arc, with S2D enabled and host CSV volumes created |
| **Azure subscription** | Contributor RBAC on the target subscription |
| **Gallery image** | Windows Server 2025 Datacenter: Azure Edition Core (Gen2) imported to the cluster |
| **Network** | A logical network / VLAN reachable by AVD session hosts |
| **AD domain** | Domain controller(s) reachable from the Azure Local network |

### AD Permissions

The account used for guest cluster creation must be able to:

- **Create Computer Objects** in the target OU (for the cluster CNO and SOFS access point)
- **Read/write** the target OU for SOFS-related objects

If your AD environment restricts dynamic Computer Object creation, pre-stage the cluster CNO and SOFS access point Computer Objects in AD before Phase 6.

### Tooling

| Tool | Required For | Install |
|------|-------------|---------|
| **Azure CLI** | VM provisioning, storage paths, domain join | `winget install Microsoft.AzureCLI` |
| **stack-hci-vm extension** | Arc VM creation on Azure Local | `az extension add --name stack-hci-vm` |
| **PowerShell 7+** | Guest configuration (Phases 3–11) | `winget install Microsoft.PowerShell` |
| **RSAT-Clustering** | Failover Cluster management | `Install-WindowsFeature -Name RSAT-Clustering` |
| **Terraform** *(optional)* | If using Terraform for Phase 1 | [terraform.io](https://www.terraform.io/downloads) |

### Licensing

!!! warning "Verify your licensing"
    Each SOFS VM requires a **Windows Server 2025 Datacenter** license. If your Azure Local hosts are licensed with Windows Server Datacenter with Software Assurance or an active Azure Local subscription that includes Windows Server guest licensing, guest VM rights may already cover the SOFS VMs. **Check with your Microsoft licensing contact** — this is not always included and depends on how the Azure Local cluster was purchased and licensed.

---

## Step 1: Make Design Decisions

Before configuring anything, decide on three architecture choices:

### 1.1 — Host Volume Layout

| Choice | Description | When to use |
|--------|------------|-------------|
| **Three host volumes** (recommended) | One CSV per SOFS VM — fault isolation if a volume goes offline | Production deployments |
| **Single host volume** | All 3 VMs on one CSV — simpler but shared fate | Dev/test or small deployments |

### 1.2 — Guest S2D Mirror Level

| Choice | Raw cost | Fault tolerance | When to use |
|--------|---------|-----------------|-------------|
| **Two-way mirror** (recommended) | 2× raw | 1 guest disk failure | Most deployments — host mirror already protects against host failures |
| **Three-way mirror** | 3× raw | 2 guest disk failures | Maximum resiliency — higher raw consumption |

### 1.3 — Guest Share Model

| Choice | Description | When to use |
|--------|------------|-------------|
| **Triple layout — Three Shares** (recommended) | Separate Profiles, ODFC, AppData volumes and shares | 50+ users, production, independent sizing |
| **Single layout — Single Share** | One volume, one share for all FSLogix data | Small deployments, PoC |

See [Architecture Overview](architecture/overview.md) for the full design rationale and [Scenarios](architecture/scenarios.md) for worked examples.

---

## Step 2: Configure Variables

Copy the example configuration and fill in your values:

```bash
cp config/variables.example.yml config/variables.yml
```

!!! danger "Never commit variables.yml"
    `variables.yml` contains environment-specific values and Key Vault references. It is excluded by `.gitignore`.

Edit `config/variables.yml` and set at minimum:

| Section | Key variables |
|---------|--------------|
| `azure` | `subscription_id`, `resource_group`, `location` |
| `azure_local` | `cluster_name`, `custom_location_id`, `logical_network_id`, `gallery_image_name`, `storage_path_id(s)` |
| `vm` | `count`, `processors`, `memory_mb`, `ips` |
| `data_disks` | `count`, `size_gb` |
| `domain` | `fqdn`, `netbios`, `join_username`, `cluster_ou_path` |
| `sofs` | `name`, `cluster_name`, `cluster_ip`, `share_name` or `shares` |
| `s2d` | `volume_name`/`volumes`, `data_copies` |
| `cloud_witness` | `name` |

See [Variable Reference](reference/variables.md) for every parameter with types, defaults, and valid values.

---

## Step 3: Deploy Azure Infrastructure (Phase 1)

Choose one tool to create the resource group, NICs, Arc VMs, data disks, and cloud witness storage account:

=== "Terraform (recommended)"

    ```bash
    cd src/terraform
    terraform init
    terraform plan -var-file="terraform.tfvars"
    terraform apply -var-file="terraform.tfvars"
    ```

    See [Terraform Deployment](deployment/terraform.md) for full details.

=== "Bicep"

    ```bash
    az deployment sub create \
      --location eastus \
      --template-file src/bicep/main.bicep \
      --parameters src/bicep/main.bicepparam
    ```

    See [Bicep Deployment](deployment/bicep.md) for full details.

=== "ARM Templates"

    ```bash
    az deployment group create \
      --resource-group rg-sofs-azl-eus-01 \
      --template-file src/arm/azuredeploy.json \
      --parameters @src/arm/azuredeploy.parameters.json
    ```

    See [ARM Deployment](deployment/arm.md) for full details.

=== "PowerShell"

    ```powershell
    .\src\powershell\Deploy-SOFSInfrastructure.ps1 -ConfigFile .\config\variables.yml
    ```

    See [PowerShell Deployment](deployment/powershell.md) for full details.

=== "Ansible"

    ```bash
    ansible-playbook src/ansible/deploy-sofs-infra.yml -i inventory/hosts.yml
    ```

    See [Ansible Deployment](deployment/ansible.md) for full details.

!!! note "Host volume creation is a prerequisite"
    Azure-side tools create VMs and disks but **not** the host CSV volumes. Create host volumes on the Azure Local cluster directly before running Phase 1. See the [SOFS Design & Deployment Guide](reference/sofs-design-and-deployment-guide.md) Phase 1 for the exact `New-Volume` commands.

### What Phase 1 creates

| Resource | Count | Description |
|----------|-------|-------------|
| Resource group | 1 | Contains all SOFS resources |
| Network interfaces | 3 | One per SOFS VM |
| Arc VMs | 3 | Windows Server 2025 on Azure Local |
| Data disks | 12–21 | 4–7 per VM (for S2D pool) |
| Domain join extension | 3 | Joins each VM to AD |
| Cloud witness storage account | 1 | For guest cluster quorum |

---

## Step 4: Configure Guest Cluster (Phases 3–11)

After Azure infrastructure is deployed and VMs are domain-joined, configure the guest OS:

=== "PowerShell (recommended)"

    ```powershell
    .\src\powershell\Configure-SOFS-Cluster.ps1 -ConfigFile .\config\variables.yml
    ```

=== "Ansible"

    ```bash
    ansible-playbook src/ansible/configure-sofs-cluster.yml -i inventory/hosts.yml
    ```

This covers all remaining phases:

| Phase | Description |
|-------|-------------|
| **3 — Anti-affinity** | Pin each SOFS VM to a different host node |
| **4 — WinRM & firewall** | Enable remoting and open required ports |
| **5 — Failover clustering** | Install features, validate, create guest cluster |
| **6 — Cloud witness** | Configure cluster quorum with Azure Storage |
| **7 — Storage Spaces Direct** | Enable S2D, create volumes |
| **8 — SOFS role** | Add Scale-Out File Server role and shares |
| **9 — NTFS permissions** | Set CREATOR OWNER / modify-this-folder-only ACLs |
| **10 — Antivirus exclusions** | Exclude SOFS paths and FSLogix processes |
| **11 — Validation** | Run smoke tests and failover scenario |

For step-by-step manual commands, see the [SOFS Design & Deployment Guide](reference/sofs-design-and-deployment-guide.md) Part III.

---

## Step 5: Validate

Run the validation script to verify the deployment end-to-end:

```powershell
.\tests\Test-SOFSDeployment.ps1 `
    -SOFSAccessPoint "FSLogixSOFS" `
    -ShareNames @("Profiles", "ODFC", "AppData") `
    -ClusterName "sofs-cluster"
```

### Manual validation checklist

| Check | Command | Expected |
|-------|---------|----------|
| Cluster health | `Get-Cluster -Name "sofs-cluster" | Get-ClusterNode` | All nodes **Up** |
| S2D pool | `Get-StoragePool -CimSession "sofs-cluster" -IsPrimordial $false` | Pool **Online**, HealthStatus **Healthy** |
| Virtual disks | `Get-VirtualDisk -CimSession "sofs-cluster"` | All volumes **Healthy** |
| SOFS role | `Get-ClusterGroup -Cluster "sofs-cluster" \| Where-Object GroupType -eq ScaleOutFileServer` | **Online** |
| SMB shares | `Get-SmbShare -CimSession "sofs-vm-01" -Name "Profiles","ODFC","AppData"` | All shares present with CA enabled |
| SMB access | `Test-Path "\\FSLogixSOFS\Profiles"` (from session host) | **True** |
| Anti-affinity | `Get-ClusterAffinityRule -Cluster "host-cluster"` | Each VM on a different host node |

### Failover test

Drain one host node and verify:

1. The SOFS VM live-migrates to another node
2. SMB shares remain accessible (CA = continuously available)
3. Active FSLogix sessions are uninterrupted

See [Validation](deployment/validation.md) for the complete procedure.

---

## Step 6: Configure AVD Session Hosts

!!! info "Separate deployment"
    AVD session host deployment is outside this repo's scope. See [AzureLocal/azurelocal-avd](https://github.com/AzureLocal/azurelocal-avd) for AVD-specific automation.

After the SOFS is validated, configure FSLogix on your AVD session hosts:

### FSLogix registry keys (Triple layout — Three Shares)

| Container | Registry Path | Value |
|-----------|-------------- |-------|
| **Profiles** | `HKLM\SOFTWARE\FSLogix\Profiles\VHDLocations` | `\\<sofs-access-point>\Profiles` |
| **ODFC** | `HKLM\SOFTWARE\Policies\FSLogix\ODFC\VHDLocations` | `\\<sofs-access-point>\ODFC` |
| **AppData** | Folder Redirection GPO → `\\<sofs-access-point>\AppData\%USERNAME%` | — |

See [FSLogix Configuration](configuration/fslogix.md) for the complete registry reference, Cloud Cache setup, and GPO deployment.

---

## Next Steps

- [Architecture Overview](architecture/overview.md) — Full design rationale, stacked mirror math, capacity planning
- [Capacity Planning](architecture/capacity-planning.md) — Storage sizing worksheets, raw-to-usable calculations
- [SOFS Design & Deployment Guide](reference/sofs-design-and-deployment-guide.md) — Comprehensive reference with every PowerShell command
- [Troubleshooting](operations/troubleshooting.md) — Common issues and resolution steps
- [CI/CD Pipelines](operations/cicd-pipelines.md) — Automated deployment pipelines
