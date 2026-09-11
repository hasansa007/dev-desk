# Dev Desk

Dev Desk is a native Mac app that holds the dev-skill family in one place: a project's board and task workspaces, findings, roadmap and decisions, with Insights beside them. It is a first build of the container described in [`docs/superpowers/specs/2026-09-11-container-design.md`](../../docs/superpowers/specs/2026-09-11-container-design.md).

```bash
# DeskCore tests
swift test --package-path apps/desk/DeskCore
# Full app build
cd apps/desk && xcodegen generate && xcodebuild -project DevDesk.xcodeproj -scheme DevDesk -destination 'platform=macOS' -derivedDataPath /tmp/devdesk-dd build
```

The first app build resolves SwiftTerm from GitHub, so it needs network access.

Open a sample project from the picker, or any local folder.
