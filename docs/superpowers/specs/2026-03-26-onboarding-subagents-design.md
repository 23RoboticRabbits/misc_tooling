# Onboarding Subagents Design

## Objective

Design a fully autonomous subagent suite that helps an engineering director onboard into an unfamiliar codebase faster, while preserving enough rigor to surface critical architectural risks. The first version prioritizes artifact generation over interactive Q&A and targets one repository at a time.

## Goals

- Reduce time to initial repository comprehension.
- Produce a small set of linked artifacts that support executive-level technical review.
- Surface architectural risks even when the codebase is large, polyglot, or only partially verifiable.
- Support both coordinated onboarding workflows and standalone specialist-agent usage.

## Non-Goals

- Cross-repository analysis in v1.
- Automated code modification or remediation.
- Interactive conversational follow-up as the primary interface.
- PR-level review workflows tied to active development.

## Users

Primary user: engineering director.

The output should assume a technically strong reader who wants dense, concise, high-signal summaries rather than generalized onboarding documentation.

## Scope

The system accepts either:

- A local checked-out repository.
- A remote repository URL.

Both inputs are normalized into the same single-repository analysis pipeline. The system is designed so that multi-repo analysis can be added later by linking multiple repo-level outputs, but that is explicitly out of scope for v1.

For local repositories, Intake must capture the current commit SHA when available, detect whether the worktree is clean or dirty, and record any uncommitted changes as part of the run metadata. Dirty worktrees must also include a deterministic change fingerprint derived from the changed file paths and their current content hashes so downstream artifacts can be traced back to the analyzed local state. If the repository is not backed by git, Intake must record that the analysis is path-based and non-reproducible by commit identity.

For remote repositories, v1 should analyze a pinned snapshot rather than a moving target. Intake must resolve the user-supplied repository URL to a concrete commit before downstream analysis begins. The resolved commit SHA becomes part of the repo context package and must be referenced in the final artifacts so results are reproducible.

Remote intake must also record whether the target requires authentication and whether submodules or Git LFS objects are present. If the system cannot obtain required credentials or fully materialize repository content, it should continue only when the missing material is non-blocking and must mark the affected areas as partially analyzed.

Blocking conditions for remote intake are:

- The repository root cannot be materialized.
- The pinned target commit cannot be resolved.
- A missing submodule or LFS object is required to analyze a top-level service, package, or entrypoint discovered during Intake.

Non-blocking missing material may be skipped only when it is outside those core analysis surfaces. The affected subsystem paths must be listed explicitly in the repo context package and propagated into downstream unknowns and confidence fields.

For this decision, Intake determines `top-level` from material that is available without traversing the missing content: repository-root manifests, workspace configuration, checked-in docs, root-level service directories, and declared entrypoints visible in accessible config files. If requiredness cannot be determined from those surfaces, the missing material must be treated as blocking rather than assumed optional.

Partial materialization must be represented per analysis surface, not only as a flat gap list. Each affected subsystem, package, or entrypoint must carry a materialization status of `fully-materialized`, `partially-materialized`, `skipped-non-blocking`, or `blocking-missing`. Downstream agents must preserve those statuses and must not treat `partially-materialized` or `skipped-non-blocking` surfaces as fully verified.

## Recommended Approach

Use a pipeline-first system with specialist agents coordinated by an orchestrator.

This approach is preferred over a single generalist agent because very large polyglot repositories require decomposition to avoid shallow summaries and missed risks. It is preferred over a graph-first platform because the first version should optimize for usable onboarding outputs instead of heavy analysis infrastructure.

## Operating Modes

### Coordinated Mode

An orchestrator runs specialist agents in a fixed sequence, passing structured artifacts between them and assembling the final onboarding package.

### Standalone Mode

Each specialist agent can also be run independently against a repository when only one function is needed, such as structure discovery, architecture synthesis, or risk review.

Standalone mode still uses the shared repo context package, but each agent must declare a minimum required input contract and a guaranteed output artifact:

- Repo Intake requires a local path or remote URL and emits the initial inventory artifact plus the normalized repo context package.
- Structure Discovery requires the repo context package and the initial inventory artifact, and emits the repository map artifact.
- Execution and Validation requires the repo context package and emits an execution evidence artifact that records runnable commands, outcomes, and verification gaps.
- Architecture Synthesis requires the repo context package plus a repository map artifact and an execution evidence artifact, and emits the architecture brief artifact plus the architecture model artifact.
- Risk Review requires the repo context package plus a repository map artifact, an execution evidence artifact, and an architecture model artifact, and emits the risk register artifact. Human-readable Markdown artifacts (`03-architecture-brief.md` and others) are outputs only and are not declared inputs to any downstream agent; all cross-artifact reasoning must resolve through the JSON artifacts.

If a standalone invocation is missing required upstream artifacts, the agent must fail closed with an explicit missing-input report rather than silently inferring unavailable context. If a standalone invocation receives upstream artifacts whose `run_id` values differ from each other, or whose `run_id` differs from the caller-supplied `run_id`, the agent must emit a `pipeline-error` artifact with `error_type: incompatible-input` and halt.

## System Shape

The core system principle is a shared repository context package rather than ephemeral conversation state. Each agent reads prior artifacts and writes structured outputs that become the input boundary for downstream analysis.

This allows:

- Progressively reducing a large codebase into a smaller and more reliable representation.
- Preserving uncertainty and evidence between stages.
- Reusing specialist agents outside the full pipeline.

## Core Data Contracts

All machine-readable handoff artifacts should be serialized as JSON. Human-readable deliverables remain Markdown. Each JSON artifact must include a schema version so standalone and coordinated runs can validate compatibility.

Schema versioning uses a `major.minor` format (e.g., `"1.0"`). The current version for all v1 artifacts is `"1.0"`. A major version increment indicates a breaking change; a minor version increment indicates a backward-compatible addition. Each agent must declare the schema versions it can consume and the schema version it emits. An agent receiving an artifact whose major version differs from its declared compatible major must fail closed with a structured `schema-incompatible` error (see Pipeline Error Artifact). A minor version mismatch must proceed with a logged warning recorded in the receiving agent's `*_unknowns` list.

