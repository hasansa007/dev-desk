import Foundation
import XCTest
@testable import DeskCore

/// The registry document as published on 2026-09-16, trimmed to the shapes detection has to survive.
enum AcpRegistryFixture {
    static let json = """
    {
      "version": "1.0.0",
      "agents": [
        { "id": "claude-acp", "name": "Claude Agent", "version": "0.78.0",
          "description": "ACP wrapper for Anthropic's Claude",
          "repository": "https://github.com/agentclientprotocol/claude-agent-acp",
          "authors": ["Anthropic", "Zed Industries", "JetBrains"], "license": "proprietary",
          "distribution": { "npx": { "package": "@agentclientprotocol/claude-agent-acp@0.78.0" } } },
        { "id": "cursor-agent", "name": "Cursor Agent", "version": "2026.9.1",
          "description": "Cursor's own agent", "repository": "https://cursor.com",
          "website": "https://cursor.com", "authors": ["Anysphere"], "license_url": "https://cursor.com/terms",
          "icon": "https://cursor.com/icon.png",
          "distribution": { "binary": {
            "darwin-aarch64": { "archive": "https://cursor.com/a.tar.gz", "cmd": "./dist-package/cursor-agent",
                                "args": ["acp"], "sha256": "abc123" },
            "linux-x86_64": { "archive": "https://cursor.com/l.tar.gz", "cmd": "./dist-package/cursor-agent",
                              "args": ["acp"] } } } },
        { "id": "opencode", "name": "opencode", "version": "1.17.18", "authors": ["opencode"],
          "distribution": { "binary": {
            "darwin-aarch64": { "archive": "https://opencode.ai/a.tar.gz", "cmd": "./opencode",
                                "args": ["acp"] } } } },
        { "id": "future-agent", "name": "Future Agent", "version": "1.0.0", "authors": [],
          "newTopLevelField": { "anything": true },
          "distribution": { "wasm": { "module": "future.wasm" } } }
      ],
      "extensions": []
    }
    """

    static func registry() throws -> AcpRegistry {
        try AcpRegistry.decode(Data(json.utf8))
    }

    static func agent(_ id: String) throws -> AcpAgent {
        let agent = try registry().agents.first { $0.id == id }
        return try XCTUnwrap(agent)
    }
}

final class AcpRegistryTests: XCTestCase {
    func testTheRealShapedDocumentDecodesWithItsNpxAndBinaryAgents() throws {
        let registry = try AcpRegistryFixture.registry()
        XCTAssertEqual(registry.version, "1.0.0")
        XCTAssertEqual(registry.agents.map(\.id), ["claude-acp", "cursor-agent", "opencode", "future-agent"])
        let claude = try AcpRegistryFixture.agent("claude-acp")
        XCTAssertEqual(claude.name, "Claude Agent")
        XCTAssertEqual(claude.authors, ["Anthropic", "Zed Industries", "JetBrains"])
        XCTAssertEqual(claude.license, "proprietary")
        XCTAssertNil(claude.website)
        XCTAssertEqual(claude.distribution, .npx(AcpPackage(package: "@agentclientprotocol/claude-agent-acp@0.78.0")))
        let cursor = try AcpRegistryFixture.agent("cursor-agent")
        XCTAssertEqual(cursor.licenseURL, "https://cursor.com/terms")
        guard case .binary(let platforms) = cursor.distribution else { return XCTFail("expected a binary distribution") }
        XCTAssertEqual(Set(platforms.keys), ["darwin-aarch64", "linux-x86_64"])
        XCTAssertEqual(platforms["darwin-aarch64"]?.sha256, "abc123")
    }

    func testAnUnknownDistributionKindAndUnknownFieldsDecodeWithoutThrowing() throws {
        let future = try AcpRegistryFixture.agent("future-agent")
        XCTAssertEqual(future.distribution, .unknown)
        XCTAssertNil(future.spawnCommand(on: "darwin-aarch64"))
    }

    func testAnAgentThatCannotBeReadAtAllIsSkippedRatherThanBreakingTheDocument() throws {
        let json = """
        { "version": "2.0.0", "agents": [ { "name": "No id here" },
          { "id": "good", "name": "Good", "distribution": { "npx": { "package": "p" } } } ] }
        """
        let registry = try AcpRegistry.decode(Data(json.utf8))
        XCTAssertEqual(registry.agents.map(\.id), ["good"])
    }

    func testTheNpxSpawnCommandIsNpxWithTheYesFlagAndThePinnedPackage() throws {
        let claude = try AcpRegistryFixture.agent("claude-acp")
        let spawn = try XCTUnwrap(claude.spawnCommand(on: "darwin-aarch64"))
        XCTAssertEqual(spawn.executable, "npx")
        XCTAssertEqual(spawn.arguments, ["-y", "@agentclientprotocol/claude-agent-acp@0.78.0"])
    }

    func testTheBinarySpawnCommandComesFromThePlatformEntryAndIsNilWhereThereIsNone() throws {
        let cursor = try AcpRegistryFixture.agent("cursor-agent")
        let spawn = try XCTUnwrap(cursor.spawnCommand(on: "darwin-aarch64"))
        // Verbatim from the registry, archive-relative and all: turning it into something spawnable is
        // detection's job, not this type's. `AcpDetection` resolves the basename against PATH.
        XCTAssertEqual(spawn.executable, "./dist-package/cursor-agent")
        XCTAssertEqual(spawn.arguments, ["acp"])
        XCTAssertNil(cursor.spawnCommand(on: "windows-x86_64"))
    }

    func testTheUvxSpawnCommandUsesFromWithItsPackage() throws {
        let json = """
        { "agents": [ { "id": "uv-agent", "name": "Uv Agent",
          "distribution": { "uvx": { "package": "some-agent==1.2", "args": ["acp"] } } } ] }
        """
        let agent = try XCTUnwrap(AcpRegistry.decode(Data(json.utf8)).agents.first)
        let spawn = try XCTUnwrap(agent.spawnCommand(on: "darwin-aarch64"))
        XCTAssertEqual(spawn.executable, "uvx")
        XCTAssertEqual(spawn.arguments, ["--from", "some-agent==1.2", "acp"])
    }

    func testThePlatformKeyIsDerivedFromUnameForBothMacArchitectures() {
        XCTAssertEqual(AcpPlatform.key(from: ("Darwin", "arm64")), "darwin-aarch64")
        XCTAssertEqual(AcpPlatform.key(from: ("Darwin", "x86_64")), "darwin-x86_64")
        XCTAssertTrue(AcpPlatform.current.hasPrefix("darwin-"), AcpPlatform.current)
    }
}
