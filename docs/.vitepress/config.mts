import { defineConfig } from 'vitepress'

export default defineConfig({
  ignoreDeadLinks: true,
  base: '/azurelocal-sofs-fslogix/',
  title: "Azure Local SOFS for FSLogix",
  description: "Governed centrally by HCS Platform Engineering standards",
  themeConfig: {
    logo: '/assets/images/azurelocal-sofs-fslogix-icon.svg',
    nav: [{"link":"/","text":"Home"},{"link":"/getting-started","text":"Getting Started"},{"items":[{"link":"/architecture/overview","text":"Overview"},{"link":"/architecture/storage-design","text":"Storage Design"},{"link":"/architecture/capacity-planning","text":"Capacity Planning"},{"link":"/architecture/avd-considerations","text":"AVD Considerations"},{"link":"/architecture/scenarios","text":"Scenarios"}],"text":"Architecture"},{"items":[{"link":"/deployment/prerequisites","text":"Prerequisites"},{"link":"/deployment/paths","text":"Deployment Paths"},{"link":"/deployment/terraform","text":"Terraform"},{"link":"/deployment/bicep","text":"Bicep"},{"link":"/deployment/arm","text":"ARM Templates"},{"link":"/deployment/powershell","text":"PowerShell"},{"link":"/deployment/ansible","text":"Ansible"},{"link":"/deployment/validation","text":"Validation"}],"text":"Deployment"},{"items":[{"link":"/configuration/fslogix","text":"FSLogix"},{"link":"/configuration/permissions","text":"Permissions"},{"link":"/configuration/antivirus","text":"Antivirus Exclusions"}],"text":"Configuration"},{"items":[{"link":"/operations/troubleshooting","text":"Troubleshooting"},{"link":"/operations/cicd-pipelines","text":"CI/CD Pipelines"},{"link":"/operations/runner-setup","text":"Runner & Agent Setup"},{"link":"/operations/secrets-management","text":"Secrets Management"}],"text":"Operations"},{"items":[{"link":"/reference/variables","text":"Variables"},{"link":"/reference/phase-ownership","text":"Phase Ownership Matrix"},{"link":"/reference/sofs-design-and-deployment-guide","text":"SOFS Design & Deployment Guide"}],"text":"Reference"},{"link":"/roadmap","text":"Roadmap"},{"link":"/contributing","text":"Contributing"}],
    sidebar: [{"link":"/","text":"Home"},{"link":"/getting-started","text":"Getting Started"},{"text":"Architecture","items":[{"link":"/architecture/overview","text":"Overview"},{"link":"/architecture/storage-design","text":"Storage Design"},{"link":"/architecture/capacity-planning","text":"Capacity Planning"},{"link":"/architecture/avd-considerations","text":"AVD Considerations"},{"link":"/architecture/scenarios","text":"Scenarios"}],"collapsed":false},{"text":"Deployment","items":[{"link":"/deployment/prerequisites","text":"Prerequisites"},{"link":"/deployment/paths","text":"Deployment Paths"},{"link":"/deployment/terraform","text":"Terraform"},{"link":"/deployment/bicep","text":"Bicep"},{"link":"/deployment/arm","text":"ARM Templates"},{"link":"/deployment/powershell","text":"PowerShell"},{"link":"/deployment/ansible","text":"Ansible"},{"link":"/deployment/validation","text":"Validation"}],"collapsed":false},{"text":"Configuration","items":[{"link":"/configuration/fslogix","text":"FSLogix"},{"link":"/configuration/permissions","text":"Permissions"},{"link":"/configuration/antivirus","text":"Antivirus Exclusions"}],"collapsed":false},{"text":"Operations","items":[{"link":"/operations/troubleshooting","text":"Troubleshooting"},{"link":"/operations/cicd-pipelines","text":"CI/CD Pipelines"},{"link":"/operations/runner-setup","text":"Runner & Agent Setup"},{"link":"/operations/secrets-management","text":"Secrets Management"}],"collapsed":false},{"text":"Reference","items":[{"link":"/reference/variables","text":"Variables"},{"link":"/reference/phase-ownership","text":"Phase Ownership Matrix"},{"link":"/reference/sofs-design-and-deployment-guide","text":"SOFS Design & Deployment Guide"}],"collapsed":false},{"link":"/roadmap","text":"Roadmap"},{"link":"/contributing","text":"Contributing"}],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/AzureLocal/azurelocal-sofs-fslogix' }
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © Hybrid Cloud Solutions & AzureLocal'
    }
  }
})




