#!/usr/bin/env bash
# configure-arc-extensions.sh
# Enables Azure Arc extensions on Azure Local cluster nodes for monitoring and management.
#
# Usage:
#   source parameters.env
#   ./configure-arc-extensions.sh

set -euo pipefail

REQUIRED_VARS=(SUBSCRIPTION_ID CLUSTER_RESOURCE_GROUP CLUSTER_NAME)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Required environment variable '$var' is not set." >&2
        exit 1
    fi
done

echo "=== Configuring Azure Arc Extensions on cluster: $CLUSTER_NAME ==="
az account set --subscription "$SUBSCRIPTION_ID"

# Azure Monitor Agent
echo "Installing Azure Monitor Agent extension..."
az connectedmachine extension create \
    --resource-group "$CLUSTER_RESOURCE_GROUP" \
    --machine-name "$CLUSTER_NAME" \
    --name "AzureMonitorWindowsAgent" \
    --type "AzureMonitorWindowsAgent" \
    --publisher "Microsoft.Azure.Monitor" \
    --output table

# Microsoft Defender for Cloud
echo "Installing Defender for Cloud extension..."
az connectedmachine extension create \
    --resource-group "$CLUSTER_RESOURCE_GROUP" \
    --machine-name "$CLUSTER_NAME" \
    --name "MDE.Windows" \
    --type "MDE.Windows" \
    --publisher "Microsoft.Azure.AzureDefenderForServers" \
    --output table

echo ""
echo "=== Arc extension configuration complete ==="
