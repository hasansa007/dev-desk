import Foundation

/// How the Diagrams screen runs `dev:arch` for one kind: an interactive session in the terminal, like every other
/// door, so the run is watched and its questions answered where it runs. A headless `-p` run showed an empty pane
/// until it exited, and a question it asked ended it with nothing drawn. The screen does not wait for the exit:
/// it picks the file up as soon as one newer than the start lands (`ProjectWindowModel.pickUpGeneratedDiagram`).
public enum ArchRun {
    /// The `dev:arch` prompt for one kind, with an optional target. The door reads what to draw first and a
    /// bare type token after it, so a target leads and the type follows; an empty target draws the whole
    /// project. Built from the same skill path `DoorCommand` uses, so both doors read the same SKILL.md.
    /// `outputName` fixes the file stem — a flow's sequence is `<repo>-sequence-<flow slug>`, which is how the
    /// screen matches the drawing back to its row (ADR 0047).
    public static func prompt(agent name: String, kind: String, target: String, home: String,
                              outputName: String? = nil) -> String? {
        guard DoorCommand.backgroundAgent(named: name) != nil else { return nil }
        var arguments: [String] = []
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { arguments.append(trimmed) }
        arguments.append(kind)
        guard let door = DoorCommand.prompt(door: "arch", agent: name, arguments: arguments, home: home) else { return nil }
        let naming = outputName.map { " Name the files docs/arch/\($0).html and its sidecar docs/arch/\($0).\(kind).json." } ?? ""
        return door + " " + screenInstruction + naming
    }

    /// The answers the screen already has, so the run does not ask for them (SKILL.md's "Runs from Dev Desk").
    public static let screenInstruction =
        "Started from Dev Desk's Diagrams screen. With no target, draw the whole project. Do not cut a branch or "
        + "stash; write only the new docs/arch/<name>.* files on the current branch, leaving every other change in "
        + "the tree untouched."

    /// The interactive argv — the CLI with its prompt, the form a door's terminal command takes. nil for a CLI
    /// with no verified invocation for this door.
    public static func launch(agent name: String, kind: String, target: String, home: String,
                              outputName: String? = nil) -> [String]? {
        guard let agent = DoorCommand.backgroundAgent(named: name),
              let prompt = prompt(agent: name, kind: kind, target: target, home: home, outputName: outputName) else { return nil }
        return [agent.executable, prompt]
    }
}
