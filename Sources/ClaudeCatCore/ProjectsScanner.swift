import Foundation

// Locates transcript files worth reading. Transcripts are append-only jsonl,
// so a modification date older than the cutoff (e.g. the logical-day start)
// proves the file contains no entries newer than that cutoff.
public enum ProjectsScanner {
    // Recursively finds *.jsonl under root with modification date >= cutoff, sorted by path.
    // Missing/unreadable root -> [] (never throws).
    public static func candidateFiles(under root: URL, modifiedAfter cutoff: Date,
                                      fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true } // Skip unreadable entries, keep scanning.
        ) else {
            return []
        }
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey]
            ), values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }
            candidates.append(url.standardizedFileURL)
        }
        return candidates.sorted { $0.path < $1.path }
    }
}
