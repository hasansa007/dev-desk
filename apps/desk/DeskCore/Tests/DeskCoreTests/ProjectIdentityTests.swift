import XCTest
@testable import DeskCore

final class ProjectIdentityDerivationTests: XCTestCase {
    func testColourIsDeterministicForTheSameRef() {
        let ref = ProjectRef.local(path: "/Users/hasan/Developer/studyhub")
        let first = ProjectIdentity.paletteHex(forID: ref.id)
        XCTAssertEqual(first, ProjectIdentity.paletteHex(forID: ref.id))
        // The literal is the point: the same project must wear the same colour on every machine, so a
        // change to the hash or the palette order has to be a deliberate one.
        XCTAssertEqual(first, "#8FD3E8")
        XCTAssertEqual(ProjectIdentity.paletteHex(forID: ProjectRef.local(path: "/Users/hasan/Developer/skills/dev-desk").id), "#C9CFD9")
    }

    func testColourAlwaysComesFromThePalette() {
        for i in 0..<200 {
            XCTAssertTrue(ProjectIdentity.palette.contains(ProjectIdentity.paletteHex(forID: "local:/p/\(i)")))
        }
    }

    func testPaletteAvoidsTheReservedGreenAndAmberBand() {
        for hex in ProjectIdentity.palette {
            XCTAssertFalse(ProjectIdentity.isReserved(hex: hex), "\(hex) sits in the running/waiting band")
        }
        // The status colours themselves, to prove the guard is not vacuous.
        XCTAssertTrue(ProjectIdentity.isReserved(hex: "#7FD19B"))  // running green
        XCTAssertTrue(ProjectIdentity.isReserved(hex: "#E7C067"))  // waiting amber
    }

    func testHueOfKnownColours() {
        XCTAssertEqual(ProjectIdentity.hue(ofHex: "#FF0000") ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(ProjectIdentity.hue(ofHex: "#00FF00") ?? -1, 120, accuracy: 0.5)
        XCTAssertEqual(ProjectIdentity.hue(ofHex: "#0000FF") ?? -1, 240, accuracy: 0.5)
        XCTAssertNil(ProjectIdentity.hue(ofHex: "#808080"))
        XCTAssertNil(ProjectIdentity.hue(ofHex: "nonsense"))
    }

    func testInitialsFromAName() {
        XCTAssertEqual(ProjectIdentity.initials(from: "dev-desk"), "DD")
        XCTAssertEqual(ProjectIdentity.initials(from: "studyhub-deploy"), "SD")
        XCTAssertEqual(ProjectIdentity.initials(from: "studyhub"), "ST")
        XCTAssertEqual(ProjectIdentity.initials(from: "my_cool_thing"), "MC")
        XCTAssertEqual(ProjectIdentity.initials(from: "Acme App"), "AA")
        XCTAssertEqual(ProjectIdentity.initials(from: "x"), "X")
        XCTAssertEqual(ProjectIdentity.initials(from: "///"), "")
    }
}

@MainActor
final class ProjectIdentityStoreTests: XCTestCase {
    private var directories: [URL] = []

    private func makeStore() -> ProjectIdentityStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directories.append(dir)
        return ProjectIdentityStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                    key: "test.identities",
                                    imagesDirectory: dir)
    }

    override func tearDown() {
        directories.forEach { try? FileManager.default.removeItem(at: $0) }
        directories = []
        super.tearDown()
    }

    func testDefaultIsInitialsOnTheDerivedColour() {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/dev-desk")
        let identity = store.identity(for: ref, name: "dev-desk")
        XCTAssertEqual(identity.initials, "DD")
        XCTAssertEqual(identity.colorHex, ProjectIdentity.paletteHex(forID: ref.id))
        XCTAssertNil(identity.imagePath)
    }

    func testChosenColourWinsAndSurvivesAReload() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let ref = ProjectRef.local(path: "/p/a")
        let store = ProjectIdentityStore(defaults: defaults, key: "k", imagesDirectory: FileManager.default.temporaryDirectory)
        store.setColor("#B8A7F2", for: ref)
        XCTAssertEqual(store.identity(for: ref, name: "a").colorHex, "#B8A7F2")

        let reloaded = ProjectIdentityStore(defaults: defaults, key: "k", imagesDirectory: FileManager.default.temporaryDirectory)
        XCTAssertEqual(reloaded.identity(for: ref, name: "a").colorHex, "#B8A7F2")
    }

    func testAReservedColourIsRefused() {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/a")
        store.setColor("#7FD19B", for: ref)
        XCTAssertEqual(store.identity(for: ref, name: "a").colorHex, ProjectIdentity.paletteHex(forID: ref.id))
    }

    func testResetGoesBackToInitials() {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/a")
        store.setColor("#F2A7C3", for: ref)
        store.reset(ref)
        XCTAssertEqual(store.mark(for: ref), .initials)
        XCTAssertEqual(store.identity(for: ref, name: "a").colorHex, ProjectIdentity.paletteHex(forID: ref.id))
    }

    func testImageIsCopiedInAndSurvivesTheOriginalGoingAway() throws {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/a")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try onePixelPNG().write(to: source)

        try store.setImage(from: source, for: ref)
        try FileManager.default.removeItem(at: source)

        let identity = store.identity(for: ref, name: "a")
        let path = try XCTUnwrap(identity.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.hasPrefix(store.imagesDirectory.path))
    }

    func testAFileThatIsNotAnImageIsRefusedRatherThanStored() throws {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/a")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        XCTAssertThrowsError(try store.setImage(from: source, for: ref))
        XCTAssertNil(store.identity(for: ref, name: "a").imagePath)
    }

    func testAMissingCopyFallsBackToInitials() throws {
        let store = makeStore()
        let ref = ProjectRef.local(path: "/p/a")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try onePixelPNG().write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        try store.setImage(from: source, for: ref)

        try FileManager.default.removeItem(atPath: XCTUnwrap(store.identity(for: ref, name: "a").imagePath))
        XCTAssertNil(store.identity(for: ref, name: "a").imagePath)
    }

    /// The smallest valid PNG; ImageIO has to accept it and a text file has to fail against it.
    private func onePixelPNG() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    }
}
