# =============================================================================
# SOFS on Azure Local — Key Vault Secret Resolution
# =============================================================================
# Admin password is fetched directly from Key Vault via az CLI at plan/apply
# time. No TF_VAR_admin_password env var needed from the wrapper script.
# =============================================================================

data "external" "admin_password" {
  program = [
    "az", "keyvault", "secret", "show",
    "--vault-name", var.key_vault_name,
    "--name",       var.key_vault_secret_admin_password,
    "--query",      "{value: value}",
    "-o",           "json"
  ]
}
