# Automation

Documents every GitHub Actions workflow in this repository.

---

## Workflow Summary

| File | Name | Trigger | Purpose |
|------|------|---------|---------|
| `add-to-project.yml` | Add to Project | Issues/PRs opened or labeled | Adds items to org project board and sets custom fields |
| `deploy-docs.yml` | Deploy Documentation | Push to `main` touching `docs/**` or `mkdocs.yml` | Builds MkDocs site and deploys to GitHub Pages |
| `release-please.yml` | Release Please | Push to `main` | Automates CHANGELOG and releases |
| `validate-automation.yml` | Validate Automation | Push/PR touching `src/**`, `tests/**`, `config/**` | Multi-language CI: schema, PowerShell, Terraform, Bicep, ARM, contracts, Ansible |
| `validate-config.yml` | Validate Configuration | Push/PR touching `config/**` | Validates config YAML against JSON Schema |
| `validate-repo-structure.yml` | Validate Repo Structure | PR to `main` | Checks required files and directories are present |

---

## add-to-project.yml

**Trigger:** `issues` (opened, labeled) and `pull_request` (opened, labeled)  
**Secrets:** `ADD_TO_PROJECT_PAT`

Two-job pipeline:

1. **add-to-project** — Uses `actions/add-to-project@v1.0.2` to add the item to org project board (`AzureLocal/projects/3`). Outputs the item ID.
2. **set-fields** (issues only) — Uses `gh project item-edit` to set:
   - **ID field** — text value `SOFS-{issue_number}`
   - **Solution field** — maps `solution/*` label to a project board single-select option
   - **Priority field** — maps `priority/*` label (`critical`/`high`/`medium`/`low`)
   - **Category field** — maps `type/*` label (`feature`/`bug`/`docs`/`infra`/`refactor`/`security`)

---

## deploy-docs.yml

**Trigger:** Push to `main` touching `docs/**` or `mkdocs.yml`; manual via `workflow_dispatch`  
**Permissions:** `contents: read`, `pages: write`, `id-token: write`  
**Concurrency group:** `pages` (cancel-in-progress: false)

Two-job pipeline:

**build:**
1. Sets up Python 3.12
2. Installs `mkdocs-material`
3. `mkdocs build --strict` — fails on any warning
4. Uploads `site/` as a pages artifact

**deploy:**
1. Uses `actions/deploy-pages@v4` to publish to GitHub Pages

---

## release-please.yml

**Trigger:** Push to `main`  
**Permissions:** `contents: write`, `pull-requests: write`

Uses `googleapis/release-please-action@v4`. Maintains an automated release PR. When conventional commits land on `main`, it updates `CHANGELOG.md` and bumps the version. When the PR is merged, it creates the GitHub release and tag.

---

## validate-automation.yml

**Trigger:** Push to `main` or PR touching `src/**`, `tests/**`, `config/**`; manual via `workflow_dispatch`

This is the main CI workflow. It runs 7 parallel jobs:

**schema** (Ubuntu):
- Validates `config/variables/variables.example.yml` against `config/variables/schema/variables.schema.json` using `jsonschema`

**powershell** (Windows):
- Installs PSScriptAnalyzer, Pester 5, `powershell-yaml`
- PSScriptAnalyzer on `src/powershell/` (Severity Warning — blocks on Error)
- Syntax check: parses every `.ps1` in `src/powershell/` and `tests/`
- Pester tests in `tests/` with JUnit XML output (uploaded as artifact)

**terraform** (Ubuntu):
- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`
- `terraform test`

**bicep** (Ubuntu):
- `az bicep build --file src/bicep/main.bicep` — syntax and lint check

**arm** (Ubuntu, needs bicep):
- Recompiles Bicep to `/tmp/compiled.json`
- Compares against `src/arm/azuredeploy.json` using normalized JSON diff
- Fails if the committed ARM template is out of sync with the Bicep source

**contract** (Ubuntu, needs schema + bicep):
- Validates `$defs.examples` in the JSON schema
- Verifies pass-through parameter annotations (`passThrough: true`) exist in `src/bicep/main.bicep` (requires ≥ 5)
- Verifies all pass-through Bicep params exist in `src/arm/azuredeploy.json`
- Verifies `deployment.guest_layout` in `variables.example.yml` uses canonical values (`single` or `triple`)

**ansible** (Ubuntu):
- `yamllint -d relaxed src/ansible/`
- `ansible-lint src/ansible/playbooks/`
- `ansible-playbook --syntax-check` for every playbook in `src/ansible/playbooks/`

> **Note:** This workflow has pre-existing failures on main — do not treat as a regression.

---

## validate-config.yml

**Trigger:** Push to `main` or PR touching `config/**`; manual via `workflow_dispatch`

1. Sets up Python 3.12
2. Installs `pyyaml`, `jsonschema`
3. Validates `config/variables/variables.example.yml` against `config/variables/schema/variables.schema.json`

---

## validate-repo-structure.yml

**Trigger:** PR to `main`

| Check | Required Items |
|-------|---------------|
| Root files | `README.md`, `CONTRIBUTING.md`, `LICENSE`, `CHANGELOG.md`, `.gitignore` |
| Directories | `docs/`, `.github/` |
| PR template | `.github/PULL_REQUEST_TEMPLATE.md` |
| Config structure (if `config/` exists) | `config/variables.example.yml`, `config/schema/variables.schema.json` |
