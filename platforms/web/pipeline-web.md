# Pipeline — Web Additions

Apply these additions to Phases 10, 11, and 14 when the detected stack is **Web** (`package.json` → Next.js / React / Vue).

---

## Phase 10 — Web Additions

### UI Previews
Add `.stories.tsx` story per component state variant for all new UI components. Use realistic production-shaped fixture data.

Skip if the project has no Storybook setup — do not add Storybook as part of a feature.

### Localization Audit
Only run if the project already uses an i18n library (e.g. `next-intl`, `react-i18next`, `i18next`).

If detected:
- Wrap new user-visible strings in `t('key')` / `intl.formatMessage`
- Add key to every locale JSON / YAML file
- Draft baseline translations for all supported locales

If not detected: skip localization audit entirely.

### Release Notes Draft
Draft changelog / release notes entry:
- **Features:** New pages, flows, or significant capabilities
- **Improvements:** UX polish, performance, behavioral changes
- **Bug fixes:** Issues resolved (reference ticket/issue ID)

No platform isolation rules apply (single platform).

---

## Phase 11 — Web Build & Verification (agent-run via Chrome DevTools MCP)

**Server first:** check whether the dev server is already running (probe the app's port). The developer may run it themselves (IDE run config) — connect to THEIR instance; never start a second one on the same port. Start `npm run dev` only if nothing is running AND the project has no run-it-myself convention; when the convention exists but the port is silent, ask the developer to start it (their run button) — do not start it for them. Run `npm run build` only if the repo has no rule against it (some do — check memory/CLAUDE.md); the test suite plus the live checks below are the default evidence.

**Execute the Phase 11 checklist yourself** with the Chrome DevTools MCP tools:

1. `new_page` / `navigate_page` to the flow's entry point — signed in via the project's dev sign-in path when one exists.
2. Drive each row: `click`, `fill`, `press_key` through the real UI — the same clicks the user would make.
3. Evidence per row: `take_screenshot` of the end state, `list_console_messages` (no new errors), `list_network_requests` (expected calls, expected statuses).
4. UI components: screenshot each new state variant; for RTL/LTR products, both directions.
5. Flaky/ambiguous behavior: `navigate_page` with an `initScript` error listener to attribute errors the console won't; compare responses with direct `curl` of the same endpoints.

Mark rows ✅/❌ with the evidence attached. Hand the developer ONLY the rows the browser can't reach (real OAuth, real payments) plus the prod decision.

---

## Phase 14 — Web Pre Prod Note

After PR is merged, remind:

> "Merged to pre prod. Run `vercel` for a preview, or push to your pre-prod branch if auto-deploy is configured. Production is Phase 16 — a separate promotion with its own gate."

No store submission steps apply.