### Repo Context Package

The repo context package is the canonical shared handoff object. Required fields:

- `schema_version`
- `run_id`
- `input_type` as `local` or `remote`
- `repo_locator` as local path or remote URL
- `source_state_id`
- `non_reproducible_source_state`
- `resolved_commit_sha` when available — always records the git commit SHA of the analyzed ref regardless of worktree state; for `local-dirty-commit` cases it is identical to `source_state_id.primary_id` while `source_state_id.secondary_id` carries the change fingerprint
- `worktree_state` as `clean`, `dirty`, or `unknown`
- `uncommitted_change_summary` when `worktree_state` is `dirty`
- `local_change_fingerprint` when `worktree_state` is `dirty`
- `worktree_state_unknown_reason` when `worktree_state` is `unknown`
- `auth_requirement` as `none`, `read-required`, or `unknown`
- `submodule_status`
- `lfs_status`
- `analysis_scope` listing included root paths or packages
- `analysis_surfaces` with per-surface materialization status (full object schema defined in field constraints below)
- `materialization_gaps` listing unresolved submodules, LFS objects, or inaccessible paths
- `detected_languages`
- `detected_build_systems`
- `detected_package_managers`
- `top_level_entrypoints`
- `top_level_services_or_packages`

Field constraints:

- `submodule_status` must use the shared materialization vocabulary: `none`, `fully-materialized`, `partially-materialized`, `skipped-non-blocking`, `blocking-missing`, or `unknown`.
- `lfs_status` must use the shared materialization vocabulary: `none`, `fully-materialized`, `partially-materialized`, `skipped-non-blocking`, `blocking-missing`, or `unknown`.
- `source_state_id` must be an object with `identity_type`, `primary_id`, and optional `secondary_id`.
- `non_reproducible_source_state` must be `true` when `identity_type` is `path-snapshot`, `local-dirty-commit`, or `local-unknown-commit`, and `false` otherwise. Any artifact where `non_reproducible_source_state` and `identity_type` are inconsistent must be rejected by the receiving agent as a malformed artifact.
- `worktree_state` of `unknown` occurs when the git status command fails, git is not available, or permissions prevent worktree inspection. When `worktree_state` is `unknown`, `identity_type` must be `local-unknown-commit` and `non_reproducible_source_state` must be `true`. Downstream artifacts must treat `local-unknown-commit` as equivalent to `local-dirty-commit` for confidence purposes. `local-unknown-commit` is compatible with no other `identity_type` for cross-artifact matching. `worktree_state_unknown_reason` must be omitted (not present as null or empty string) when `worktree_state` is `clean` or `dirty`; similarly, `uncommitted_change_summary` and `local_change_fingerprint` must be omitted when `worktree_state` is not `dirty`.
- `analysis_surfaces` must be a list of objects with `surface_id`, `paths`, `surface_type`, `materialization_status`, `evidence_refs`, and `confidence`. The `confidence` value represents the confidence that the surface was correctly identified and scoped, not the confidence of downstream analytical claims derived from it. `surface_id` must be a string unique within the run, assigned by Repo Intake and preserved unchanged by all downstream agents; downstream agents must not re-assign or transform `surface_id` values from upstream artifacts. Recommended naming convention: `svc-<slug>` for services, `pkg-<slug>` for packages (where `<slug>` is a lowercase alphanumeric identifier derived from the surface name), to produce human-inspectable IDs in standalone runs.
- `surface_type` must be one of `service`, `package`, `entrypoint`, `module-root`, `config-surface`, or `doc-surface`. Note: hotspots and ownership zones are not `analysis_surfaces` entries; they are entries in the repository map artifact's `hotspots` list and boundary hypotheses respectively. `analysis_surfaces` covers only materializable code surfaces, not analytical overlays.
- `detected_languages`, `detected_build_systems`, and `detected_package_managers` must be lists of objects with `value`, `evidence_refs`, and `confidence`.
- `top_level_entrypoints` and `top_level_services_or_packages` must be lists of objects with `id`, `paths`, `reason`, `materialization_status`, `evidence_refs`, and `confidence`.
- `materialization_gaps` must be a list of objects with `id`, `paths`, `gap_type`, `affected_surface_ids`, `evidence_refs`, and `confidence`. The `confidence` on a gap entry represents the confidence that the identified paths are genuinely inaccessible, not merely transiently unavailable. Valid `gap_type` values: `missing-submodule`, `missing-lfs-object`, `inaccessible-path`, `auth-blocked`, `other`.
- submodule-backed analysis surfaces must record `secondary_id` values for the resolved submodule commit when materialized.
- LFS-backed analysis surfaces must record `secondary_id` values for the resolved object identifier when materialized.

### Initial Inventory Artifact

The initial inventory artifact captures the raw intake findings. Required fields:

- `schema_version`
- `run_id`
- `repo_locator`
- `source_state_id`
- `non_reproducible_source_state`
- `discovered_manifests`
- `discovered_configs`
- `discovered_docs`
- `repo_roots`
- `candidate_test_entrypoints`
- `candidate_runtime_entrypoints`
- `inventory_unknowns`

Note: `worktree_state`, `uncommitted_change_summary`, `local_change_fingerprint`, and `worktree_state_unknown_reason` are intake-time observations carried only in `repo-context.json`, not in `initial-inventory.json`. Consumers that require worktree state information must read `repo-context.json` rather than the inventory artifact.

`discovered_manifests`, `discovered_configs`, and `discovered_docs` must be lists of objects with `id`, `path`, `kind`, `kind_detail` (optional free-text for unrecognized types), `evidence_refs`, and `confidence`.

