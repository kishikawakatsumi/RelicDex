import Foundation

struct EffectMatch: Identifiable {
  let id = UUID()
  let effect: RelicEffect
  let score: Double
  let recognizedText: String
}

final class EffectMatcher {
  private let effects: [RelicEffect]
  /// 各効果につき（JA, EN） の正規化済みテキストを文字配列でキャッシュ。
  /// OCR が JA / EN どちらで読み取られたかは事前にわからないので両方に対して
  /// マッチを試し、高い方を採用する。
  /// `applyingTransform` は ICU 経由で高コストなので init で 1 度だけ計算する。
  private let normalizedTargets: [(ja: [Character], en: [Character])]

  /// スコアの最低採用ライン（これ未満は extractSlots 側でも捨てるので、ここで早期スキップする）
  private let scoreFloor: Double = 0.45

  init(effects: [RelicEffect] = MasterDataStore.shared.effects) {
    self.effects = effects
    self.normalizedTargets = effects.map { e in
      (Array(Self.normalize(e.textJa)),
       Array(Self.normalize(e.textEn)))
    }
  }

  func topMatches(for recognizedText: String, limit: Int = 3) -> [EffectMatch] {
    let normalized = Array(Self.normalize(recognizedText))
    guard !normalized.isEmpty else { return [] }
    let inputLen = normalized.count

    // floor=0.45 を満たすには distance <= 0.55 * maxLen が必要。
    // つまり |inputLen - targetLen| > 0.55 * maxLen の効果は絶対に採用されない。
    // Levenshtein を計算する前に長さ差で篩い落とすだけで対象が ~70-80% 減る。
    let maxAllowedRatio = 1.0 - scoreFloor

    var scored: [EffectMatch] = []
    scored.reserveCapacity(64)

    for (i, effect) in effects.enumerated() {
      let pair = normalizedTargets[i]
      let scoreJa = scoreAgainst(input: normalized, inputLen: inputLen,
                                 target: pair.ja, maxAllowedRatio: maxAllowedRatio)
      let scoreEn = scoreAgainst(input: normalized, inputLen: inputLen,
                                 target: pair.en, maxAllowedRatio: maxAllowedRatio)
      let score = max(scoreJa, scoreEn)
      if score < scoreFloor { continue }
      scored.append(EffectMatch(effect: effect, score: score, recognizedText: recognizedText))
    }

    return scored
      .sorted { $0.score > $1.score }
      .prefix(limit)
      .map { $0 }
  }

  /// 1 つの target に対する正規化済み入力のスコア。floor を割る場合は 0 を返す。
  private func scoreAgainst(
    input: [Character], inputLen: Int,
    target: [Character], maxAllowedRatio: Double
  ) -> Double {
    let targetLen = target.count
    let maxLen = max(inputLen, targetLen)
    if maxLen == 0 { return 0 }
    let lenDiff = abs(inputLen - targetLen)
    if Double(lenDiff) / Double(maxLen) > maxAllowedRatio { return 0 }
    let maxDistance = Int(Double(maxLen) * maxAllowedRatio)
    let distance = Self.levenshteinBounded(input, target, maxDistance: maxDistance)
    if distance > maxDistance { return 0 }
    return 1.0 - Double(distance) / Double(maxLen)
  }

  func bestMatch(for recognizedText: String, threshold: Double = 0.6) -> EffectMatch? {
    guard let top = topMatches(for: recognizedText, limit: 1).first else { return nil }
    return top.score >= threshold ? top : nil
  }

  static func normalize(_ s: String) -> String {
    var result = s
    result = result.lowercased()
    result = result.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    result = result.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? result
    result = result.applyingTransform(.hiraganaToKatakana, reverse: false) ?? result
    // 数値 / 符号の直前にある単独 カ (カタカナ) を 力 (漢字) に置換する。
    // ゲームのフォントで 力 と カ がほぼ同じ字形のため OCR が頻繁に取り違える。
    // 例: "持久カ+1" → "持久力+1" / "筋カ+2" → "筋力+2"
    // 「カット率」「カウンター」など正当な カ には影響しない (次が +/-/数字でないため)。
    //
    // 注: 上の `.fullwidthToHalfwidth` で全角カナが半角カナ ｶ に変換されているので
    // 全角 カ と半角 ｶ の両方を含む文字クラスでマッチさせる必要がある。
    result = result.replacingOccurrences(
      of: "[カｶ](?=[0-9+\\-])",
      with: "力",
      options: .regularExpression
    )
    return result
  }

  static func similarity(_ a: [Character], _ b: [Character]) -> Double {
    if a.isEmpty && b.isEmpty { return 1.0 }
    let distance = levenshtein(a, b)
    let maxLen = max(a.count, b.count)
    return 1.0 - Double(distance) / Double(maxLen)
  }

  static func similarity(_ a: String, _ b: String) -> Double {
    similarity(Array(a), Array(b))
  }

  static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    levenshteinBounded(a, b, maxDistance: .max)
  }

  static func levenshtein(_ a: String, _ b: String) -> Int {
    levenshtein(Array(a), Array(b))
  }

  /// 距離が `maxDistance` を超えそうになったら計算を打ち切るバージョン。
  /// 打ち切られた場合は `maxDistance + 1` 以上の値を返す（具体値は不定）。
  /// これにより 1 ペアあたり最悪 O(m*n) → 多くのケースで O(m + 数行) になる。
  static func levenshteinBounded(_ a: [Character], _ b: [Character], maxDistance: Int) -> Int {
    let m = a.count
    let n = b.count
    if m == 0 { return n }
    if n == 0 { return m }
    let lenDiff = abs(m - n)
    if lenDiff > maxDistance { return maxDistance + 1 }

    var prev = Array(0...n)
    var curr = Array(repeating: 0, count: n + 1)

    for i in 1...m {
      curr[0] = i
      var rowMin = curr[0]
      for j in 1...n {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        let v = min(
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost
        )
        curr[j] = v
        if v < rowMin { rowMin = v }
      }
      // 行の最小値が maxDistance を超えたら、これ以降のどの経路も改善できない。
      if rowMin > maxDistance { return maxDistance + 1 }
      swap(&prev, &curr)
    }
    return prev[n]
  }
}
