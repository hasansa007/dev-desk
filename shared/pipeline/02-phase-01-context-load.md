## Phase 1 — Context Load

Runs before everything else. Reads persistent project context to skip re-discovery.

1. **Check for `PROJECT_MAP.md`** → load `TECH_STACK`, `SYSTEM_FLOW`, `ORPHANS & PENDING`. If absent, create in Phase 7.
2. **Check for `ARCHITECTURE.md`** → load decisions. If absent, proceed with Phase 2 discovery (it is optional).
3. **Check for `specs/[feature-slug].md`** → if found, resume from existing spec (skip Phase 7; for BUGS, Phase 4 reproduce-first is never skipped).
4. **Report what was loaded:** name each file found or note fallback (e.g. `"ARCHITECTURE loaded. PROJECT_MAP will be created in Phase 7."`). Missing files are not blockers — proceed either way.

If a spec is found and Phase 8 or Phase 9 is the next step, skip straight there.

---

