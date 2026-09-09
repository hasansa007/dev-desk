# New-Project Bootstrap Path Validation

Validate and fix the new-project path where no ARCHITECTURE.md exists. Both MASTER_PROMPTs (web and mobile) have a new-project bootstrap flow that has never been run. Exercise these paths in real new projects, identify failures, and fix them. Ensure dev-skill works from project day one — not just on mature codebases with existing architecture documentation.

## Rationale
The new-project path is a known gap that has never been tested. For dev-skill to grow beyond its current user base, it must work for developers starting fresh — not just developers adding it to existing projects. This addresses the user goal of having 'a repeatable workflow that works across web, iOS, Android, and KMP projects' including greenfield projects. It also reduces a barrier to adoption for the secondary persona of 'teams adopting AI coding agents.'

## User Stories
- As a developer starting a new project, I want dev-skill to bootstrap the necessary architecture documentation so that I can use the full pipeline from day one
- As a developer, I want the pipeline to handle the absence of ARCHITECTURE.md gracefully rather than failing or producing incorrect results

## Acceptance Criteria
- [ ] The web MASTER_PROMPT new-project path has been exercised in a real new web project
- [ ] The mobile MASTER_PROMPT new-project path has been exercised in a real new mobile project
- [ ] ARCHITECTURE.md is generated correctly for new projects with appropriate initial structure
- [ ] Discovered issues are fixed and re-validated
- [ ] The bootstrap flow works with all supported stacks (Next.js, React, Vue, iOS, Android, KMP)
