## Phase 2 — Tech Stack & Project Discovery

Always run, regardless of source:

1. **Read `PROJECT_MAP.md`** if it exists — extract `TECH_STACK` and `SYSTEM_FLOW`. If absent, create it in Phase 7.

2. **Ambiguity check:** If the requirements have any ambiguity (unclear scope, missing context, conflicting signals), stop and ask. Do not choose a path silently.

3. **Time awareness:** Note the current year and month. For any dependency, library, or tool decision, check for the latest stable version.

4. Scan root files to detect stack:
   - `package.json` → Node / React / Vue / Next.js
   - `build.gradle.kts` / `settings.gradle.kts` → Android / KMP
   - `*.xcodeproj` / `project.yml` → iOS
   - Mixed `androidApp/` + `iOSApp/` + `shared/` → KMP multi-platform
   - `Cargo.toml` → Rust
   - `pyproject.toml` / `requirements.txt` → Python
   - `go.mod` → Go

5. Identify affected platforms from the ticket/feature description.
6. Identify relevant files, models, DB tables, or modules likely touched.

**After detecting the stack, read the matching platform pipeline and apply its additions to Phases 10, 11, and 14:**

| Detected stack | Platform pipeline |
|---|---|
| `*.xcodeproj` / `Package.swift` (Swift only) | `platforms/mobile/pipeline-ios.md` |
| `build.gradle*` + Android manifest only | `platforms/mobile/pipeline-android.md` |
| `androidApp/` + `iOSApp/` + `shared/` (KMP) | `platforms/mobile/pipeline-kmp.md` |
| `package.json` → Next.js / React / Vue | `platforms/web/pipeline-web.md` |

### Exploration Fan-Out (conditional)

**When:** the work touches territory the context files don't cover — a new subsystem, an area
absent from `PROJECT_MAP.md`, or any Deep-tier feature. **Skip** when PROJECT_MAP + prior work
already cover the area (most Light/Standard tasks — do not fan out for a known-territory fix).

1. Launch 2–3 `feature-dev:code-explorer` agents **in parallel** (any read-only explore agent
   works if the plugin is absent), each with a DIFFERENT focus, e.g.:
   - "Find features similar to [feature] and trace their implementation end-to-end"
   - "Map the architecture and abstractions of [affected area]"
   - "Identify UI patterns, testing approaches, or extension points relevant to [feature]"
2. Ask each agent to return its findings **plus a list of 5–10 key files**.
3. **Read the flagged files yourself** before planning — the agent report is a map, not a
   substitute for the territory.
4. Fold anything durable into `PROJECT_MAP.md` (that's what makes the next task skip this step).

---

