# Repo intent — azurelocal-sofs-fslogix

**Scale-Out File Server (SOFS) and FSLogix profile container automation for Azure Local and AVD.**

## What this repo is

Automation and IaC for deploying a Scale-Out File Server on Azure Local to host
FSLogix profile containers for Azure Virtual Desktop session hosts. Three Windows
Server VMs form a guest Storage Spaces Direct cluster, presenting a SOFS role
with continuously-available SMB shares; anti-affinity rules keep each VM on a
separate physical node for host-level resiliency.

## How it relates to other repos

- **`azurelocal-avd`** — the sister repo for the AVD session-host side of this
  same deployment; this repo only covers the storage/profile side

## Status

Active, early — "under active development," per its own README.
