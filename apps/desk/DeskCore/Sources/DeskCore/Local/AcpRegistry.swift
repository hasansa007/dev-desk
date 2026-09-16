import Foundation

/// The ACP agent registry as published, decoded so that a field we have never seen can never break a launch.
///
/// ADR 0036 decision 2 makes the registry the only thing that names an agent: nothing here knows that Claude
/// or Cursor exist. Unknown top-level keys are ignored, and an agent whose entry cannot be read at all is
/// dropped rather than taking the document down with it.
public struct AcpRegistry: Decodable, Hashable {
    public let version: String?
    public let agents: [AcpAgent]

    public init(version: String? = nil, agents: [AcpAgent]) {
        self.version = version
        self.agents = agents
    }

    private enum CodingKeys: String, CodingKey { case version, agents }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        let entries = try container.decodeIfPresent([LenientlyDecoded<AcpAgent>].self, forKey: .agents) ?? []
        agents = entries.compactMap(\.value)
    }

    /// The registry as fetched or cached; a document that is not JSON at all still throws, because that is a
    /// fetch that failed rather than a registry that grew.
    public static func decode(_ data: Data) throws -> AcpRegistry {
        try JSONDecoder().decode(AcpRegistry.self, from: data)
    }
}

/// One agent the registry names, with only `id` genuinely required — everything else may be absent or new.
public struct AcpAgent: Decodable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let version: String?
    public let description: String?
    public let repository: String?
    public let website: String?
    public let authors: [String]
    public let license: String?
    public let licenseURL: String?
    public let icon: String?
    public let distribution: AcpDistribution

    public init(id: String, name: String, version: String? = nil, description: String? = nil,
                repository: String? = nil, website: String? = nil, authors: [String] = [],
                license: String? = nil, licenseURL: String? = nil, icon: String? = nil,
                distribution: AcpDistribution = .unknown) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.repository = repository
        self.website = website
        self.authors = authors
        self.license = license
        self.licenseURL = licenseURL
        self.icon = icon
        self.distribution = distribution
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, description, repository, website, authors, license, icon, distribution
        case licenseURL = "license_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        repository = try container.decodeIfPresent(String.self, forKey: .repository)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        license = try container.decodeIfPresent(String.self, forKey: .license)
        licenseURL = try container.decodeIfPresent(String.self, forKey: .licenseURL)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        distribution = (try? container.decodeIfPresent(AcpDistribution.self, forKey: .distribution)) ?? .unknown
    }

    /// What to spawn for this agent on one platform, or nil when it ships nothing that runs there.
    public func spawnCommand(on platform: String = AcpPlatform.current) -> AcpSpawnCommand? {
        distribution.spawnCommand(on: platform)
    }
}

/// How an agent is shipped: exactly one of the three keys the registry uses, or `.unknown` for a kind
/// published after this build — which is a reason not to offer the agent, never a reason to fail decoding.
public enum AcpDistribution: Decodable, Hashable {
    case npx(AcpPackage)
    case uvx(AcpPackage)
    case binary([String: AcpBinary])
    case unknown

    private enum Keys: String, CodingKey { case npx, uvx, binary }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if let npx = try container.decodeIfPresent(AcpPackage.self, forKey: .npx) { self = .npx(npx) }
        else if let uvx = try container.decodeIfPresent(AcpPackage.self, forKey: .uvx) { self = .uvx(uvx) }
        else if let binary = try container.decodeIfPresent([String: AcpBinary].self, forKey: .binary) {
            self = .binary(binary)
        } else { self = .unknown }
    }

    /// `npx -y <package>`, `uvx --from <package>`, or the platform entry's own command; nil when this
    /// platform has no entry. The uvx form is modelled from the schema and is UNTESTED — no agent in the
    /// registry ships that way today, so nothing has ever run it.
    public func spawnCommand(on platform: String) -> AcpSpawnCommand? {
        switch self {
        case .npx(let package):
            return AcpSpawnCommand(executable: "npx", arguments: ["-y", package.package] + package.args,
                                   environment: package.env)
        case .uvx(let package):
            return AcpSpawnCommand(executable: "uvx", arguments: ["--from", package.package] + package.args,
                                   environment: package.env)
        case .binary(let platforms):
            guard let entry = platforms[platform] else { return nil }
            return AcpSpawnCommand(executable: entry.cmd, arguments: entry.args, environment: entry.env)
        case .unknown:
            return nil
        }
    }
}

/// An npx or uvx distribution: the pinned package plus whatever the registry wants passed with it.
public struct AcpPackage: Decodable, Hashable {
    public let package: String
    public let args: [String]
    public let env: [String: String]

    public init(package: String, args: [String] = [], env: [String: String] = [:]) {
        self.package = package
        self.args = args
        self.env = env
    }

    private enum CodingKeys: String, CodingKey { case package, args, env }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        package = try container.decode(String.self, forKey: .package)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }
}

/// One `{os}-{arch}` entry of a binary distribution; `archive` and `sha256` describe a download the app does
/// not perform yet, so only `cmd` and `args` take part in detection.
public struct AcpBinary: Decodable, Hashable {
    public let archive: String?
    public let cmd: String
    public let args: [String]
    public let sha256: String?
    public let env: [String: String]

    public init(archive: String? = nil, cmd: String, args: [String] = [], sha256: String? = nil,
                env: [String: String] = [:]) {
        self.archive = archive
        self.cmd = cmd
        self.args = args
        self.sha256 = sha256
        self.env = env
    }

    private enum CodingKeys: String, CodingKey { case archive, cmd, args, sha256, env }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archive = try container.decodeIfPresent(String.self, forKey: .archive)
        cmd = try container.decode(String.self, forKey: .cmd)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }
}

/// The process a detected adapter would become, exactly as the registry described it.
public struct AcpSpawnCommand: Hashable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(executable: String, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// The registry's `{os}-{arch}` key for the machine this build is running on, read from `uname` rather than
/// assumed, so a Rosetta or Intel process never claims the Apple Silicon archive.
public enum AcpPlatform {
    public static let current: String = key(from: systemInfo())

    static func key(from info: (sysname: String, machine: String)) -> String {
        let os = info.sysname.lowercased()
        let arch: String
        switch info.machine {
        case "arm64", "aarch64", "arm64e": arch = "aarch64"
        case "x86_64", "amd64": arch = "x86_64"
        default: arch = info.machine
        }
        return "\(os)-\(arch)"
    }

    private static func systemInfo() -> (sysname: String, machine: String) {
        var info = utsname()
        guard uname(&info) == 0 else { return ("unknown", "unknown") }
        return (string(from: info.sysname), string(from: info.machine))
    }

    /// `utsname` fields are fixed-size C tuples, so the name is the bytes up to the first NUL.
    private static func string<T>(from field: T) -> String {
        withUnsafeBytes(of: field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// Lets one malformed element be skipped instead of throwing away the array it sits in.
struct LenientlyDecoded<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws { value = try? Wrapped(from: decoder) }
}
