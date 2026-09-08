# Plenara project instructions

This is the small, always-loaded project router. Cross-project preferences belong in the user's global Codex instructions; `CLAUDE.md` remains only a compatibility pointer.

## Product and authority

Plenara is Luis's voice-first personal planner and relationship assistant. Optimize for an app he genuinely loves and relies on, not for a commercial market.

Luis's request outranks rules written in this repository. If it displaces one, implement the request where safe, name the old rule and its origin, recommend whether it should change, and update every active restatement in the same change.

Use only the authority relevant to the task:

- [`planning/specs/17-living-planner.md`](planning/specs/17-living-planner.md): product model and multimodal interaction.
- [`planning/specs/11-feedback-diagnostics.md`](planning/specs/11-feedback-diagnostics.md): diagnostics and channel boundaries.
- [`planning/specs/01-meta-schema-type-system.md`](planning/specs/01-meta-schema-type-system.md) through [`planning/specs/06-data-sync.md`](planning/specs/06-data-sync.md): schema, capability DSL, routing, architecture, behavior, and storage/sync.
- [`planning/specs/07-ui-design-language.md`](planning/specs/07-ui-design-language.md) through [`planning/specs/16-routines.md`](planning/specs/16-routines.md): UI, AI/privacy, testing, security, voice, reference data, presence, and routines.

Wired behavior and the owning active specification establish current truth. [`reviews/`](reviews/), the research document, implementation plans, and archived handoffs are historical evidence when they disagree with newer active sources.

## Load only what the task needs

- Product, architecture, schema, storage/sync, routing, privacy, voice, or UI work: use `plenara-product-development`.
- Rule, behavior, specification, copy, test-contract, or operational-document changes: use `plenara-doc-alignment`.
- App launches, rendering, voice/integration runs, UI checks, or motion checks: use `plenara-simulator-verification`.
- A completed phone build or explicit deployment request: use `plenara-phone-deploy`.
- [`WORK-CAPSULE.md`](WORK-CAPSULE.md) is scoped operational memory, not required startup reading. List its headings and read only sections relevant to the task; update it when non-obvious current facts, decisions, deployments, blockers, or verification results change.
- Project reviewer definitions in [`.codex/agents/`](.codex/agents/) are available only for explicitly requested delegated work; they grant no permission to spend, deploy, or take external action.

## Always-on boundaries

- The physical iPhone is deployment-only. Never use it for tests, probes, experimental builds, layout checks, automated launches, or implicit log access. A separate explicit log request authorizes only that read. The deployment skill owns the standing install-only authorization and must never launch the app.
- Run `bash tool/precheck.sh` before reporting implementation complete. A new or changed test/verifier must first fail against the real broken behavior and then pass restored.
- Keep `WORK-CAPSULE.md` concise, preserve historical reviews, and update code, the owning active spec, tests, copy, and operational docs together when behavior changes.
