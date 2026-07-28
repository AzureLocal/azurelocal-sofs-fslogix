import { defineConfig } from 'vitepress'

export default defineConfig({
  ignoreDeadLinks: true,
  base: '/azurelocal-sofs-fslogix/',
  title: "Azure Local SOFS for FSLogix",
  description: "Governed centrally by HCS Platform Engineering standards",
  themeConfig: {
    logo: '/assets/images/azurelocal-sofs-fslogix-icon.svg',
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Architecture', link: '/architecture' },
      { text: 'Runbooks', link: '/runbooks' }
    ],
    sidebar: [
      {
        text: 'Overview',
        items: [
          { text: 'Introduction', link: '/' }
        ]
      }
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/AzureLocal' }
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © Hybrid Cloud Solutions & AzureLocal'
    }
  }
})