Valid `kind` values for `discovered_manifests`: `npm`, `cargo`, `gradle`, `maven`, `go-module`, `pyproject`, `gemspec`, `composer`, `bazel`, `cmake`, `makefile`, `other`.
Valid `kind` values for `discovered_configs`: `ci-pipeline`, `container`, `infrastructure-as-code`, `env-config`, `service-config`, `other`.
Valid `kind` values for `discovered_docs`: `readme`, `architecture-doc`, `api-doc`, `changelog`, `contributing-guide`, `other`.

`candidate_test_entrypoints` and `candidate_runtime_entrypoints` must be lists of objects with `id`, `command_or_path`, `evidence_refs`, `confidence`, and optionally `entrypoint_type`. Valid `entrypoint_type` values for test entrypoints: `unit`, `integration`, `e2e`, `smoke`, `full-suite`, `other`. Valid `entrypoint_type` values for runtime entrypoints: `server`, `cli`, `batch`, `worker`, `other`. This field supports the Execution and Validation agent's narrowest-first selection policy.

`repo_roots` must be a list of objects with `path` (string), `root_type` (one of `git-root`, `workspace-root`, `submodule-root`, `nested-package-root`), `materialization_status`, `evidence_refs`, `confidence`, and optionally `surface_id` (referencing the corresponding `analysis_surfaces` entry when one exists). `analysis_scope` in the repo context package lists paths included in analysis; `repo_roots` describes structural roots discovered during intake regardless of whether they were analyzed. Any `repo_roots` entry that corresponds to an `analysis_surfaces` entry must populate `surface_id`, regardless of `root_type`. The `surface_id` value in `repo_roots` must be the exact same string as the `surface_id` in the corresponding `analysis_surfaces` entry. Both are populated in the same Intake pass: Intake generates the `surface_id` once and writes it into both locations simultaneously. Specifically, nested package roots that are individually surfaced as `top_level_services_or_packages` entries must have a corresponding `analysis_surfaces` entry and a populated `surface_id`. Nested packages below that granularity level may be omitted from `analysis_surfaces` but must be noted in `inventory_unknowns` if their omission affects coverage assessment.

### Repository Map Artifact

The repository map artifact captures structural conclusions. Required fields:

- `schema_version`
- `run_id`
- `repo_locator`
- `source_state_id`
- `non_reproducible_source_state`
- `subsystems`
- `dependency_edges`
- `boundary_hypotheses`
- `hotspots`
- `structure_unknowns`

Each subsystem entry must include `id`, `name`, `paths`, `role`, `materialization_status`, `evidence_refs`, and `confidence`. Each dependency edge, boundary hypothesis, and hotspot entry must also include `confidence`.
Each dependency edge must include `id`, `from`, `to`, `edge_type`, `evidence_refs`, and `confidence`. Valid `edge_type` values: `runtime-dependency`, `build-dependency`, `test-dependency`, `import`, `configuration-reference`, `submodule-reference`, `other`.
Each boundary hypothesis must include `id`, `scope`, `statement`, `evidence_refs`, and `confidence`. `scope` must be a list of subsystem `id` values from `subsystems`, referencing the subsystems that participate in or are affected by the hypothesized boundary. Note: subsystem entries use `name` as a human-readable label but `id` as the stable identifier for cross-artifact referencing; `scope` must use `id`, not `name`. An empty `scope` list is permitted and means the hypothesis applies to the repository as a whole (e.g., "no clear domain boundaries exist"); agents must not infer missing subsystem relationships from an empty scope.
Each hotspot must include `id`, `paths`, `reason`, `evidence_refs`, and `confidence`.

### Execution Evidence Artifact

The execution evidence artifact is the machine-readable output of the Execution and Validation agent. Required fields:

- `schema_version`
- `run_id`
- `repo_locator`
- `source_state_id`
- `non_reproducible_source_state`
- `commands_attempted`
- `commands_skipped`
- `execution_results`
- `command_timings`
- `verified_surfaces`
- `unverified_surfaces`
- `verification_coverage`
- `execution_unknowns`

Each execution result entry and each verified or unverified surface entry must include `confidence`.
Each entry in `verified_surfaces` and `unverified_surfaces` must include `surface_id` (referencing a `surface_id` from `analysis_surfaces`), `evidence_refs` (referencing `command_id` values from `commands_attempted` or result IDs from `execution_results`), and `confidence`. The `covered_surfaces`, `partially_covered_surfaces`, and `uncovered_surfaces` fields in `verification_coverage` must be lists of `surface_id` strings referencing entries from `analysis_surfaces`. These three lists must be disjoint, and their union must equal the complete set of `surface_id` values present in `analysis_surfaces` (every analysis surface must appear in exactly one of the three lists). Surfaces with direct execution evidence map to `covered_surfaces`; surfaces with partial or indirect evidence map to `partially_covered_surfaces`; surfaces with no execution evidence map to `uncovered_surfaces`.
Each command in `commands_attempted` must include `id`, `command`, `origin`, `confidence`, and optionally `source_entrypoint_id` (string referencing the `id` of the originating `candidate_test_entrypoints` or `candidate_runtime_entrypoints` entry from the initial inventory artifact, when the command derives from a discovered entrypoint). Valid `origin` values: `repo-declared-test`, `repo-declared-build`, `platform-allowlist`, `orchestrator-injected`, `unclassified`. When a command qualifies under multiple categories, `origin` must reflect the highest-priority matching category: `repo-declared-test` > `repo-declared-build` > `platform-allowlist` > `orchestrator-injected` > `unclassified`.
Each command in `commands_skipped` must include `id`, `command`, `origin`, `confidence`, and `skip_reason`. Valid `skip_reason` values: `network-access-required`, `outside-allowlist`, `aggregate-budget-exhausted`, `interactive-input-required`, `privileged-access-required`, `other`. Commands with `skip_reason: outside-allowlist` that cannot be attributed to a source category must use `origin: unclassified`.
Each execution result entry must include `id` (string, unique within the artifact), `command_id`, `exit_status`, `outcome`, `evidence_refs`, and `confidence`. Valid `outcome` values: `success`, `failure`, `timed-out`, `skipped`, `error` (for infrastructure or sandbox failures distinct from command-level failures). Each invocation of the Execution and Validation agent produces exactly one `execution-evidence.json`; partial outputs due to budget exhaustion are recorded within that single artifact. `id` uniqueness is scoped to that single artifact file; if the orchestrator retries a failed execution stage, the new invocation begins a new `run_id` session (or follows the incompatible-input rules if chaining into an existing run).
`verification_coverage` must be an object with `covered_surfaces`, `partially_covered_surfaces`, `uncovered_surfaces`, `coverage_notes`, `evidence_refs` (referencing command IDs or execution result IDs that support the coverage assessment), and `confidence`.
`command_timings` must be a list of objects with `command_id` (referencing an ID in `commands_attempted`), `wall_clock_ms` (integer milliseconds), `exit_time_iso8601` (ISO 8601 timestamp — for forcibly terminated commands, records the timestamp of the last signal sent, typically SIGKILL), `timed_out` (boolean), and `forcibly_killed` (boolean, defaults to `false`, set to `true` when the process was terminated by SIGKILL rather than exiting normally).

