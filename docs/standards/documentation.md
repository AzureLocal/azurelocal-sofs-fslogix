# Documentation Standards

> **Canonical reference:** [Documentation Standards (full)](https://azurelocal.cloud/standards/documentation/documentation-standards)  
> **Applies to:** All AzureLocal repositories  
> **Last Updated:** 2026-03-17

---

## Principles

| Principle | Rule |
|-----------|------|
| Documentation-First | Document **before** implementing. Keep docs current with code. |
| Single Source of Truth | One authoritative document per topic. Cross-reference, don't duplicate. |
| Audience-Aware | Write for operators, developers, or executives — with appropriate depth. |
| Actionable | Step-by-step procedures, examples, prerequisites, and outcomes. |

---

## File Naming

| Type | Convention | Pattern | Example |
|------|-----------|---------|---------|
| Directories | lowercase-with-hyphens | `^[a-z][a-z0-9-]*$` | `architecture/`, `getting-started/` |
| Markdown (docs/) | lowercase with hyphens | `*.md` | `storage-design.md` |
| Root files | UPPERCASE | — | `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md` |
| PowerShell scripts | PascalCase | `Verb-Noun.ps1` | `New-SofsCluster.ps1` |
| Config files | lowercase-with-hyphens | — | `variables.example.yml` |

---

## MkDocs Material Conventions

This repo uses **MkDocs Material** with the following conventions:

- **Admonitions**: Use `!!! note`, `!!! warning`, `!!! danger`, `!!! info`, `!!! tip`
- **Code blocks**: Always include a language identifier (e.g., ` ```powershell `, ` ```yaml `)
- **Code copy**: Enabled via `content.code.copy`
- **Mermaid diagrams**: Supported via `pymdownx.superfences` custom fence
- **Tables**: Use standard Markdown tables; use inline HTML only for complex layouts
- **Tabs**: Use `=== "Tab Name"` via `pymdownx.tabbed`

---

## Frontmatter & Metadata

Every documentation page should include:

```markdown
# Page Title

> Brief one-line description of the page's purpose.

---
```

For reference documents, include a metadata block:

| Field | Example |
|-------|---------|
| Status | Active / Draft / Deprecated |
| Applies To | SOFS + FSLogix solution |
| Last Updated | 2026-03-17 |

---

## Diagrams

- Source format: `.drawio` files in `docs/diagrams/`
- Export format: PNG at 2x scale for retina displays
- Reference in Markdown: `![Alt text](../diagrams/filename.png)`
- Keep `.drawio` source and `.png` export in sync

---

## Fictional Company — Infinite Improbability Corp (IIC)

All examples, sample configs, and walkthroughs **must** use IIC. See the [Examples & IIC Policy](examples.md) page for the full reference card.

| Never Use | Use Instead |
|-----------|-------------|
| `contoso`, `fabrikam`, `northwind` | Infinite Improbability Corp |
| `example.com`, `test.com` | `improbability.cloud` |
| Real customer names | IIC naming patterns |

---

## Related Standards

- [Naming Conventions (full reference)](https://azurelocal.cloud/standards/documentation/naming-conventions)
- [Badge Library](https://azurelocal.cloud/standards/documentation/badge-library)
- [Naming Conventions](naming.md)
- [Scripting Standards](scripting.md)
