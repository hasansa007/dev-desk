import Foundation

/// Turns the registry plus this machine into the two lists the start sheet shows, and never blends them.
///
/// ADR 0036 decision 2: *Run it here* holds ACP adapters only. There is no path in this file that puts a
/// headless or otherwise non-ACP runner into `here` — where nothing can spawn, `here` is empty and
/// `hereEmptyReason` names what is missing, because a fallback is the defect the decision exists to remove.
public enum AcpDetection {

    /// The tools a run can be handed to, detected read-only: a bundle id for an app, a name for a CLI.
    ///
    /// Antigravity is deliberately absent — ADR 0036 names it as a hand-off target, but its bundle id is not
    /// something this file may guess, and a wrong id would report "not installed" for an installed app.
    public static let launchers: [AcpLauncher] = [
        AcpLauncher(id: "terminal", name: "Terminal", bundleId: "com.apple.Terminal"),
        AcpLauncher(id: "iterm", name: "iTerm", bundleId: "com.googlecode.iterm2"),
        AcpLauncher(id: "vscode", name: "VS Code", bundleId: "com.microsoft.VSCode"),
        AcpLauncher(id: "cursor", name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92"),
        AcpLauncher(id: "zed", name: "Zed", bundleId: "dev.zed.Zed"),
        AcpLauncher(id: "sc", name: "super.engineering", command: "sc"),
    ]

    /// The start sheet's two lists; `registry` is nil when it could not be fetched or read from cache, which
    /// is a reason and not an error.
    public static func choices(registry: AcpRegistry?, connections: [Connection], runner: CommandRunner,
                               probe: LauncherProbe? = nil,
                               platform: String = AcpPlatform.current) async -> RunnerChoices {
        let probe = probe ?? CommandLauncherProbe(runner: runner)
        async let handoffRows = handoff(probe: probe)
        let hereRows = await here(registry: registry, connections: connections, runner: runner,
                                  platform: platform)
        return RunnerChoices(here: hereRows.rows, handoff: await handoffRows,
                             hereEmptyReason: hereRows.rows.isEmpty ? hereRows.reason : nil)
    }

    /// The ACP adapters that can actually be spawned on this machine, with the reason when none can.
    static func here(registry: AcpRegistry?, connections: [Connection], runner: CommandRunner,
                     platform: String) async -> (rows: [RunnerOption], reason: String) {
        guard let registry else {
            return ([], "No ACP adapter found: the agent registry could not be read.")
        }
        guard !registry.agents.isEmpty else {
            return ([], "No ACP adapter found: the agent registry lists no agents.")
        }
        var rows: [RunnerOption] = []
        var wantsNpx = false, wantsUvx = false, wantsBinary = false
        var resolved: [String: Bool] = [:]

        for agent in registry.agents {
            guard let spawn = agent.spawnCommand(on: platform) else {
                if case .binary = agent.distribution { wantsBinary = true }
                continue
            }
            switch agent.distribution {
            case .npx: wantsNpx = true
            case .uvx: wantsUvx = true
            case .binary: wantsBinary = true
            case .unknown: break
            }
            // A binary adapter's `cmd` is relative to an archive Dev Desk never downloads — `./opencode`,
            // `./dist-package/cursor-agent`. The same tool installed by its own installer is on PATH under
            // its basename, and `opencode acp` is the same adapter. So the path is what the archive would
            // hold and the basename is what this machine may already have; resolving only the former would
            // hide an adapter that is right there, which is the whole reason a fallback is not needed.
            let candidate = spawn.executable.contains("/")
                ? (spawn.executable as NSString).lastPathComponent : spawn.executable
            if resolved[candidate] == nil {
                let found = (try? await runner.run("which", [candidate], in: nil,
                                                   timeout: CommandTimeout.git))?.succeeded ?? false
                resolved[candidate] = found
            }
            guard resolved[candidate] == true else { continue }
            rows.append(row(for: agent, connections: connections))
        }
        return (sorted(rows), emptyReason(npx: wantsNpx, uvx: wantsUvx, binary: wantsBinary,
                                          resolved: resolved, platform: platform))
    }

    /// An adapter whose own CLI is signed out is shown and not chosen, in that CLI's own words.
    private static func row(for agent: AcpAgent, connections: [Connection]) -> RunnerOption {
        let signedOut = connection(for: agent, in: connections)
        let version = agent.version.map { "acp v1 · \($0)" } ?? "acp v1"
        guard let signedOut else {
            return RunnerOption(id: agent.id, name: agent.name, detail: version, kind: .here)
        }
        return RunnerOption(id: agent.id, name: agent.name,
                            detail: signedOut.detail ?? signedOut.label, kind: .here, isAvailable: false)
    }

    /// Matches an agent to a detected CLI by the id the registry chose — `claude-acp` is the `claude` row —
    /// so no provider is named here.
    static func connection(for agent: AcpAgent, in connections: [Connection]) -> Connection? {
        let parts = Set(agent.id.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init))
        return connections.first { $0.isSignedOut && parts.contains($0.id) }
    }

