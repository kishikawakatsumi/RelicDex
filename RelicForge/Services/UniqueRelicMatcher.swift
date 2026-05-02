import Foundation

struct UniqueRelicMatch {
  let relic: UniqueRelic
  /// 0...1 のマッチスコア
  let score: Double
  /// マッチに使った OCR 由来テキスト
  let recognizedText: String
}

/// OCRで取り出したタイトル候補を、固有遺物名と Levenshtein ベースで照合する。
/// 固有遺物名は短く（2〜10文字程度）、誤マッチを避けるため厳しめの閾値を採る。
final class UniqueRelicMatcher {
  private let uniques: [UniqueRelic]
  /// 各固有遺物名の正規化済み文字配列（JA, EN）。
  /// JA / EN の両方に対して照合し、高い方を採用する。
  private let normalizedTargets: [(ja: [Character], en: [Character])]

  /// 採用する最低スコア。固有遺物名は短いので、ほぼ完全一致を要求する。
  private let confirmThreshold: Double = 0.80

  init(uniques: [UniqueRelic] = MasterDataStore.shared.uniqueRelics) {
    self.uniques = uniques
    self.normalizedTargets = uniques.map { u in
      (Array(Self.normalize(u.nameJa)),
       Array(Self.normalize(u.nameEn)))
    }
  }

  /// 候補となるテキスト群（OCR行や連結）から、最高スコアの固有遺物を返す。
  func bestMatch(in candidates: [String]) -> UniqueRelicMatch? {
    var best: UniqueRelicMatch?
    for raw in candidates {
      let normalized = Array(Self.normalize(raw))
      guard !normalized.isEmpty else { continue }
      for (i, u) in uniques.enumerated() {
        let pair = normalizedTargets[i]
        let scoreJa = approximateSubstringScore(needle: pair.ja, haystack: normalized)
        let scoreEn = approximateSubstringScore(needle: pair.en, haystack: normalized)
        let score = max(scoreJa, scoreEn)
        if best == nil || score > (best?.score ?? 0) {
          best = UniqueRelicMatch(relic: u, score: score, recognizedText: raw)
        }
      }
    }
    guard let m = best, m.score >= confirmThreshold else { return nil }
    return m
  }

  static func normalize(_ s: String) -> String {
    var r = s.lowercased()
    r = r.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    r = r.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? r
    return r
  }

  private func approximateSubstringScore(needle: [Character], haystack: [Character]) -> Double {
    let n = needle.count; let h = haystack.count
    guard n > 0, h > 0 else { return 0 }
    // 完全包含なら即 1.0
    if h >= n {
      let needleStr = String(needle)
      let haystackStr = String(haystack)
      if haystackStr.contains(needleStr) { return 1.0 }
    }
    if h <= n {
      let d = Self.levenshtein(haystack, needle)
      return 1.0 - Double(d) / Double(n)
    }
    var best = Int.max
    for windowSize in stride(from: max(1, n - 1), through: min(h, n + 1), by: 1) {
      for i in 0...(h - windowSize) {
        let window = Array(haystack[i..<(i + windowSize)])
        let d = Self.levenshtein(window, needle)
        if d < best { best = d }
        if best == 0 { return 1.0 }
      }
    }
    return max(0.0, 1.0 - Double(best) / Double(n))
  }

  private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    let m = a.count, n = b.count
    if m == 0 { return n }
    if n == 0 { return m }
    var prev = Array(0...n)
    var curr = Array(repeating: 0, count: n + 1)
    for i in 1...m {
      curr[0] = i
      for j in 1...n {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
      }
      swap(&prev, &curr)
    }
    return prev[n]
  }
}
