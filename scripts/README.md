# Scripts — Standalone Utilities

Optional utility scripts that are not part of the core deployment workflow.

---

## Scripts

| Script | Description |
|--------|-------------|
| `configure-arc-extensions.sh` | Enables Azure Arc extensions (Azure Monitor + Microsoft Defender) on Azure Local cluster nodes |

---

## Usage

```bash
# Set required environment variables
export SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
export CLUSTER_RESOURCE_GROUP="rg-azurelocal-prod"
export CLUSTER_NAME="azlhci-cluster"

./scripts/configure-arc-extensions.sh
```

---

## Prerequisites

- Azure CLI >= 2.50 authenticated (`az login`).
- The Azure Local cluster already registered with Azure Arc.