### Architecture Model Artifact

The architecture model artifact is the machine-readable counterpart to the architecture brief. Required fields:

- `schema_version`
- `run_id`
- `repo_locator`
- `source_state_id`
- `non_reproducible_source_state`
- `components`
- `interactions`
- `layering_hypotheses`
- `architecture_unknowns`

Each component, interaction, and layering hypothesis entry must include `confidence`.
Each layering hypothesis must include `id`, `statement` (string description of the hypothesized layering), `scope` (list of qualified component or subsystem identifiers the hypothesis applies to), `evidence_refs`, and `confidence`. Optionally, it may include `contradicted_by` (list of evidence IDs or execution result IDs where the layering was not observed), to support divergence analysis. Each entry in `scope` must use a qualified format: `component:<id>` to reference a component from `components` (in this artifact), or `subsystem:<id>` to reference a subsystem from the repository map artifact's `subsystems` list. Unqualified IDs are not permitted in `scope`.
Each component must include `id`, `name`, `paths`, `role`, `evidence_refs`, `confidence`, and optionally `source_subsystem_ids` (list of subsystem IDs from the repository map artifact).
Each interaction must include `id`, `from`, `to`, `interaction_type`, `evidence_refs`, `confidence`, and optionally `source_dependency_edge_ids` (list of dependency edge IDs from the repository map artifact). Valid `interaction_type` values: `synchronous-call`, `asynchronous-message`, `shared-data`, `configuration-dependency`, `import`, `submodule-reference`, `other`. The `source_dependency_edge_ids` field provides a provenance trace to the repository map edges that motivated the interaction; it does not imply type correspondence between `interaction_type` and `edge_type` values, which are independently scoped vocabularies.

### Risk Register Artifact

The risk register artifact is the machine-readable counterpart to the human-readable risk register. Required fields:

- `schema_version`
- `run_id`
- `repo_locator`
- `source_state_id`
- `non_reproducible_source_state`
- `risks`
- `risk_unknowns`

Each risk entry must include `severity`, `evidence_refs`, `affected_surfaces`, `confidence`, `id`, `title`, and `statement`. `affected_surfaces` must be a list of objects with `surface_id` (referencing a `surface_id` from `analysis_surfaces`) and optionally `display_name` (human-readable label). Each risk entry may optionally include `source_hotspot_ids` (list of hotspot IDs from the repository map artifact) and `source_component_ids` (list of component IDs from the architecture model artifact) to link risks back to the structural and architectural findings that motivated them.

### Architecture Inputs

Architecture Synthesis in standalone mode requires a valid repository map artifact. The earlier `equivalent structural inventory` fallback is intentionally removed to keep the contract explicit and machine-validatable.

### Unknown Entry Schema

All `*_unknowns` fields in every artifact must be lists of objects conforming to this shared schema:

- `id`: string, unique within the artifact
- `description`: string, human-readable explanation of what is unknown
- `unknown_type`: one of `missing-evidence`, `ambiguous-signal`, `unresolvable-dependency`, `incomplete-coverage`, `blocked-access`
- `unknown_type_detail`: optional string, free-text additional qualification of the `unknown_type`, analogous to `kind_detail` on manifest/config/doc entries; used when the agent needs to further qualify a known type or when the receiving system does not recognize the `unknown_type` value
- `affected_surface_ids`: list of strings referencing `surface_id` values in `analysis_surfaces`, optional
- `confidence`: using the four-level confidence scale
- `propagated_from`: list of artifact-scoped unknown references, optional, used when an unknown is inherited from an upstream artifact. Each reference must use the format `<artifact_name>:<unknown_id>` (e.g., `repo-map:unk-003`) to avoid ambiguity across artifacts whose unknown `id` values are only locally unique. Cycles are prohibited; implementations must validate that `propagated_from` chains are acyclic. Maximum chain depth is 10. When a chain depth limit is reached and propagation would logically continue, the propagating agent must truncate `propagated_from` to the 10 most recent entries and must set `unknown_type_detail` to a note recording the truncation and the reference of the oldest dropped ancestor (e.g., `"propagated_from truncated at depth 10; oldest dropped ancestor: initial-inventory:unk-001"`).

### Evidence Reference Schema

`evidence_refs` appears on nearly every structured object in every artifact. It must be a list of objects with the following fields:

- `ref_type`: one of `file-path`, `command-id`, `execution-result-id`, `artifact-field`, `external-url`
- `ref_target`: the actual reference value (file path string, command `id`, execution result `id`, RFC 6901 JSON Pointer with artifact filename prefix for `artifact-field` references, or URL). For `ref_type: artifact-field`, `ref_target` must use the format `<artifact-filename>#<json-pointer>` (e.g., `architecture-model.json#/components/0/role`), where `<artifact-filename>` must match one of the canonical artifact filenames defined in this spec.
- `line_range`: optional object with `start` and `end` line numbers, applicable only when `ref_type` is `file-path`

