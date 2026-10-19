import Foundation

struct SubtitleCue: Hashable {
    let start: Double
    let end: Double
    let text: String
}

/// AVPlayer cannot load sidecar subtitle files, so cues are parsed here and drawn by PlayerView.
enum SubtitleParser {
    static func parse(_ raw: String, mimeType: String) -> [SubtitleCue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let cues = mimeType == "text/x-ssa" ? parseASS(text) : parseTimedBlocks(text)
        return cues.sorted { $0.start < $1.start }
    }

    // SRT and WebVTT: blocks separated by blank lines, a line with "-->" holds the times.
    private static func parseTimedBlocks(_ text: String) -> [SubtitleCue] {
        text.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[i].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]),
                  let end = seconds(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]) else { return nil }
            let body = clean(lines[(i + 1)...].joined(separator: "\n"))
            return body.isEmpty ? nil : SubtitleCue(start: start, end: end, text: body)
        }
    }

    // ASS/SSA: "Dialogue: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text"
    private static func parseASS(_ text: String) -> [SubtitleCue] {
        text.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("Dialogue:") else { return nil }
            let fields = line.dropFirst("Dialogue:".count).split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10, let start = seconds(String(fields[1])), let end = seconds(String(fields[2])) else { return nil }
            let body = clean(String(fields[9]).replacingOccurrences(of: "\\N", with: "\n"))
            return body.isEmpty ? nil : SubtitleCue(start: start, end: end, text: body)
        }
    }

    /// "00:01:02,345", "01:02.345" or "0:01:02.34" -> seconds
    private static func seconds(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for p in parts {
            guard let v = Double(p) else { return nil }
            total = total * 60 + v
        }
        return total
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cue visible at `time` (cues are sorted by start; binary search then a short backwards scan for overlaps).
    static func cue(at time: Double, in cues: [SubtitleCue]) -> SubtitleCue? {
        var lo = 0, hi = cues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        var i = lo - 1
        while i >= 0 && i >= lo - 5 {
            if time < cues[i].end { return cues[i] }
            i -= 1
        }
        return nil
    }
}
