# Azure CLI – SOFS & FSLogix Deployment

Bash scripts using the **Azure CLI** to manage Azure-side resources that support the SOFS/FSLogix deployment on Azure Local.

> **Note:** The SOFS cluster role itself is a Windows Server Failover Clustering feature managed via PowerShell or Windows Admin Center. These scripts focus on the Azure control-plane tasks (resource groups, storage accounts for diagnostics, Arc extensions, etc.).

---

## Scripts

| Script | Description |
|--------|-------------|
| `deploy-prerequisites.sh` | Creates the Azure resource group and any supporting Azure resources |
| `configure-arc-extensions.sh` | Enables Azure Arc extensions on the Azure Local cluster nodes |

---

## Prerequisites

- **Azure CLI** >= 2.50 installed and authenticated (`az login`).
- Bash shell (Linux, macOS, or Windows Subsystem for Linux).
- The Azure Local cluster registered with Azure Arc.

---

## Quick Start

1. Copy the example environment file and fill in your values:
   ```bash
   cp parameters.example.env parameters.env
   # Edit parameters.env with your values
   ```

2. Source the environment file and run the deployment:
   ```bash
   source parameters.env
   ./deploy-prerequisites.sh
   ```

3. (Optional) Configure Arc extensions:
   ```bash
   ./configure-arc-extensions.sh
   ```

---

## Parameters Reference

See `parameters.example.env` for all available parameters and descriptions.
