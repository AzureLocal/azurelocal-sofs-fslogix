#!/usr/bin/env bash
# deploy-prerequisites.sh
# Creates the Azure resource group and supporting resources for the SOFS/FSLogix deployment.
#
# Usage:
#   source parameters.env
#   ./deploy-prerequisites.sh
#
# Required environment variables (set via parameters.env or exported before running):
#   SUBSCRIPTION_ID, RESOURCE_GROUP, LOCATION,
#   DIAG_STORAGE_ACCOUNT (optional), TAG_ENVIRONMENT, TAG_OWNER

set -euo pipefail

# -------------------------------------------------------
# Validate required variables
# -------------------------------------------------------
REQUIRED_VARS=(SUBSCRIPTION_ID RESOURCE_GROUP LOCATION)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "ERROR: Required environment variable '$var' is not set." >&2
        echo "       Source parameters.env before running this script." >&2
        exit 1
    fi
done

TAGS="environment=${TAG_ENVIRONMENT:-dev} owner=${TAG_OWNER:-unknown}"

echo "=== SOFS/FSLogix Prerequisites Deployment ==="
echo "  Subscription : $SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location      : $LOCATION"
echo ""

# -------------------------------------------------------
# Set the active subscription
# -------------------------------------------------------
echo "Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "  Done."

# -------------------------------------------------------
# Create resource group
# -------------------------------------------------------
echo "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags $TAGS \
    --output table
echo "  Resource group ready."

# -------------------------------------------------------
# (Optional) Create diagnostic storage account
# -------------------------------------------------------
if [[ -n "${DIAG_STORAGE_ACCOUNT:-}" ]]; then
    echo "Creating diagnostic storage account '$DIAG_STORAGE_ACCOUNT'..."
    az storage account create \
        --name "$DIAG_STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --https-only true \
        --min-tls-version TLS1_2 \
        --tags $TAGS \
        --output table
    echo "  Storage account ready."
fi

echo ""
echo "=== Prerequisites deployment complete ==="