Per-field descriptions that say "referencing X" constrain the permitted `ref_type` and `ref_target` values for that field's evidence; they do not override this schema.

### Source Identity Summary Template

All Markdown artifacts require a "source identity summary" section. This section must render at minimum: `repo_locator`, `identity_type`, `primary_id`, and `non_reproducible_source_state`. When `secondary_id` is present, it must also be rendered. When `non_reproducible_source_state` is `true`, the section must include a visible warning line indicating that analysis results may not be fully reproducible.

### Confidence Field Contract

Any JSON artifact that describes claims about structure, architecture, execution coverage, or risk must store confidence per claim using a `confidence` field attached directly to the claim-bearing object. The `confidence` on `analysis_surfaces` entries (representing surface identification confidence) does not participate in confidence ceiling calculations for downstream analytical claims; only the confidence fields on `subsystems`, `dependency_edges`, `components`, `interactions`, `boundary_hypotheses`, and `layering_hypotheses` are used in ceiling rule calculations. Markdown outputs may summarize confidence in prose, but they should derive from the structured values rather than inventing new labels.

### Run ID Contract

`run_id` identifies the analysis session, not the source state. In coordinated mode, the orchestrator generates a UUID v4 at pipeline start and passes it to all specialist agents; all artifacts from that run share the same `run_id`. In standalone mode, when no upstream artifacts are provided, the agent auto-generates a UUID v4 `run_id` and includes it in all emitted artifacts. Callers chaining standalone agents must read the `run_id` from the first agent's emitted artifact (available as the top-level `run_id` field) and supply it explicitly to subsequent standalone invocations. When upstream artifacts are provided, a caller-supplied `run_id` is required and must match the `run_id` embedded in all supplied artifacts; a missing caller-supplied `run_id` when upstream artifacts are present is treated as an error. When a caller-supplied `run_id` is provided and validated, the agent must embed that exact `run_id` in all emitted output artifacts, including any `pipeline-error.json` artifacts emitted during that invocation. `run_id` must not be reused across distinct analysis sessions.

### Artifact Identity Contract

Every JSON artifact must include `run_id`, `repo_locator`, `source_state_id`, and `non_reproducible_source_state`.

`source_state_id` is a structured object:

- `identity_type`: one of `remote-commit`, `local-clean-commit`, `local-dirty-commit`, `local-unknown-commit`, `path-snapshot`, or `unresolved` (permitted only in `pipeline-error.json` artifacts when the error occurs before source state is resolved; `non_reproducible_source_state` must be `true` for this value)
- `primary_id`: the primary stable identifier for the source state
- `secondary_id`: optional secondary identifier used when the primary identifier alone is insufficient

Construction rules:

- pinned remote runs: `identity_type=remote-commit`, `primary_id=resolved_commit_sha`, `secondary_id` omitted, `non_reproducible_source_state=false`
- clean local git worktrees: `identity_type=local-clean-commit`, `primary_id=resolved_commit_sha`, `secondary_id` omitted, `non_reproducible_source_state=false`
- dirty local git worktrees: `identity_type=local-dirty-commit`, `primary_id=resolved_commit_sha`, `secondary_id=local_change_fingerprint`, `non_reproducible_source_state=true`. The base commit is recoverable, but the uncommitted changes captured only in the `local_change_fingerprint` may not be fully reproducible.
- non-git inputs: `identity_type=path-snapshot`, `primary_id` is a deterministic path-based marker (defined as the SHA-256 hex digest of the sorted, newline-delimited list of all regular file paths relative to the repository root), `secondary_id` omitted, `non_reproducible_source_state=true`
- git-backed repos where worktree status cannot be determined: `identity_type=local-unknown-commit`, `primary_id` is the last resolvable commit SHA, or the same deterministic path-based marker format defined for `path-snapshot` if the commit cannot be resolved, `secondary_id` omitted, `non_reproducible_source_state=true`

Downstream agents must copy `source_state_id` verbatim from the repo context package rather than independently deriving it. Only Repo Intake may construct `source_state_id`; all other agents must propagate the value they received without modification.

Downstream agents must reject upstream artifacts whose identity fields do not match the active repo context package. A match requires: `run_id` must be identical across all artifacts in a session; `source_state_id.primary_id` must be identical; when `identity_type` is `local-dirty-commit`, `source_state_id.secondary_id` must also be identical — a `secondary_id` mismatch must cause the receiving agent to emit a `pipeline-error` with `error_type: incompatible-input` and halt; `source_state_id.identity_type` must be identical with one permitted exception — `remote-commit` and `local-clean-commit` are compatible when their `primary_id` values are the same commit SHA, in which case the agent must log a warning rather than reject. Any other type mismatch (including any combination involving `local-dirty-commit`, `local-unknown-commit`, or `path-snapshot`) is incompatible and must cause the receiving agent to emit a `pipeline-error` artifact with `error_type: incompatible-input` and halt.

## Agent Set

### 1. Repo Intake Agent

Responsibilities:

- Normalize local path or remote URL input.
- Detect languages, package managers, build systems, repo layout, and package boundaries.
- Discover key docs, configs, manifests, service roots, and entry points.
- Create the initial inventory artifact.
- Capture `source_state_id` once at the beginning of the intake run and use that single captured value for all artifacts emitted in the same invocation. If the worktree state changes after initial capture (e.g., the developer modifies files mid-run), Intake must record the originally captured state rather than refreshing it mid-run.

### 2. Structure Discovery Agent

Responsibilities:

- Build the repository map.
- Identify major directories, modules, services, seams, and dependency surfaces.
- Detect likely ownership and subsystem boundaries.
- Flag hotspots that require deeper scrutiny later in the pipeline.

