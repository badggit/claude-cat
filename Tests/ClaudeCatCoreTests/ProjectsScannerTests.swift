import XCTest
@testable import ClaudeCatCore

final class ProjectsScannerTests: XCTestCase {
    private var fileManager: FileManager!
    private var root: URL!
    private var cutoff: Date!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("ProjectsScannerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        cutoff = Date(timeIntervalSinceNow: -3600)
    }

    override func tearDownWithError() throws {
        if let root, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        root = nil
        fileManager = nil
        cutoff = nil
        try super.tearDownWithError()
    }

    // Creates a file at a path relative to root and pins its modification date.
    private func makeFile(_ relativePath: String, modifiedAt date: Date) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: url)
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    func testFindsNestedFreshJsonlFile() throws {
        let fresh = try makeFile("a/b/session.jsonl", modifiedAt: Date())

        let found = ProjectsScanner.candidateFiles(under: root, modifiedAfter: cutoff,
                                                   fileManager: fileManager)

        XCTAssertEqual(found.map(\.standardizedFileURL.path),
                       [fresh.standardizedFileURL.path])
    }

    func testExcludesStaleJsonlAndNonJsonlFiles() throws {
        // Stale: mtime one hour before the cutoff.
        _ = try makeFile("a/old-session.jsonl", modifiedAt: cutoff.addingTimeInterval(-3600))
        // Wrong extension despite fresh mtime.
        _ = try makeFile("a/notes.txt", modifiedAt: Date())

        let found = ProjectsScanner.candidateFiles(under: root, modifiedAfter: cutoff,
                                                   fileManager: fileManager)

        XCTAssertTrue(found.isEmpty, "Expected no candidates, got \(found)")
    }

    func testResultsAreSortedByPath() throws {
        let second = try makeFile("z/second.jsonl", modifiedAt: Date())
        let first = try makeFile("a/first.jsonl", modifiedAt: Date())

        let found = ProjectsScanner.candidateFiles(under: root, modifiedAfter: cutoff,
                                                   fileManager: fileManager)

        XCTAssertEqual(found.map(\.standardizedFileURL.path),
                       [first.standardizedFileURL.path, second.standardizedFileURL.path])
    }

    func testNonexistentRootReturnsEmptyWithoutThrowing() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        let found = ProjectsScanner.candidateFiles(under: missing, modifiedAfter: cutoff,
                                                   fileManager: fileManager)

        XCTAssertEqual(found, [])
    }
}
