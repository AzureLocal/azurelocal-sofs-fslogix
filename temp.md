# SOFS Phase-Driven Compliance and Decision-Tree Plan

## Implementation Progress (feature/epic-59-completion)

Status snapshot (repository implementation):

- Completed: canonical guest layout migration scaffolding (`single`/`triple`) with legacy alias compatibility (`option_a`/`option_b`) in schema, PowerShell, Terraform, Bicep, ARM parameters, and Ansible inventory/playbooks.
- Completed: PowerShell Phase 0 preflight ownership logging and layout normalization with strict per-layout validation.
- Completed: PowerShell triple-layout gating fix so single-layout-only fields are not required/resolved before branch decision.
- Completed: Bicep/ARM parity update to support optional static NIC IP assignment (`vmIps`) in Azure Stack HCI NIC definitions.
- Completed: Ansible Azure deployment static IP parity path (`sofs_vm_ips`) with deterministic NIC updates.
- Completed: repo-wide markdown documentation terminology parity migration to canonical single/triple naming.
- Completed: full test/evidence matrix refresh across task scopes (#67, #68, #69), including canonical layout naming, phase ownership clarity, and reproducible test evidence mapping.

Note:

- GitHub issue state transitions (reopen/close/edit on remote issues) are tracked as process tasks but require direct GitHub issue operations outside this local repository change set.


## Scope and Goal

This report reframes deployment compliance around the architecture model in docs:

- Phase 0: planning checkpoint and method selection.
- Phases 1-11: execution phases across Azure/Host and Guest OS layers.
- Explicit layer handoff after Phase 2.

Goal:

- Make variable-driven method selection the authoritative control plane.
- Ensure every tool follows the same decision tree contract.
- Prepare migration from Option A/Option B naming to single/triple layout naming.

References used in this pass:

- docs/architecture/overview.md (Phase 0 + 11 phases + handoff)
- docs/reference/variables.md
- docs/reference/sofs-design-and-deployment-guide.md
- src/powershell/*
- src/terraform/*
- src/bicep/*
- src/arm/*
- src/ansible/*
- ../azurelocal-avd/docs/architecture.md (plane split naming convention)

---

## Governing Architecture Contract

The deployment model should be treated as:

1. Phase 0 decides method and execution ownership by variable state.
2. Phases 1-2 are Azure/Host plane provisioning and bootstrap.
3. Phases 3-11 are Guest OS cluster and workload configuration.
4. Any tool can own one or more phases, but no tool may claim phases it does not execute.

Cross-repo naming alignment from AVD architecture:

- AVD uses explicit plane naming: control plane vs session-host plane.
- SOFS should mirror this pattern as Azure/Host plane vs Guest OS plane.
- Method labels should express behavior directly, not implementation history.

---

## Current State Findings (Phase-Oriented)

1. Phase 0 decision output is not uniformly enforced across tools.

- PowerShell supports singular and map storage path fallback.
- Terraform and Ansible expect map storage paths.
- Bicep/ARM expose many phase-control parameters but do not consume several in Azure execution logic.

2. Phase ownership claims are broader than actual execution in some paths.

- Bicep/ARM parameter surfaces imply guest/layout behavior, but guest phases are delegated.
- Ansible guest phases are strong, but Azure NIC static IP behavior is not aligned with documented deterministic provisioning.

3. Phase 3+ layout selection has a PowerShell gating defect.

- Option B path can fail if Option A fields are resolved before branch execution.

4. Phase 6+ operations parity differs by guest engine.

- PowerShell includes FSRM flow.
- Ansible configure path does not currently include FSRM parity.

---

## Strict Compliance Matrix by Phase Group

Legend:

- Compliant: tool executes documented behavior for the phase group.
- Partial: tool participates but behavior is delegated/incomplete.
- Non-compliant: behavior claimed or expected but not actually implemented.

| Phase Group | PowerShell | Terraform | Bicep | ARM | Ansible |
|---|---|---|---|---|---|
| Phase 0 planning contract enforcement | Partial | Partial | Non-compliant | Non-compliant | Partial |
| Phases 1-2 Azure/Host provisioning | Compliant | Compliant | Partial | Partial | Partial |
| Phases 3-5 guest bootstrap and layout execution | Partial | Partial | Partial | Partial | Compliant |
| Phases 6-9 role/share/data path config | Compliant | Partial | Partial | Partial | Partial |
| Phases 10-11 validation/hardening extras | Compliant | Partial | Partial | Partial | Partial |
| Cross-phase variable contract consistency | Partial | Partial | Non-compliant | Non-compliant | Partial |

Notes:

- Terraform is strong in Phases 1-2 and relies on downstream guest tooling for later phases.
- Bicep/ARM are primarily Phases 1-2 today despite broader parameter surfaces.
- Ansible is strongest in guest phases but needs Azure NIC/static-IP and FSRM parity improvements.

---

## Variable-Driven Decision Tree Contract (Target)

All tools must evaluate the same Phase 0 contract before any phase execution.

Required Phase 0 inputs:

- deployment.method (tool chain entry point)
- deployment.host_layout
- deployment.guest_layout (target rename from option_a/option_b)
- deployment.host_resiliency
- deployment.guest_resiliency
- deployment.cloud_cache_enabled
- deployment.storage_path_ids (map, canonical)
- deployment.storage_path_id (optional backward-compat alias)

Required Phase 0 outputs:

- Selected execution path: Azure-only, Guest-only, or End-to-End.
- Declared phase ownership map for the selected method.
- Hard validation errors for unsupported combinations.

Required behavior:

1. No Option A field resolution when guest_layout selects triple layout path.
2. No silent fallback from unsupported singular storage path in tools that only support map input.
3. Any parameter exposed in Bicep/ARM must either:
   a) alter Azure behavior in Phases 1-2, or
   b) be explicitly marked pass-through metadata for downstream guest tooling.

---

## Naming Migration Plan: Option A/B to Single/Triple

Recommended naming model:

- Option A -> single-volume layout
- Option B -> triple-volume layout

Migration strategy:

1. Introduce new canonical field values:
   - deployment.guest_layout: single or triple
2. Preserve backward compatibility for one release train:
   - option_a maps to single
   - option_b maps to triple
3. Emit warning on legacy values at Phase 0 validation.
4. Update docs, examples, and schema together.
5. Remove legacy aliases in next major release.

Why this is better:

- Names describe the actual storage topology.
- Easier to align across PowerShell/Terraform/Bicep/ARM/Ansible.
- Matches AVD-style explicit architecture labeling and reduces interpretation errors.

---

## Tool-by-Tool Remediation Plan

### PowerShell

1. Fix guest layout branch gating so triple path does not resolve single-only fields.
2. Add explicit Phase 0 validation function that emits phase ownership.
3. Maintain singular storage path alias while preferring canonical map.

### Terraform

1. Enforce canonical map input and emit clear error if only singular path provided.
2. Generate explicit phase ownership metadata in inventory output.
3. Ensure guest_layout naming migration is fully reflected in tfvars examples.

### Bicep

1. Remove or annotate non-functional phase-control parameters.
2. Implement static NIC private IP assignment if vmIps is advertised.
3. Update wrapper script to current repo path and config shape.

### ARM

1. Regenerate from corrected Bicep once parameter semantics are fixed.
2. Keep parameter file examples aligned with canonical guest_layout names.

### Ansible

1. Add static IP support in deploy-azure-resources playbook when vm_ips is supplied.
2. Add FSRM parity tasks in configure-sofs-cluster.
3. Add Phase 0 preflight role to normalize legacy option names.

---

## Documentation Changes Needed

1. Make Phase 0 decision tree the first-class entry section in deployment docs.
2. Replace Option A/B narrative with single/triple layout terminology.
3. Publish a phase ownership table per tool to prevent over-claiming.
4. Mark Bicep/ARM as Azure-plane focused unless guest phases are actually implemented.
5. Correct stale script paths and outdated anti-affinity statements.

---

## Pre-Start Work Item Plan (Before Implementation)

This is the issue-management plan to run before code changes begin.

### 1) Reopen Epic and Child Issues (SOFS)

Reopen the SOFS parent epic and all epic child issues so remediation is tracked in existing lineage:

- Reopen epic: `azurelocal-sofs-fslogix#59`
- Reopen child issues: `#60` through `#69`

Reason:

- Current audit evidence shows material parity and contract gaps remain, so previous closure state no longer matches implementation reality.

### 2) Rewrite Acceptance Criteria on Reopened Issues

Each reopened SOFS issue should include these mandatory criteria:

1. Phase 0 decision-tree enforcement
2. Single/triple naming migration behavior
3. Per-tool parity expectations
4. Evidence-based validation criteria
5. Cross-repo dependency alignment

Required evidence format on each issue:

- "As-is" behavior summary (current observed state)
- "Target" behavior summary (post-fix expected state)
- Verification steps with command/file evidence
- Pass/fail outcome table by tool and phase group

### 3) Cross-Repo Dependency Links (Prevent Drift)

For SOFS issue updates, link dependencies to:

- `azurelocal-avd#8` (active AVD epic)
- `azurelocal-avd#36` (topology terminology alignment)
- `azurelocal-toolkit#4` (master variable registry)
- `azurelocal-toolkit#5` (IaC maturity tracking)

Dependency policy:

- SOFS issue cannot be marked complete if canonical variable names or terminology mappings are unresolved in linked AVD/Toolkit work.

### 4) Epic Hygiene

Handle duplicate/legacy AVD epic tracking:

- Treat `azurelocal-avd#8` as the active epic.
- Mark `azurelocal-avd#7` as outdated/duplicate of `#8` (close with explicit duplicate note if still open).

### 5) Re-Completion Gate (Do Not Re-Close Early)

Reopened SOFS issues should only move to Done when all are true:

1. Tool behavior matches documented phase ownership
2. Decision-tree variables are validated at Phase 0
3. Naming migration support (single/triple + legacy alias handling) is implemented and documented
4. Validation evidence is attached and reproducible
5. Cross-repo dependency checks are satisfied

---

## Execution Order (Practical)

1. Reopen `#59` and `#60`-`#69`; update each with refreshed acceptance criteria and dependency links.
2. Normalize epic hierarchy (`avd#8` active, `avd#7` marked outdated duplicate).
3. Fix PowerShell triple-layout gating bug.
4. Finalize naming migration in schema and variable docs.
5. Align Terraform and Ansible Phase 0 normalization and validation.
6. Correct Bicep/ARM parameter semantics and wrapper compatibility.
7. Update docs with the phase ownership matrix and migration notes.
8. Run evidence-based validation and only then close issues.

---

## Final Verdict

Current state is deployable but not yet phase-contract consistent across all toolchains.

Best path forward:

- Treat Phase 0 as mandatory, variable-driven control.
- Standardize guest layout naming to single/triple.
- Enforce explicit phase ownership and eliminate ambiguous parameter behavior.

This will align SOFS with the same clear plane-oriented architecture language used in the AVD repository and make method selection reliable at scale.