### 3. Execution and Validation Agent

Responsibilities:

- Run available tests and safe discovery commands.
- Capture which parts of the system can actually be exercised.
- Validate or challenge structure assumptions using observable behavior.
- Record failures, missing tooling, and unverified areas.

Execution policy:

- Allowed commands are limited to read-oriented discovery, repository-declared test entrypoints, and repository-declared build verification entrypoints.
- Commands must run with bounded timeouts and captured exit status. Default timeouts: 60 seconds for read-only inspection commands; 300 seconds for repository-declared test or build entrypoints. An aggregate execution budget of 1800 seconds applies per agent invocation. On per-command timeout or when the aggregate budget is exhausted while a command is executing, the agent must send SIGTERM followed by SIGKILL after a 10-second grace period. In-flight commands terminated by budget exhaustion must be recorded in `commands_attempted` with `outcome: timed-out` and `timed_out: true` in `command_timings`. All commands not yet started when the budget is exhausted must be recorded in `commands_skipped` with `skip_reason: aggregate-budget-exhausted`. Default timeouts are configurable by the orchestrator via the execution policy object.
- The agent must not modify repository contents.
- The agent must not access the network. Repository-declared test or build entrypoints that are determined to require network access (detectable from manifest-declared install steps or tool behavior patterns) must be recorded in `commands_skipped` with `skip_reason: network-access-required` rather than attempted.
- Commands that require elevated privileges must be recorded in `commands_skipped` with `skip_reason: privileged-access-required`. Elevated privilege is detectable from: invocations of `sudo`, `su`, or privilege-escalation tools in the command string; setuid binary targets; or repository documentation (Makefile targets, README instructions, or checked-in developer guides) that indicate the command requires elevated access.
- If a command falls outside the allowlist or requires broader privileges, the agent must record the gap instead of improvising.
- All command execution must run in a sandbox: a container or chroot with a read-only bind mount of the repository, no filesystem write access outside a designated ephemeral output directory, a non-root user, no network access, and hard CPU and memory resource limits in addition to the timeout policy. The platform must enforce these constraints; the agent must not rely solely on its own policy choices for isolation.

The source of truth for permitted commands is:

- First, repository-declared test entrypoints discovered from manifests, task runners, or documented developer workflows.
- Second, repository-declared build verification entrypoints discovered from manifests, task runners, or documented developer workflows.
- Third, a fixed platform allowlist of read-oriented inspection commands.

Repository-declared test or build verification entrypoints may be executed only when they match detected tooling, do not require interactive input, and are documented or discoverable from checked-in project metadata. If multiple candidate commands exist, the agent should prefer the narrowest command that exercises a top-level package or service before broader suite commands.

The fixed read-only inspection allowlist is limited to:

- file and directory listing
- file content reads
- manifest and lockfile inspection
- repository metadata inspection such as branch, commit, and worktree status
- symbol, path, and text search
- dependency graph extraction using non-mutating built-in tooling

Any repo-specific helper script outside these categories must be treated as a test or build entrypoint, not as an implicit discovery command.

### 4. Architecture Synthesis Agent

Responsibilities:

- Build the inferred architecture model from structure and execution evidence.
- Summarize major components, abstractions, interactions, and boundaries.
- Note where the code suggests a different architecture from the intended one.
- Propagate upstream `*_unknowns` entries into `architecture_unknowns` with a populated `propagated_from` field unless the unknown can be positively determined to be irrelevant to the architecture model's claims. An unknown must be propagated if any of the following apply: its `affected_surface_ids` overlap with surfaces used in the architecture model; its `unknown_type` is `incomplete-coverage`, `blocked-access`, or `ambiguous-signal`; or its description references a subsystem, component, or boundary element used in the architecture model.

Confidence ceiling rules:

- If the execution evidence artifact is absent (because the Execution and Validation stage was skipped due to a recoverable error), all architecture model claims must be capped at `weak-inference` confidence.
- If the execution evidence artifact is present but `execution_results` is empty and `verified_surfaces` is empty (e.g., all commands timed out or were skipped), all architecture model claims must also be capped at `weak-inference` confidence.
- If all `boundary_hypotheses` in the repository map artifact are at `weak-inference` or `unknown` confidence, all architecture model claims must be capped at `weak-inference`. More generally, the confidence of a downstream claim may not exceed the maximum confidence of the upstream evidence it is derived from unless new independent corroborating evidence is added in the current stage.
- If `verification_coverage` indicates that the majority of analysis surfaces are uncovered — defined as `len(uncovered_surfaces) + len(partially_covered_surfaces) > len(covered_surfaces)` where `partially_covered_surfaces` entries are treated as uncovered for this calculation — architecture model claims whose `source_subsystem_ids` map exclusively to uncovered surfaces must be capped at `weak-inference`. Additionally, architecture model claims whose `source_subsystem_ids` include a mix of covered and uncovered (or partially covered) surfaces must have their confidence capped at the maximum confidence corresponding to the least-covered surface among their referenced subsystems.

All are degradation rules, not failure conditions; the pipeline may still produce output.

### 5. Risk Review Agent

Responsibilities:

- Produce a prioritized director-level risk scan.
- Highlight brittle boundaries, coupling hotspots, test blind spots, configuration hazards, scaling concerns, and ambiguous ownership zones.
- Emphasize where conceptual architecture diverges from implementation.
- Propagate any upstream `*_unknowns` entry whose `affected_surface_ids` overlap with surfaces used in the risk register, or whose `unknown_type` is `incomplete-coverage`, `blocked-access`, or `ambiguous-signal`, into `risk_unknowns` with a populated `propagated_from` field.

Confidence ceiling rule: the confidence of a downstream risk claim may not exceed the maximum confidence of the upstream architecture model claims it is derived from unless new independent corroborating evidence is added. If all architecture model claims used in deriving a risk are at `weak-inference` or `unknown`, that risk entry must be capped at `weak-inference`.

