# Terraform – SOFS & FSLogix Deployment

Terraform configurations using the **AzureRM** provider to deploy Azure-side resources supporting the SOFS/FSLogix solution on Azure Local.

---

## Files

| File | Description |
|------|-------------|
| `main.tf` | Provider configuration and resource definitions |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output value declarations |
| `terraform.tfvars.example` | Example variable values (copy to `terraform.tfvars`) |

---

## Prerequisites

- **Terraform** >= 1.5
- **AzureRM provider** >= 3.75 (declared in `main.tf`)
- Azure CLI authenticated (`az login`) or a service principal configured via environment variables

---

## Quick Start

```bash
# 1. Initialise providers
terraform init

# 2. Copy and fill in variable values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars

# 3. Review the execution plan
terraform plan

# 4. Apply
terraform apply
```

---

## Authentication

The AzureRM provider supports multiple authentication methods:

- **Azure CLI** (default for local development): `az login`
- **Service Principal** (CI/CD): set `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` environment variables
- **Managed Identity** (Azure-hosted agents): set `use_msi = true` in the provider block

---

## Parameters Reference

See `terraform.tfvars.example` for all variable descriptions.
