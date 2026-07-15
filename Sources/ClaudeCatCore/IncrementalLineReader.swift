import Foundation

// Tracks how far into a transcript file we have consumed complete lines,
// plus the file's identity so atomic replacement (new inode) can be detected.
public struct FileReadPosition: Equatable {
    public var byteOffset: UInt64
    // Inode via FileManager attribute .systemFileNumber, captured on first read.
    public var fileIdentity: UInt64?

    public static let start = FileReadPosition(byteOffset: 0, fileIdentity: nil)

    public init(byteOffset: UInt64 = 0, fileIdentity: UInt64? = nil) {
        self.byteOffset = byteOffset
        self.fileIdentity = fileIdentity
    }
}

public enum IncrementalLineReader {
    // Returns complete lines appended since `position`; advances position to just past
    // the last newline consumed. A trailing partial line (no newline yet) is NOT returned
    // and NOT consumed. Resets to byte 0 first when the file was truncated OR replaced:
    // current size < offset, or the file's inode differs from position.fileIdentity.
    // `didReset` is true only when such a rewind actually happened; a very first read
    // from `.start` (offset 0, no identity captured yet) never reports a reset, so
    // callers can safely use it as a "re-ingestion may have occurred" signal.
    public static func readNewLines(
        at url: URL,
        from position: inout FileReadPosition
    ) throws -> (lines: [String], didReset: Bool) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let currentIdentity = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value

        // Truncation or atomic replacement invalidates the stored offset.
        let wasReplaced = position.fileIdentity != nil
            && currentIdentity != nil
            && position.fileIdentity != currentIdentity
        // Note: a first read from `.start` cannot land here (offset 0 satisfies
        // any size, and no identity has been captured yet), so didReset stays false.
        var didReset = false
        if currentSize < position.byteOffset || wasReplaced {
            didReset = true
            position.byteOffset = 0
        }
        position.fileIdentity = currentIdentity

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: position.byteOffset)
        let data = try handle.readToEnd() ?? Data()

        guard let lastNewlineIndex = data.lastIndex(of: UInt8(ascii: "\n")) else {
            // Only a partial line (or nothing) arrived; leave the position untouched.
            return ([], didReset)
        }

        let consumed = data[data.startIndex...lastNewlineIndex]
        var lines: [String] = []
        for lineBytes in consumed.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            // An undecodable line is skipped, but its bytes are still consumed.
            if let line = String(bytes: lineBytes, encoding: .utf8) {
                lines.append(line)
            }
        }
        position.byteOffset += UInt64(consumed.count)
        return (lines, didReset)
    }
}
