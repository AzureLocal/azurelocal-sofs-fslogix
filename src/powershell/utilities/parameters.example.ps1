# -------------------------------------------------------
# parameters.example.ps1
# Copy this file to parameters.ps1 and fill in your values.
# DO NOT commit parameters.ps1 – it is excluded by .gitignore.
# -------------------------------------------------------

# Azure Local / Failover Cluster settings
$ClusterName  = "AZLHCI-CLUSTER"          # Network name of the Azure Local failover cluster
$SOFSName     = "SOFS01"                  # SOFS cluster role / client access point name
$ShareName    = "FSLogixProfiles"         # SMB share name
$SharePath    = "C:\ClusterStorage\Volume1\FSLogixProfiles"  # Path on the CSV

# Active Directory settings
$DomainFQDN   = "contoso.local"               # AD domain FQDN
$OUPath       = "OU=Servers,DC=iic,DC=local"      # OU for the SOFS computer object

# FSLogix / AVD settings
$AVDUsersGroup = "AVD-Users"              # AD group whose members mount FSLogix profiles

# Azure settings (used by scripts that interact with the Azure control plane)
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$ResourceGroup  = "rg-azurelocal-prod"
$Location       = "eastus"
