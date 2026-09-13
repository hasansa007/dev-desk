# dev-skill

This repository **is** the dev family: the doors, the pipeline, and the Mac app that reads them.

## The pipeline does not gate work done here

`shared/pipeline.md` describes seventeen phases with gates at 11–14. **Those gates do not apply to
changes made in this repo.** A repo cannot be governed by the rules it is the source of — running
`dev:verify` → `dev:docs` → `dev:code-review` → `dev:pre-prod` against the thing that defines them is
circular, and it costs more than the change whenever the change is a card's padding.

Work here instead:

```bash
apps/desk/install.sh      # build Dev Desk Release and install it to ~/Applications
```

edit → build → **look at the result on screen** → commit straight to the working branch. No
branch-per-fix, no PR-per-change, no ADR for a visual tweak.

**Keep:** an ADR when a decision reverses an earlier one (that is what `docs/adr/` is for), and the
one-line documentation rule from `docs/guide/CONTRIBUTING.md`.

**This is a rule about THIS repo only.** In every other repository the doors are the product being
used, and their gates hold exactly as written — see `shared/entry.md`'s write boundary.

> Stated by the developer, 2026-09-13: *"dev rules can be not applied to this repo, this repo is the
> creator of it"* · *"it's like the admin rule"* · *"otherwise it will be endless loop"*.

## The app

`apps/desk/` is Dev Desk. `apps/desk/README.md` covers building it; `docs/adr/` records the decisions
it has reversed, which is most of the interesting history.
