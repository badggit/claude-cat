import XCTest
@testable import ClaudeCatCore

final class IncrementalLineReaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalLineReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    private func fileURL(_ name: String = "transcript.jsonl") -> URL {
        tempDirectory.appendingPathComponent(name)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testReadsNewLinesIncrementally() throws {
        let url = fileURL()
        try write("first\nsecond\n", to: url)

        var position = FileReadPosition.start
        let firstRead = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(firstRead.lines, ["first", "second"])
        XCTAssertFalse(firstRead.didReset)
        XCTAssertEqual(position.byteOffset, UInt64("first\nsecond\n".utf8.count))

        try append("third\n", to: url)
        let secondRead = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(secondRead.lines, ["third"])
        XCTAssertFalse(secondRead.didReset)

        let thirdRead = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(thirdRead.lines, [])
        XCTAssertFalse(thirdRead.didReset)
    }

    func testPartialLineIsNotConsumedUntilNewlineArrives() throws {
        let url = fileURL()
        try write("done\n", to: url)

        var position = FileReadPosition.start
        _ = try IncrementalLineReader.readNewLines(at: url, from: &position)
        let offsetAfterCompleteLines = position.byteOffset

        try append("partial", to: url)
        let readWithPartial = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(readWithPartial.lines, [])
        XCTAssertFalse(readWithPartial.didReset)
        XCTAssertEqual(position.byteOffset, offsetAfterCompleteLines)

        try append("\n", to: url)
        let readAfterNewline = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(readAfterNewline.lines, ["partial"])
        XCTAssertFalse(readAfterNewline.didReset)
    }

    func testTruncationResetsReadPosition() throws {
        let url = fileURL()
        try write("a long enough first line\nand a second one\n", to: url)

        var position = FileReadPosition.start
        _ = try IncrementalLineReader.readNewLines(at: url, from: &position)

        // Truncate to zero, then write shorter content: size < offset must reset to byte 0.
        try write("fresh\n", to: url)
        let read = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(read.lines, ["fresh"])
        XCTAssertTrue(read.didReset)
        XCTAssertEqual(position.byteOffset, UInt64("fresh\n".utf8.count))
    }

    func testAtomicReplacementWithLargerFileResetsReadPosition() throws {
        let url = fileURL()
        try write("old\n", to: url)

        var position = FileReadPosition.start
        _ = try IncrementalLineReader.readNewLines(at: url, from: &position)

        // Atomically replace with LARGER content so the size check alone cannot
        // detect the swap — the inode mismatch must win. The replacement is created
        // while the old file still exists (as atomic writers do), so it is
        // guaranteed to get a different inode; a bare delete-and-recreate could
        // silently reuse the freed inode and not exercise the identity check.
        let replacementURL = fileURL("replacement.tmp")
        try write("replacement line one\nreplacement line two\n", to: replacementURL)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacementURL, to: url)

        let read = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(read.lines, ["replacement line one", "replacement line two"])
        XCTAssertTrue(read.didReset)
    }

    func testUndecodableLineIsSkippedButConsumed() throws {
        let url = fileURL()
        var data = Data("good\n".utf8)
        data.append(Data([0xFF, 0xFE, 0xFF]))
        data.append(Data("\nafter\n".utf8))
        try data.write(to: url)

        var position = FileReadPosition.start
        let read = try IncrementalLineReader.readNewLines(at: url, from: &position)
        XCTAssertEqual(read.lines, ["good", "after"])
        XCTAssertFalse(read.didReset)
        XCTAssertEqual(position.byteOffset, UInt64(data.count))
    }

    func testNonexistentFileThrows() {
        let url = fileURL("does-not-exist.jsonl")
        var position = FileReadPosition.start
        XCTAssertThrowsError(try IncrementalLineReader.readNewLines(at: url, from: &position))
    }
}
