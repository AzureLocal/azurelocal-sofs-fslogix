# Plan: Documentation Overhaul Using Deployment Guide as Framework

## TL;DR

Use the comprehensive sofs-deployment-guide.md as the content source to rewrite and expand the `/docs` site. The deployment guide contains deep design rationale, step-by-step procedures, capacity planning, NTFS/SMB details, FSLogix configuration, and troubleshooting that the current docs pages either omit or cover superficially. This plan extracts that knowledge into purpose-built docs pages, adds missing pages (design decisions, storage planning, troubleshooting, automation reference), and ensures every repo artifact (examples, scripts, tests, CI/CD) is properly represented in the docs site.

---

## Gap Analysis: Deployment Guide vs. Current Docs

### What the deployment guide covers that the docs DO NOT:

1. **Design decision framework** — host volume layout (single vs. three), guest volume layout (Option A vs. B), S2D resiliency choices, capacity planning with raw-to-usable ratios. Current `architecture.md` has a basic ASCII diagram and a simple sizing table.

2. **Detailed storage capacity planning** — stacked mirror math, per-layer calculations, raw footprint warnings, thin-provisioning dangers. Current docs have a 3-row "User Count" table with no math.

3. **Complete 11-phase implementation walkthrough** — the current `getting-started.md` has 5 high-level steps with no actual commands for host prep, cluster creation, S2D, anti-affinity, or NTFS permissions.

4. **NTFS permissions model** — CREATOR OWNER, Domain Users modify-this-folder-only, the ACL function. Not in any docs page.

5. **Anti-affinity rules** — both modern (`New-ClusterAffinityRule`) and legacy (`AntiAffinityClassNames`). Not mentioned in docs.

6. **S2D guest tuning** — HwTimeout, auto-replace disable. Not in docs.

7. **Firewall requirements** — port tables for inter-SOFS and SOFS-to-session-host. Current architecture.md mentions 445 and RPC but no complete table.

8. **Cloud witness setup** — storage account creation, `Set-ClusterQuorum`. Not in docs.

9. **FSLogix configuration detail** — Option A vs. B registry keys, ODFC containers, Cloud Cache with connection strings, identity model explanation. Current `architecture.md` has a 5-row registry table.

10. **Antivirus exclusions** — SOFS-side and session-host-side exclusions. Not in docs.

11. **Validation and failover testing** — SMB CA verification, live migration failover test, anti-affinity verification. Current docs just point to `Test-SOFSDeployment.ps1`.

12. **Automation script inventory** — the deployment guide has a full table mapping each tool to phases with descriptions and links. Current docs just list folder paths.

### What the docs have that the deployment guide does NOT:
- CI/CD pipeline guides (cicd-pipelines.md, runner-setup.md, secrets-management.md) — these are good and should be kept
- Contributing guidelines — good, keep
- Standards section — good, keep and extend per the other plan
- MkDocs site structure and nav — keep

---

## Phase 1: Rewrite `architecture.md` — Design & Architecture Deep Dive

**Source content:** Deployment guide Part I (Design) — sections 1–5

**Current state:** Basic ASCII diagram, simple component table, 3-row sizing table, 5-row FSLogix settings table. ~80 lines of content.

**Target state:** Comprehensive design document covering:

### 1.1 — Architecture Overview (rewrite existing)
- Replace ASCII art with Mermaid diagram showing: Azure Local cluster → 3 host volumes → 3 SOFS VMs → guest S2D pool → SOFS role → SMB shares → AVD session hosts
- Add component relationship table with actual resource names (IIC examples)
- Add the "stacked resiliency" concept (host mirror + guest mirror)