## Recommended Artifact Set

The orchestrator should assemble a small linked set of outputs:

### `01-executive-brief.md`

Purpose:

- Fastest entry point for understanding the repository.
- Summarize repo purpose, major subsystems, key risks, and recommended reading path.

Required sections:

- source identity summary with `repo_locator` and `source_state_id`
- repository purpose and scope
- top subsystems with links to `02-repo-map.md`
- top risks with links to `04-risk-register.md`
- explicit unknowns and confidence caveats

### `02-repo-map.md`

Purpose:

- Describe the directory, module, service, and boundary structure.
- Rank important areas by architectural significance.

Required sections:

- source identity summary with `repo_locator` and `source_state_id`
- directory and module structure
- subsystem descriptions with materialization status
- dependency surface summary
- hotspots requiring deeper scrutiny
- structure unknowns

### `03-architecture-brief.md`

Purpose:

- Describe the inferred component model and major interaction paths.
- Explain how responsibilities appear to be divided.

Required sections:

- source identity summary with `repo_locator` and `source_state_id`
- component inventory
- major interaction paths
- layering and boundary analysis
- divergence between inferred and intended architecture
- architecture unknowns

### `04-risk-register.md`

Purpose:

- Prioritize architectural and maintainability risks.
- Include evidence and confidence levels for each risk.

Required sections:

- source identity summary with `repo_locator` and `source_state_id`
- risk summary table with severity, title, and affected surfaces
- individual risk entries with statement, evidence, affected surfaces, confidence, and links to supporting JSON artifact IDs
- risk unknowns

### `05-analysis-log.md`

Purpose:

- Record commands run, tests attempted, failed assumptions, and unresolved unknowns.
- Preserve traceability for the conclusions in the other artifacts.

Required sections:

- source identity summary with `repo_locator` and `source_state_id`
- agent or orchestrator run summary: in standalone mode this must include the agent name, `run_id`, overall success/failure/partial status, any `pipeline-error` artifacts emitted, and any confidence degradation rules applied; in coordinated mode this must additionally include all pipeline stages executed with per-stage success or failure status, total wall-clock duration, and whether the output package is complete or partial
- executed and skipped commands linked to `execution-evidence.json`
- failed assumptions and corrections
- unresolved unknowns
- artifact manifest linking all generated Markdown and JSON outputs

In coordinated mode, the orchestrator is the sole writer of `05-analysis-log.md`; specialist agents must not write to this file directly. The orchestrator collects all artifact outputs from specialist agents, computes hashes, and performs the two-pass write after all other artifacts are finalized.

Artifact manifest schema:

- each entry must include `artifact_name`, `artifact_type`, `path`, `run_id`, `schema_version`, `artifact_hash` (SHA-256 of the artifact file contents), and `linked_from` (a list of objects with `artifact_name` and `section_anchor`). Section anchors must use the GitHub Markdown slug convention: lowercase, spaces replaced with hyphens, non-alphanumeric characters stripped. Required section headings in each Markdown artifact must use headings that produce deterministic slugs; agents must use the heading text exactly as specified in the required sections list for that artifact. For JSON artifact entries, `section_anchor` is not applicable and must be omitted or set to `null`; `linked_from` for a JSON artifact must list the Markdown artifacts (and their section anchors) that reference that JSON artifact by filename, providing the cross-reference map for the machine-readable half of the artifact set.
- The `05-analysis-log.md` file itself is exempt from appearing in its own artifact manifest (it is the manifest container). The `artifact_hash` for all other artifacts must be computed from final file contents before being recorded in the manifest. The analysis log must be written in two passes: first, write all content with an empty artifact manifest section and `manifest_complete: false`; second, compute hashes for all other artifacts, write the completed manifest section to `05-analysis-log.md.tmp` in the same output directory, then atomically rename it over `05-analysis-log.md`. Set `manifest_complete: true` only after the rename. If the rename fails, the agent must emit a `pipeline-error` with `error_type: execution-abort` and leave `manifest_complete: false`. A final `manifest_complete: false` is a non-fatal degradation condition; consumers must treat all artifact content as valid except the hash manifest. Consumers detecting `manifest_complete: false` must not rely on artifact hashes from it and must re-read `05-analysis-log.md` to check whether the atomic rename has since completed before treating the first-read state as final. The orchestrator must not declare the output package complete until it has read `05-analysis-log.md` and confirmed `manifest_complete: true`; a `manifest_complete: false` in the final analysis log must be reported as a degradation condition rather than a terminal failure. The `linked_from` lists for JSON artifact entries must be populated by accumulating a registry of JSON artifact filename references during Markdown generation; the orchestrator (or Markdown-generating agents) must maintain this registry and provide it to the analysis log writer before the second pass.

### `pipeline-error.json`

Purpose:

- Provide a structured machine-readable record of agent failures so the orchestrator and callers can distinguish recoverable degradation from terminal failures.

Required fields:

- `schema_version`
- `run_id`
- `agent_name`
- `repo_locator` — use the raw user-supplied input when the error occurs before `repo_locator` is resolved
- `source_state_id` — use `identity_type: "unresolved"` and `primary_id: ""` when the error occurs before source state is resolved; `non_reproducible_source_state` must be `true` in this case
- `non_reproducible_source_state`
- `error_type`: one of `missing-input`, `schema-incompatible`, `incompatible-input`, `blocking-materialization-failure`, `execution-abort`
- `affected_artifact_names`: list of artifact names involved
- `message`: human-readable description
- `recoverable`: boolean — whether the orchestrator may continue with a degraded pipeline. The `recoverable` field is the authoritative value; the recovery classification table below provides the default mappings that agents must use when setting this field. An agent must not set `recoverable: true` for an `error_type` that the table lists as non-recoverable unless the spec is explicitly extended.

Every agent must emit this artifact type on failure rather than producing unstructured error output. The orchestrator must check for this artifact after each stage gate.

