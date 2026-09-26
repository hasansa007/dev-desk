---
type: index
reviewed: 2026-09-26
---

# docs

What each folder holds. Open the repo root in Obsidian for the same docs as tables — [`docs.base`](../docs.base), whose **Needs review** view lists the living docs, oldest `reviewed:` first. Which folder is which type, and which are frozen, is stated once in [SYSTEM-MODEL → Where the doors write](guide/SYSTEM-MODEL.md#where-the-doors-write).

**Living** — kept current, stamped `reviewed:` by `dev:docs`:

- [`guide/`](guide/) — reader documentation: [getting started](guide/GETTING-STARTED.md), [using it](guide/GUIDE.md), [commands](guide/COMMANDS.md), [workflow](guide/WORKFLOW.md), [system model](guide/SYSTEM-MODEL.md), [contributing](guide/CONTRIBUTING.md).
- [`flows.md`](flows.md) — the project's flow list, read by `dev:arch`, `dev:findings` and Dev Desk.
- [`adr/README.md`](adr/README.md) — the ADR index. And [`../PROJECT_MAP.md`](../PROJECT_MAP.md), the pipeline's memory.

**Frozen** — records, never reviewed and never deleted as old:

- [`adr/`](adr/) — one decision per file, superseded rather than edited.
- [`superpowers/`](superpowers/) — the design specs and the plan Dev Desk was first built from.
- [`findings/`](findings/) — `dev:findings` reports.
- [`validation/`](validation/) — the bootstrap validation and root-cause reports of 2026-09-09/10.
- [`design/`](design/) — the app's design brief and HTML mockups.

**Generated** — [`arch/`](arch/): evidenced diagrams (HTML with their JSON IR), re-pinned by `dev:docs`. [`assets/`](assets/): images the README embeds.