### 1.2 — Host Volume Layout (new section)
- Extract "Host Volume Layout: Fault Isolation" from deployment guide
- Three volumes (recommended) vs. single volume — decision criteria
- Volume sizing table
- Why NOT to thin-provision (from the deployment guide's callout box)
- **Cross-ref:** Link to deployment guide for actual commands

### 1.3 — Storage Capacity Planning (new section)
- Extract "Storage Capacity Design" from deployment guide
- Two-way vs. three-way mirror math tables
- Raw-to-usable ratio explanation
- Per-layer calculation walkthrough
- Link to Azure Local Sizer (Odin)

### 1.4 — Guest Volume Layout (new section)
- Extract "Guest Volume Layout: Single vs. Three FSLogix Shares"
- Option A (single) — when to use, diagram
- Option B (three volumes) — when to use, NTFS metadata isolation explanation, FSRM quotas
- Decision table by user count and density

### 1.5 — Network Architecture (expand existing)
- Full port table (from Phase 5 firewall section)
- Inter-SOFS traffic vs. SOFS-to-session-host traffic
- Same-VLAN recommendation with rationale
- Optional dedicated storage VLAN for S2D replication

### 1.6 — Identity & Authentication (new section)
- Extract from "Considerations for AVD Deployment" → Identity Model
- AD domain join requirement for Azure Local
- Kerberos auth flow: session host → SOFS
- Hybrid Entra ID join support note
- Permission groups planning

---

## Phase 2: Rewrite `getting-started.md` — End-to-End Walkthrough

**Source content:** Deployment guide Part II (Implementation) — Phases 1–11

**Current state:** 5 generic steps, no actual commands, references old parameter names (`ClusterName`, `SOFSName`), wrong script names. ~100 lines.

**Target state:** A proper getting-started guide that walks through the deployment using the repo's automation tools, organized by the 11 phases.

### 2.1 — Prerequisites (rewrite)
- Infrastructure requirements (from deployment guide Prerequisites)
- Licensing section (from deployment guide — this is CRITICAL and completely missing)
- AD/DNS requirements
- Tooling requirements (Azure CLI, stack-hci-vm extension, RSAT, PowerShell modules)
- Reference required Azure RBAC permissions

### 2.2 — Configure Variables (rewrite)
- `cp config/variables.example.yml config/variables.yml`
- Highlight the key design decisions to make FIRST (host volume layout, guest volume layout, S2D resiliency)
- Link to the new architecture.md sections for help choosing
- Link to `docs/reference/variables.md` for the complete reference

### 2.3 — Phase 1: Azure Infrastructure (rewrite)
- Choose your tool: Terraform (recommended) / Bicep / ARM / PowerShell / Ansible
- Brief description of what each tool creates (from deployment guide Automation Scripts table)
- Link to each tool's `src/<tool>/README.md`
- Note: Host volume creation is a prerequisite done on the Azure Local cluster directly (Phase 1.1 of deployment guide) — link to deployment guide for manual steps

### 2.4 — Phase 2: Guest Cluster Configuration (new)
- Choose your tool: PowerShell `Configure-SOFS-Cluster.ps1` / Ansible `configure-sofs-cluster.yml`
- What each tool covers (Phases 3–11)
- Link to each tool's README
- Note that anti-affinity rules require host cluster access (not guest)

### 2.5 — Validate (rewrite)
- `Test-SOFSDeployment.ps1` with actual current parameters
- Manual validation steps (from Phase 11 of deployment guide)
- Failover test procedure (from Phase 11.2)

### 2.6 — Troubleshooting (expand)
- Expand the 4-row troubleshooting table with real issues from the deployment guide (S2D timeout, cloud witness connectivity, NTFS permission errors, etc.)
- Link to new troubleshooting guide (Phase 5)

---

## Phase 3: Create `docs/guides/design-decisions.md` — Decision Guide

**New page.** A focused decision-making guide for someone planning a SOFS deployment.

### Content:
- Decision tree flowchart (Mermaid) walking through each choice:
  1. How many host volumes? → single vs. three → depends on cluster capacity and fault isolation requirements
  2. S2D resiliency? → two-way vs. three-way → depends on risk tolerance and raw capacity
  3. Guest volume layout? → Option A vs. Option B → depends on user count and workload
  4. Guest config engine? → PowerShell vs. Ansible → depends on team skills and existing tooling
- Each decision links back to the detailed rationale in `architecture.md`
- "Quick recommendation" callout for the most common scenario (three host volumes, two-way mirror, Option A, PowerShell)

---

## Phase 4: Create `docs/guides/automation-tools.md` — Automation Reference

**New page.** The deployment guide's "Automation Scripts" section (Part III) is excellent content that should live in the docs site.

### Content:
- Central configuration table (from deployment guide)
- Phase 1 tools table: Terraform, Bicep, ARM, PowerShell, Ansible — path, description, what it creates
- Phase 2 tools table: PowerShell, Ansible — path, phases covered, description
- Supplemental scripts table: `New-SOFSDeployment.ps1`, `Set-FSLogixShare.ps1`
- Supplemental playbooks table: `configure-sofs.yml`, `configure-fslogix.yml`
- Validation tools table: `Test-SOFSDeployment.ps1`
- Pre-deployment scripts table: `deploy-prerequisites.sh`, `configure-arc-extensions.sh`
- CI/CD pipeline examples table: links to `examples/pipelines/` by platform
- "Which tool should I use?" decision matrix

---

## Phase 5: Create `docs/guides/troubleshooting.md`

**New page.** Consolidate troubleshooting from across the deployment guide.

### Content:
- Common deployment failures by phase (cluster validation fails, S2D won't enable, SOFS role fails to create, cloud witness errors)
- FSLogix profile issues (VHD mount fails, profile corruption, slow logon)
- Network/firewall issues (SMB not reachable, WinRM timeouts)
- Permission issues (NTFS ACL wrong, SMB share access denied)
- Antivirus interference (from Phase 10)
- Capacity issues (volume full, S2D pool degraded)
- Validation script output interpretation
- Each entry: Symptom → Diagnosis steps → Resolution

---

## Phase 6: Create `docs/guides/fslogix-configuration.md`

**New page.** Extract FSLogix configuration detail from the deployment guide's "Considerations for AVD Deployment" section.

### Content:
- How FSLogix maps users to shares (the explanation from the deployment guide is excellent)
- Option A registry keys (VHDLocations, SizeInMBs, VolumeType, FlipFlop)
- Option B registry keys (separate Profile + ODFC + AppData configs)
- GPO deployment path
- Cloud Cache configuration (connection string format, primary/secondary providers)
- Antivirus exclusions on session hosts (from Phase 10.2)
- Profile sizing guidance
- Link to the Ansible playbook `configure-fslogix.yml` for automated setup

---

## Phase 7: Create `docs/guides/permissions.md`

**New page.** NTFS and SMB permissions are critical and currently undocumented in the docs site.

### Content:
- SMB share permissions model (Full Access for admins, Change for Domain Users, ABE enabled)
- NTFS permissions model — the `Set-FSLogixNTFS` function with explanation of each ACE:
  - CREATOR OWNER — Modify (subfolders/files only)
  - Domain Users — Modify (this folder only)
  - Domain Admins — Full Control (all)
  - SYSTEM — Full Control (all)
- Why this specific ACL structure matters for FSLogix
- Option A (single share) vs. Option B (three shares) permission application
- SMB encryption and caching mode settings
- Continuously Available shares requirement

---

## Phase 8: Update `docs/index.md` — Home Page Refresh

**Current state:** Workflow diagram and 5-step quickstart with old script names and limited context.

**Changes:**
- Update the workflow to reflect the actual phases (11 phases, not 5)
- Add a "What This Repo Deploys" section with a Mermaid architecture diagram
- Add a "Key Design Decisions" callout linking to `guides/design-decisions.md`
- Fix script names and parameters to match current codebase
- Add links to all new guide pages
- Add "New to SOFS?" callout linking to `architecture.md`
- Update prerequisites to match deployment guide (licensing, RSAT, stack-hci-vm extension)

---

## Phase 9: Update `mkdocs.yml` Navigation

Add all new pages to the nav:

```yaml
nav:
  - Home: index.md
  - Architecture: architecture.md
  - Getting Started: getting-started.md
  - Guides:
      - Design Decisions: guides/design-decisions.md           # NEW
      - Automation Tools: guides/automation-tools.md           # NEW
      - FSLogix Configuration: guides/fslogix-configuration.md # NEW
      - Permissions: guides/permissions.md                     # NEW
      - Troubleshooting: guides/troubleshooting.md             # NEW
      - CI/CD Pipelines: guides/cicd-pipelines.md
      - Runner & Agent Setup: guides/runner-setup.md
      - Secrets Management: guides/secrets-management.md
  - Reference:
      - Variables: reference/variables.md
      - SOFS Deployment Guide: reference/sofs-deployment-guide.md
  - Standards:
      - Overview: standards/index.md
      - Automation: standards/automation.md
      - Naming: standards/naming.md
      - Scripts: standards/scripts.md
      - Documentation: standards/documentation.md
      - Solutions: standards/solutions.md
      - Variables: standards/variables.md
      - Examples: standards/examples.md
  - Roadmap: roadmap.md
  - Contributing: contributing.md
```

---

## Phase 10: Update `README.md`

**Current state:** Generic overview with wrong link paths and basic structure.

**Changes:**
- Add badges (build status, MkDocs, license)
- Update "Documentation" links to include all new guide pages
- Update Quick Start to reference new getting-started.md structure
- Mention the deployment guide as the standalone comprehensive reference
- Fix sister repo links
- Add "Architecture at a Glance" section with brief description + link

---

## Phase 11: Create Missing Asset — Architecture Diagram

**New file:** `docs/assets/diagrams/sofs-architecture.mermaid` (or embed inline)

Create Mermaid diagrams to replace/supplement the existing PNG references in the deployment guide:

1. **High-level architecture** — Azure Local cluster → SOFS VMs → SMB shares → AVD hosts
2. **Host volume layouts** — Three-volume vs. single-volume comparison
3. **Guest volume layouts** — Option A vs. Option B
4. **Deployment phase flow** — 11 phases with tool coverage overlay

These diagrams should be used in `architecture.md`, `getting-started.md`, and `guides/design-decisions.md`.

---

## Relevant Files

### CREATE:
- `docs/guides/design-decisions.md` — Decision guide with flowcharts (Phase 3)
- `docs/guides/automation-tools.md` — Complete automation tool reference (Phase 4)
- `docs/guides/troubleshooting.md` — Consolidated troubleshooting (Phase 5)
- `docs/guides/fslogix-configuration.md` — FSLogix config for AVD session hosts (Phase 6)
- `docs/guides/permissions.md` — NTFS/SMB permissions reference (Phase 7)

### REWRITE:
- `docs/architecture.md` — From ~80 lines to comprehensive design doc (Phase 1)
- `docs/getting-started.md` — From ~100 lines to phase-aligned walkthrough (Phase 2)
- `docs/index.md` — Home page refresh with new links and diagrams (Phase 8)
- `README.md` — Update links, add badges, fix paths (Phase 10)

### UPDATE:
- `mkdocs.yml` — Add nav entries for all new pages (Phase 9)
- `docs/standards/documentation.md` — Update file tree to reflect new structure (minor)

### REFERENCE (no changes):
- `docs/reference/sofs-deployment-guide.md` — Source content; remains standalone
- `docs/guides/cicd-pipelines.md` — Already good; no changes needed
- `docs/guides/runner-setup.md` — Already good; no changes needed
- `docs/guides/secrets-management.md` — Already good; no changes needed

---

## Verification

1. `mkdocs build --strict` passes — no broken links, no orphaned pages, no missing nav entries
2. Every section from the deployment guide's table of contents has a corresponding docs page or section with cross-reference
3. Every automation tool in the repo (`src/terraform/`, `src/bicep/`, `src/arm/`, `src/powershell/`, `src/ansible/`) is documented in `guides/automation-tools.md`
4. Every `examples/` directory is referenced from the docs
5. The deployment guide's FSLogix configuration, NTFS permissions, antivirus exclusions, and Cloud Cache content are all represented in dedicated guide pages
6. Architecture diagrams render correctly in all pages that reference them
7. No duplicate content — docs pages reference the deployment guide for detailed commands rather than copying entire code blocks
8. Manual nav walkthrough: a new user can navigate from Home → Architecture → Getting Started → their chosen tool README without dead ends

---

## Decisions

- **Don't duplicate the deployment guide** — The docs pages should provide design rationale, decision guidance, and tool-specific instructions. For raw step-by-step commands, link to the deployment guide (it's already in the docs site at `reference/sofs-deployment-guide.md`).
- **Deployment guide stays standalone** — It remains the self-contained reference. The docs site wraps it with better navigation, discovery, and tool integration.
- **Existing CI/CD guides are good** — `cicd-pipelines.md`, `runner-setup.md`, and `secrets-management.md` need no changes in this plan.
- **Mermaid over PNG** — Use Mermaid diagrams where possible for maintainability. Keep existing PNGs as fallback references.

---

## Suggestions

1. **Add `docs/guides/day2-operations.md`** — Cover monitoring, alerting, capacity expansion, disk replacement, and cluster maintenance. The deployment guide touches on backup/DR with Cloud Cache but day-2 ops aren't documented anywhere. This would be valuable as a future addition.

2. **Add `docs/guides/storage-planning-calculator.md`** — An interactive-style page (or embedded spreadsheet) where users plug in their user count, profile size, and resiliency choice and get the raw capacity requirement. The deployment guide has the formulas; a dedicated page would make it easier to use.

3. **Consider a "Quick Deploy" path** — For users who don't need to understand all the design decisions, add a "Quick Deploy" section to getting-started.md that picks the most common defaults (three host volumes, two-way mirror, Option A, PowerShell) and walks through the minimal steps. Link to architecture.md for "why."

4. **Add per-tool README audit** — Each `src/<tool>/README.md` should be reviewed and updated to match the new docs structure. Those READMEs are the first thing someone sees when browsing GitHub — they should link back to the MkDocs site. This is a follow-on task, not part of this plan.

5. **Cross-link with sister repo** — `aurelocal-avd` docs should link to the SOFS guides for FSLogix configuration (since FSLogix runs on the session hosts deployed by the AVD repo). Add a "Related: SOFS for FSLogix" link in the AVD repo's docs.