Canonical `agent_name` values for use in this artifact and in recovery logic:

- `repo-intake`
- `structure-discovery`
- `execution-and-validation`
- `architecture-synthesis`
- `risk-review`

Recovery classification by error type:

- `missing-input`: non-recoverable, halt pipeline
- `schema-incompatible`: non-recoverable, halt pipeline
- `incompatible-input`: non-recoverable, halt pipeline
- `blocking-materialization-failure`: non-recoverable, halt pipeline
- `execution-abort` from `execution-and-validation`: recoverable, continue with reduced confidence. When the aggregate execution budget is exhausted, the agent must emit a partial `execution-evidence.json` (recording completed commands and `commands_skipped` with `skip_reason: aggregate-budget-exhausted` for unstarted commands) rather than a `pipeline-error`. A `pipeline-error` with `error_type: execution-abort` is reserved for infrastructure or sandbox failures that prevent the agent from producing any `execution-evidence.json`.
- `execution-abort` from any other agent: non-recoverable, halt pipeline

Any `error_type` not listed above is non-recoverable by default unless the spec is explicitly extended.

### `repo-context.json`

Purpose:

- Canonical serialization of the repo context package, the shared handoff object passed between all agents.

### `initial-inventory.json`

Purpose:

- Canonical serialization of the initial inventory artifact, capturing raw Intake findings.

### `repo-map.json`

Purpose:

- Canonical serialization of the repository map artifact, capturing structural conclusions produced by Structure Discovery.
- Serves as the handoff artifact from Structure Discovery to Architecture Synthesis and Risk Review in both coordinated and standalone modes.
- Required input for Architecture Synthesis and Risk Review standalone-mode invocations; those agents reference this file by name when resolving `subsystems`, `dependency_edges`, `boundary_hypotheses`, `hotspots`, and `structure_unknowns`.

### `execution-evidence.json`

Purpose:

- Provide a structured machine-readable record of executed commands, outcomes, timing, and verification coverage.
- Serve as the handoff artifact between Execution and Validation, Architecture Synthesis, and Risk Review in both coordinated and standalone modes.

### `architecture-model.json`

Purpose:

- Provide the structured machine-readable form of the inferred architecture.
- Serve as the handoff artifact from Architecture Synthesis to Risk Review.

### `risk-register.json`

Purpose:

- Provide the structured machine-readable form of identified risks, supporting evidence, and confidence.
- Keep the Markdown risk register traceable to structured claims.

## Pipeline Flow

The orchestrator should run a gated, ordered pipeline rather than a free-form swarm.

1. Repo Intake creates the normalized repo context.
2. Structure Discovery creates the first map and flags candidate hotspots.
3. Execution and Validation checks the inferred structure against real test and build behavior.
4. Architecture Synthesis writes the inferred architecture model.
5. Risk Review runs last and uses all prior artifacts plus retained uncertainty markers.

This sequencing is deliberate. Risk review should not operate on raw code alone; it should evaluate both structure and observed verification results so that risk conclusions are grounded in more than static reading.

## Quality Controls

### Evidence-Backed Claims

Major architectural statements must trace back to code structure, configuration, documentation, or execution evidence.

### Forced Unknowns

Every artifact must explicitly state what the system could not validate. This prevents false completeness, especially in large repositories where partial understanding is unavoidable.

### Risk-Over-Summary Bias

When there is tension between producing a clean narrative and surfacing a messy concern, the system should choose the concern. The suite is intended to optimize for trustworthy understanding, not polished explanation.

### Confidence Propagation

Uncertainty discovered in upstream stages must survive into downstream stages. If subsystem boundaries are inferred rather than verified, the architecture and risk outputs must preserve that distinction instead of flattening it into confident prose.

### Confidence Schema

All structured artifacts should use a normalized confidence field with this four-level scale:

- `verified`: supported by direct execution evidence or unambiguous source evidence.
- `strong-inference`: supported by multiple independent static signals but not directly exercised.
- `weak-inference`: plausible interpretation with limited corroboration.
- `unknown`: insufficient evidence to support a reliable claim.

Downstream agents must not raise confidence levels unless they add new supporting evidence. They may lower confidence when they discover contradictions, execution failures, or incomplete coverage.

## Access Model

Default access for v1:

- Read access to the repository.
- Permission to execute tests and safe discovery commands.

The system should not assume write access to the repository and should not make source modifications.

For remote repositories, Intake is additionally allowed to materialize a read-only local snapshot of the target commit and any accessible submodules or LFS-backed content required for analysis. Authentication handling is limited to obtaining read access; write-capable credentials are out of scope.

## Failure Handling

The system should degrade explicitly rather than silently.

If tests do not run:

- Still generate artifacts.
- Downgrade confidence.
- Explain what could not be verified.

If the repository is too large for exhaustive coverage:

- Prioritize hotspots and architecturally central areas.
- State that coverage is selective rather than uniform.

If language or tooling detection is incomplete:

- Separate confirmed subsystems from inferred ones.
- Avoid presenting incomplete detection as full understanding.

## Design Rationale

This design supports both requested usage modes:

- As a coordinated onboarding system, the orchestrator provides a repeatable way to ingest and reduce a repository into decision-useful outputs.
- As standalone tools, each agent remains independently valuable because it has a narrow purpose and a clear artifact contract.

The design also reflects the primary user priority:

- Faster repository comprehension is the first objective.
- Architectural understanding and code-review-like risk detection are layered on top of that baseline.
- Missing critical architectural risk is treated as the main failure mode, so uncertainty must be preserved and risk review is mandatory.

## Future Extensions

Likely next steps after v1:

- Multi-repository linking and program-level architecture views.
- Interactive Q&A grounded in the generated artifact set.
- Incremental reruns that analyze only changed areas.
- Review workflows that operate on pull requests using the same repo context model.

These are intentionally deferred so that v1 stays focused on reliable repository onboarding.
