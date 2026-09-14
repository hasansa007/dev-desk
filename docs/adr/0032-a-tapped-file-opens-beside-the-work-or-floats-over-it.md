# 0032 — A tapped file opens beside the work, or floats over it

Status:  Accepted
Date:    2026-09-14
Commit:  (this branch) · `gh-775-enqueue-build-payload-trust`
Amends:  0021 (Files is an edge, and nothing floats)

## Context

ADR 0021 point 6 made Files a single right edge of the window and said nothing floats. It read the
file's contents *inside that same edge*, under the tree, split by a divider — the tree above, the
selected file below. Used against a real project, two things were wrong with that. The panel opened
at 420 pt, a width decided once for every project and screen. And the file being read shared the
tree's narrow column, so a line of code wrapped or scrolled sideways in a strip while the work it
came from kept the whole rest of the window.

The developer asked for three things: open the panel at its minimum width; on tapping a file, do not
show it under the tree — open it as its own pane beside the work, with a top nav bar; and fix the
Open action, which did nothing when pressed.

Point 6's "nothing floats" was written against the old floating panels with their own Dock and Float
buttons — chrome no other Mac app asks of a panel. A file's *reader* is a different thing from a
docked panel: it is a way of looking at one file, opened and dismissed, not a placement to restore.

## Decision

**1. Files opens at its floor.** Opening the panel sets its width to the range's lower bound (260 pt);
a width you drag it to belongs to that opening, not to every later one. Asking for a panel that is
already open leaves the width you gave it alone.

**2. A tapped file is a pane of its own, beside the work.** The inline under-the-tree viewer is gone.
Tapping a file opens `FileViewerPane` as a column between the work and the tree, so the tree stays
rightmost where it was. It earns that column only while the work keeps at least a third of the
window after the tree and the viewer take theirs — about 926 pt with both at their floors. Below
that, three columns would be three strips, so the viewer floats over the work behind a scrim that
dismisses it. This is the one thing that floats, and it is a reader, not a docked panel: it amends
point 6 for the file's contents only. The tree remains an edge that does not float.

**3. The pane carries a nav bar.** The file's path, a Preview/`</>` toggle (Preview renders markdown,
Code shows the bytes; a non-markdown file reads the same either way), Reveal, Open, an expand toggle
that fills the window, and a close that clears the selection and leaves the tree open.

**4. Open reports what the system said.** The old `NSWorkspace.open(_:)` threw away its `Bool`, so a
refused open — no handler, a path naming nothing — looked like a dead button. And the URL was never
validated: `FileTree` can hand back an absolute path as an entry id, and appending that to the root
built a path naming nothing. The URL is now built by a pure `ProjectWindowModel.fileURL(root:relativePath:)`
that rejects an absolute, empty or escaping id (`SafeFile.isInside`), and the open uses the modern
completion API, surfacing the system's own reason through the existing failure banner. The
URL-construction lives in DeskCore, tested; the `NSWorkspace` call stays in the app target.

## Consequences

`FileViewer` inside `FilesPanel` is deleted; `FilesPanel` is tree-only. `ContentRouter` hosts the
pane and decides split-versus-float from the window width. `ProjectWindowModel` gains
`filesWidthMin`, `projectRoot`, `fileURL`, `selectedFileURL`, `closeFile()`, `openFile(_:)`,
`openSelectedFile()` and an injected `editorOpen` hook, so opening is decided in the model and
performed by the app target. The floating reader is a narrow, deliberate exception to 0021's rule,
not its reversal: the tree is still an edge, and nothing else floats.
