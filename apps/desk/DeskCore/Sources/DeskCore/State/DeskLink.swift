import Foundation

/// In-app links carried by markdown text, e.g. desk://task/59; ids are percent-encoded.
public enum DeskLink: Hashable {
    case task(String)
    case finding(String)
    case decision(String)

    public init?(url: URL) {
        guard url.scheme == "desk", let host = url.host else { return nil }
        let id = String(url.path.dropFirst())
        guard !id.isEmpty else { return nil }
        switch host {
        case "task": self = .task(id)
        case "finding": self = .finding(id)
        case "decision": self = .decision(id)
        default: return nil
        }
    }

    public var url: URL {
        let (kind, id): (String, String)
        switch self {
        case .task(let value): (kind, id) = ("task", value)
        case .finding(let value): (kind, id) = ("finding", value)
        case .decision(let value): (kind, id) = ("decision", value)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return URL(string: "desk://\(kind)/\(id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)")!
    }
}
