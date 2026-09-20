import DeskCore
import SwiftUI

/// What each section is, and every phrase someone might go looking for it by.
///
/// The sections themselves are `SettingsSection` in DeskCore and are not re-titled here — the ADR 0046 names
/// are what the rest of the app calls them. What is new is `terms`: a developer hunting for the agent limit
/// or the worktree location searched for "worktree", not for "Execution", and a ten-row list gives them no
/// way to find out which of the ten it is in without opening all ten (2026-09-20).
enum SettingsIndex {
    static func blurb(_ section: SettingsSection) -> String {
        switch section {
        case .general: return "Version, dev doctor"
        case .appearance: return "Light or dark, app icon, terminal size"
        case .agentsAndDefaults: return "Which agent a run starts, and in what mode"
        case .startWith: return "Other apps and commands a task can open in"
        case .accountsAndConnections: return "Who each CLI is signed in as"
        case .notifications: return "When Dev Desk interrupts you, and with what sound"
        case .execution: return "Worktrees, how many agents at once, quitting"
        case .work: return "What the Work tab counts as next, and as done"
        case .projectOverrides: return "What this repository says, Auto, and cleanup"
        case .runProject: return "The commands that start this project"
        }
    }

    static func symbol(_ section: SettingsSection) -> String {
        switch section {
        case .general: return "slider.horizontal.3"
        case .appearance: return "circle.lefthalf.filled"
        case .agentsAndDefaults: return "cpu"
        case .startWith: return "arrow.up.forward.app"
        case .accountsAndConnections: return "person.badge.key"
        case .notifications: return "bell"
        case .execution: return "bolt"
        case .work: return "list.bullet.rectangle"
        case .projectOverrides: return "folder.badge.gearshape"
        case .runProject: return "play.rectangle"
        }
    }

    /// The words a setting is hunted by, which are almost never the words on its section. Each entry is a
    /// phrase shown back as the reason a section matched, so a search result says WHICH setting it found.
    static func terms(_ section: SettingsSection) -> [String] {
        switch section {
        case .general:
            return ["version", "dev doctor", "diagnostics", "about"]
        case .appearance:
            return ["light mode", "dark mode", "theme", "colour scheme", "app icon", "terminal text size", "font size"]
        case .agentsAndDefaults:
            return ["default connection", "claude", "codex", "gemini", "opencode", "antigravity",
                    "background runs", "run mode", "plan mode", "capabilities", "model"]
        case .startWith:
            return ["start with", "open in", "other apps", "handoff", "custom command", "placeholders"]
        case .accountsAndConnections:
            return ["sign in", "sign out", "login", "logout", "github", "account", "credentials"]
        case .notifications:
            return ["notifications", "alerts", "sound", "permission", "decisions", "failed runs", "banner"]
        case .execution:
            return ["worktree location", "parallel checkouts", "agent limit", "agents at once",
                    "findings run size", "reload", "auto reload", "confirm quit", "ask before quitting"]
        case .work:
            return ["next up", "milestone", "done limit", "pull requests without an issue", "review"]
        case .projectOverrides:
            return ["repository facts", "auto mode", "reset findings", "cleanup", "branch prefix"]
        case .runProject:
            return ["run configuration", "setup command", "npm install", "dev server", "stop command",
                    "run.json", "default configuration"]
        }
    }

    /// Whether the section has anything to show with no project open (Home, ADR 0050).
    ///
    /// `startWith` is here although it reads as project work: the list is one `@AppStorage` key for every
    /// project and renders whole without a snapshot. `accountsAndConnections` is NOT, and that is a gap
    /// rather than a choice — connections are read off a project's snapshot, so with no project there is
    /// no list to draw and an empty Accounts pane would say "nothing is connected", which is not known.
    static func existsWithoutProject(_ section: SettingsSection) -> Bool {
        switch section {
        case .general, .appearance, .agentsAndDefaults, .startWith, .notifications, .execution: return true
        case .accountsAndConnections, .work, .projectOverrides, .runProject: return false
        }
    }

    /// Sections matching `query`, and for each the terms that matched — the result says what it found, not
    /// merely that something was found. An empty query is every section, in declaration order.
    static func search(_ query: String) -> [SettingsMatch] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return SettingsSection.allCases.map { SettingsMatch(section: $0, matches: []) } }
        return SettingsSection.allCases.compactMap { section in
            let matches = terms(section).filter { $0.contains(needle) }
            let titled = section.title.lowercased().contains(needle) || blurb(section).lowercased().contains(needle)
            guard titled || !matches.isEmpty else { return nil }
            return SettingsMatch(section: section, matches: matches)
        }
    }
}

/// One index entry after a search: the section, and the phrases that put it in the list.
struct SettingsMatch: Identifiable {
    let section: SettingsSection
    let matches: [String]

    var id: SettingsSection { section }
}
