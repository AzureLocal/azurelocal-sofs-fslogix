# Runner & Agent Setup

Self-hosted runners are **required** for SOFS deployments — the runner must have network access to your Azure Local cluster and domain controllers.

## Why Self-Hosted?

- Azure Local VMs are on-premises, not reachable from cloud-hosted runners
- WinRM (5985/5986), SMB (445), and RPC require direct L3 connectivity
- Domain join operations need a domain-joined or domain-accessible host
- Terraform state backend may be on a private storage account

## Network Requirements

| Port | Protocol | Purpose | Required By |
|------|----------|---------|-------------|
| 5985 | TCP | WinRM HTTP | Ansible, PowerShell |
| 5986 | TCP | WinRM HTTPS | Ansible, PowerShell |
| 445 | TCP | SMB | SOFS share validation |
| 443 | TCP | HTTPS | Azure ARM API, Key Vault, Terraform state |
| 135 | TCP | RPC Endpoint Mapper | Cluster management |
| 3389 | TCP | RDP (optional) | Debugging only |

## Runner OS Recommendations

| Tool | Recommended OS | Notes |
|------|---------------|-------|
| Terraform | Linux or Windows | Linux preferred for consistency |
| Bicep / ARM | Linux or Windows | Azure CLI required |
| Ansible | Linux | Windows Control Node not supported by Ansible |
| PowerShell | Windows Server 2022+ | Required for SOFS/S2D cmdlets, FailoverClusters module |

If you only want one runner, use **Windows Server 2022+** with WSL2 for Ansible, or run two runners (one Linux, one Windows).

---

## GitHub Actions Runner

### Install

```powershell
# On your Windows runner host
mkdir C:\actions-runner; cd C:\actions-runner
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-win-x64-2.321.0.zip -OutFile runner.zip
Expand-Archive runner.zip -DestinationPath .
.\config.cmd --url https://github.com/AzureLocal/azurelocal-sofs-fslogix --token <RUNNER_TOKEN>
.\run.cmd
```

### Labels

Configure with labels so pipelines can target it:
```
--labels self-hosted,azurelocal,windows
```

### Run as service (recommended)

```powershell
.\svc.cmd install
.\svc.cmd start
```

### Linux runner (for Ansible)

```bash
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz
./config.sh --url https://github.com/AzureLocal/azurelocal-sofs-fslogix --token <RUNNER_TOKEN> --labels self-hosted,azurelocal,linux
sudo ./svc.sh install && sudo ./svc.sh start
```

---

## GitLab Runner

### Install on Windows

```powershell
mkdir C:\GitLab-Runner; cd C:\GitLab-Runner
Invoke-WebRequest -Uri https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.exe -OutFile gitlab-runner.exe
.\gitlab-runner.exe install
.\gitlab-runner.exe register --url https://gitlab.com --token <RUNNER_TOKEN> --executor shell --tag-list "azurelocal,windows"
.\gitlab-runner.exe start
```

### Install on Linux

```bash
curl -L --output /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
chmod +x /usr/local/bin/gitlab-runner
gitlab-runner install --user=gitlab-runner
gitlab-runner register --url https://gitlab.com --token <RUNNER_TOKEN> --executor shell --tag-list "azurelocal,linux"
gitlab-runner start
```

---

## Azure DevOps Agent

### Install on Windows

```powershell
mkdir C:\agent; cd C:\agent
Invoke-WebRequest -Uri https://vstsagentpackage.azureedge.net/agent/3.248.0/vsts-agent-win-x64-3.248.0.zip -OutFile agent.zip
Expand-Archive agent.zip -DestinationPath .
.\config.cmd --pool AzureLocal --agent sofs-runner-01 --url https://dev.azure.com/IIC --auth pat --token <PAT>
.\svc.cmd install
.\svc.cmd start
```

### Demands

Pipelines use `demands` to target the right agent:

```yaml
pool:
  name: AzureLocal
  demands:
    - Agent.OS -equals Windows_NT
```

---

## Prerequisites on Runner

Install these on every runner before first pipeline run:

### Windows

```powershell
# Azure CLI
winget install Microsoft.AzureCLI

# Terraform
winget install Hashicorp.Terraform

# PowerShell modules
Install-Module Az -Force -Scope AllUsers
Install-Module FailoverClusters -Force -Scope AllUsers

# Bicep (included with Azure CLI, or standalone)
az bicep install
```

### Linux

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Terraform
sudo apt-get install -y terraform

# Ansible
pip3 install ansible ansible-lint pywinrm
```

---

## Security Considerations

- Run the agent/runner service under a dedicated service account, not a personal account
- Store the runner token in Key Vault or a password manager — do not leave it in scripts
- Restrict runner network access to only the required ports and targets
- Keep runner software and dependencies patched
- Use HTTPS (5986) for WinRM, not HTTP (5985), in production

<!-- TODO: Add diagram showing runner network topology -->
<!-- TODO: Add runner auto-update / maintenance section -->
