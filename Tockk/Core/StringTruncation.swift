import Foundation

extension String {
    /// Returns a version of the string clamped to `maxChars` grapheme clusters
    /// (Swift `Character`s, not UTF-16 code units), with a middle ellipsis when
    /// truncation occurs. Safe for Hangul, emoji, and combined scalars.
    ///
    /// - `head + "…" + tail`, where head is the larger half when the budget is
    ///   odd. Example: 30 chars → 10 produces 5-char head + `…` + 4-char tail.
    /// - Degenerate budgets (`<= 1`) collapse to a single `"…"` — the caller is
    ///   expected to pass a sensible limit.
    func truncatedMiddle(maxChars: Int) -> String {
        let chars = Array(self)
        guard chars.count > maxChars else { return self }
        guard maxChars >= 2 else { return "…" }

        let budget = maxChars - 1                 // reserve one slot for "…"
        let headCount = (budget + 1) / 2          // bias toward the head
        let tailCount = budget - headCount

        let head = String(chars.prefix(headCount))
        let tail = String(chars.suffix(tailCount))
        return head + "…" + tail
    }
}
