import Foundation

/// A fuzzy subsequence match: the score and the title character indices that matched, in order.
public struct FuzzyMatch: Equatable, Sendable {
    public var score: Int
    public var indices: [Int]
}

/// A row that matched, with its match.
public struct RankedRow: Equatable, Sendable {
    public var row: SettingsRow
    public var match: FuzzyMatch
}

/// Subsequence matching with an optimal (dynamic-programming) alignment. Every query letter must
/// appear in the title in order (case-insensitive, query whitespace ignored). Each matched letter
/// earns `matchScore`, plus `wordStartBonus` at the start of a word (and `firstLetterBonus` at the
/// very first letter); a letter right after the previous match earns `consecutiveBonus`, and each
/// title letter skipped between two matches costs `gapPenalty`. Skipped letters before the first
/// match cost `leadingPenalty` each, up to `maxLeadingPenalty`.
public enum FuzzyMatcher {
    public static let matchScore = 16
    public static let wordStartBonus = 24
    public static let firstLetterBonus = 8
    public static let consecutiveBonus = 20
    public static let gapPenalty = 3
    public static let leadingPenalty = 1
    public static let maxLeadingPenalty = 9

    /// ASCII-only case folding (the catalog is ASCII; the web port folds identically).
    static func fold(_ c: Character) -> Character {
        guard let a = c.asciiValue, a >= 65, a <= 90 else { return c }
        return Character(UnicodeScalar(a + 32))
    }

    static func isAlnum(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 48 && a <= 57) || (a >= 65 && a <= 90) || (a >= 97 && a <= 122)
    }

    static func isUpper(_ c: Character) -> Bool { c.asciiValue.map { $0 >= 65 && $0 <= 90 } ?? false }
    static func isLower(_ c: Character) -> Bool { c.asciiValue.map { $0 >= 97 && $0 <= 122 } ?? false }

    /// The query as folded letters, with whitespace removed.
    public static func normalize(_ query: String) -> [Character] {
        query.filter { !$0.isWhitespace }.map(fold)
    }

    /// A word starts at index 0, after a non-alphanumeric character, or at a lower→upper step (camelCase).
    public static func isWordStart(_ title: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let p = title[i - 1], c = title[i]
        if !isAlnum(p) && isAlnum(c) { return true }
        return isLower(p) && isUpper(c)
    }

    /// The best-scoring alignment of `query` in `title`, or nil if it isn't a subsequence.
    /// An empty query matches everything with score 0 and no indices.
    public static func match(_ query: String, in title: String) -> FuzzyMatch? {
        let q = normalize(query)
        if q.isEmpty { return FuzzyMatch(score: 0, indices: []) }
        let raw = Array(title), t = raw.map(fold)
        let n = q.count, m = t.count
        guard n <= m else { return nil }
        let none = Int.min / 4
        var score = Array(repeating: Array(repeating: none, count: m), count: n)
        var back = Array(repeating: Array(repeating: -1, count: m), count: n)
        func base(_ i: Int) -> Int {
            matchScore + (isWordStart(raw, i) ? wordStartBonus : 0) + (i == 0 ? firstLetterBonus : 0)
        }
        for i in 0..<m where t[i] == q[0] {
            score[0][i] = base(i) - min(i * leadingPenalty, maxLeadingPenalty)
        }
        if n > 1 {
            for j in 1..<n {
                for i in j..<m where t[i] == q[j] {
                    var best = none, arg = -1
                    for k in (j - 1)..<i where score[j - 1][k] > none {
                        let link = k == i - 1 ? consecutiveBonus : -gapPenalty * (i - k - 1)
                        let s = score[j - 1][k] + link
                        if s > best { best = s; arg = k }
                    }
                    if arg >= 0 { score[j][i] = best + base(i); back[j][i] = arg }
                }
            }
        }
        var best = none, end = -1
        for i in 0..<m where score[n - 1][i] > best { best = score[n - 1][i]; end = i }
        guard end >= 0 else { return nil }
        var idx = [Int](repeating: 0, count: n)
        var i = end
        for j in stride(from: n - 1, through: 0, by: -1) { idx[j] = i; i = back[j][i] }
        return FuzzyMatch(score: best, indices: idx)
    }

    /// Matching rows, best first: score (high → low), then shorter title, then catalog order.
    /// Non-matches are left out. An empty query keeps every row in catalog order.
    public static func rank(_ query: String, rows: [SettingsRow]) -> [RankedRow] {
        if normalize(query).isEmpty { return rows.map { RankedRow(row: $0, match: FuzzyMatch(score: 0, indices: [])) } }
        let hits = rows.compactMap { r in match(query, in: r.title).map { RankedRow(row: r, match: $0) } }
        return hits.sorted { a, b in
            if a.match.score != b.match.score { return a.match.score > b.match.score }
            if a.row.title.count != b.row.title.count { return a.row.title.count < b.row.title.count }
            return a.row.id < b.row.id
        }
    }
}

/// Which letters became matched between two queries.
public enum MatchDiff {
    /// Per row, the indices matched in `current` that weren't matched in `previous` (sorted);
    /// rows with nothing new are omitted. A row that reappears counts all its letters as new.
    public static func newlyMatched(previous: [Int: [Int]], current: [Int: [Int]]) -> [Int: [Int]] {
        var out: [Int: [Int]] = [:]
        for (row, idx) in current {
            let old = Set(previous[row] ?? [])
            let fresh = idx.filter { !old.contains($0) }.sorted()
            if !fresh.isEmpty { out[row] = fresh }
        }
        return out
    }
}
