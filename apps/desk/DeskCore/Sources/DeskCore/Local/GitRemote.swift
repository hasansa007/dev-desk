public enum GitRemote {
    /// "git@github.com:owner/repo.git" and "https://github.com/owner/repo" both become "github.com/owner/repo".
    public static func display(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let scheme = value.range(of: "://") { value = String(value[scheme.upperBound...]) }
        if let at = value.firstIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if let colon = value.firstIndex(of: ":"), !value[..<colon].contains("/") {
            value.replaceSubrange(colon...colon, with: "/")
        }
        return value
    }

    /// "owner/repo" when the remote is on github.com, otherwise nil.
    public static func githubSlug(_ url: String) -> String? {
        let shown = display(url)
        guard shown.hasPrefix("github.com/") else { return nil }
        let parts = shown.dropFirst("github.com/".count).split(separator: "/")
        return parts.count == 2 ? parts.joined(separator: "/") : nil
    }
}