    /// Names every missing piece, because "nothing available" tells a developer nothing they can act on.
    private static func emptyReason(npx: Bool, uvx: Bool, binary: Bool, resolved: [String: Bool],
                                    platform: String) -> String {
        var missing: [String] = []
        if npx, resolved["npx"] != true { missing.append("npx is not on PATH") }
        if uvx, resolved["uvx"] != true { missing.append("uvx is not on PATH") }
        if binary { missing.append("no agent ships a \(platform) binary this app can run") }
        guard !missing.isEmpty else {
            return "No ACP adapter found: no agent in the registry ships a distribution this build understands."
        }
        return "No ACP adapter found: " + missing.joined(separator: ", and ") + "."
    }

    /// Every launcher, installed or not: an absent one is still a row saying so, per `RunnerOption`.
    static func handoff(probe: LauncherProbe) async -> [RunnerOption] {
        let rows = await launchers.concurrentMap { launcher -> RunnerOption in
            let installed = await probe.isInstalled(launcher)
            return RunnerOption(id: launcher.id, name: launcher.name,
                                detail: installed ? nil : "not installed", kind: .handoff,
                                isAvailable: installed)
        }
        return sorted(rows)
    }

    /// The order both lists use: what can be chosen first, then by name, then by id — stable across refreshes
    /// so a row never moves under the pointer, and so a default selection is the same one twice running.
    static func sorted(_ rows: [RunnerOption]) -> [RunnerOption] {
        rows.sorted { left, right in
            if left.isAvailable != right.isAvailable { return left.isAvailable }
            let byName = left.name.localizedCaseInsensitiveCompare(right.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return left.id < right.id
        }
    }
}

/// A tool a run can be handed to: an app found by bundle id, or a CLI found on PATH.
public struct AcpLauncher: Hashable, Identifiable {
    public let id: String
    public let name: String
    public let bundleId: String?
    public let command: String?

    public init(id: String, name: String, bundleId: String? = nil, command: String? = nil) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.command = command
    }
}

/// Asking whether a launcher is on this Mac, injected so a test never reads the real machine.
public protocol LauncherProbe {
    func isInstalled(_ launcher: AcpLauncher) async -> Bool
}

/// The default probe: Spotlight for a bundle id, `which` for a CLI — read-only, and nothing is launched.
public struct CommandLauncherProbe: LauncherProbe {
    let runner: CommandRunner

    public init(runner: CommandRunner) { self.runner = runner }

    public func isInstalled(_ launcher: AcpLauncher) async -> Bool {
        if let bundleId = launcher.bundleId {
            let query = "kMDItemCFBundleIdentifier == '\(bundleId)'"
            let result = try? await runner.run("mdfind", [query], in: nil, timeout: CommandTimeout.git)
            return result?.succeeded == true && !(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        guard let command = launcher.command else { return false }
        return (try? await runner.run("which", [command], in: nil, timeout: CommandTimeout.git))?.succeeded ?? false
    }
}
