import Foundation

struct ParsedRelicTitle {
  let slotCount: Int // 3 / 2 / 1, Parse失敗時は 0
  let color: RelicColor
  let depth: RelicDepth
  /// 各部分のマッチスコア (0...1)。低いものはOCRノイズの可能性
  let sizeScore: Double
  let colorScore: Double
  let depthScore: Double
  let raw: String
  /// Parse結果を再構成した正規形（例: "壮大な燃える景色"; 常に JA 形式）。
  /// fingerprint や depth-invariant 比較などの内部キーとして使う。
  /// 表示には `MasterDataStore.localizedRelicName(...)` を使うこと。
  var canonical: String? {
    let sizeWord = Self.sizeWord(for: slotCount)
    let colorWord = Self.colorWord(for: color)
    let depthWord = Self.depthWord(for: depth)
    guard let sizeWord, let colorWord, let depthWord else { return nil }
    return "\(sizeWord)な\(colorWord)\(depthWord)"
  }
  /// 部分的にしか解決していなくても、解決した部分を埋めて返す（例: "壮大な[?]景色"）
  var bestEffortCanonical: String {
    let sizeWord = Self.sizeWord(for: slotCount) ?? "[?]"
    let colorWord = Self.colorWord(for: color) ?? "[?]"
    let depthWord = Self.depthWord(for: depth) ?? "[?]"
    return "\(sizeWord)な\(colorWord)\(depthWord)"
  }
  var resolvedComponentCount: Int {
    var n = 0
    if slotCount > 0 { n += 1 }
    if color != .unknown { n += 1 }
    if depth != .unknown { n += 1 }
    return n
  }
  var isFullyResolved: Bool { resolvedComponentCount == 3 }

  static func sizeWord(for slotCount: Int) -> String? {
    switch slotCount { case 3: "壮大"; case 2: "端正"; case 1: "繊細"; default: nil }
  }
  static func colorWord(for color: RelicColor) -> String? {
    switch color {
    case .red: "燃える"; case .blue: "滴る"; case .yellow: "輝く"; case .green: "静まる"
    case .unknown: nil
    }
  }
  static func depthWord(for depth: RelicDepth) -> String? {
    switch depth { case .normal: "景色"; case .deep: "昏景"; case .unknown: nil }
  }
}

/// 遺物タイトルを「壮大な燃える景色」/ "Grand Burning Scene" のような形式とみなして
/// スロット数・色・深度を取り出す。JA / EN いずれの OCR 入力にも対応する
///（master `title_words.json` から両言語のキーを生成する）。
final class TitleParser {
  /// （キーワード, スロット数）. JA/EN 両方が混ざる。同じスロット数の語は複数登録される。
  private let sizeKeys: [(String, Int)]
  private let colorKeys: [(String, RelicColor)]
  /// JA: `景色`/`昏景` で normal/deep を判別。
  /// EN: `Scene` は両者共通なので判別子にならず、`Deep` プレフィックスのみを `.deep` の指標として登録する。
  /// EN かつ Deep が見つからなかった場合の `.normal` 推定はParse後段の heuristic で扱う。
  private let depthKeys: [(String, RelicDepth)]
  /// EN normal の暗黙判定に使う基準語（= depths[*].en, 通常 "scene"）
  private let enSceneKeyword: String?
  /// EN deep プレフィックス（通常 "deep"） — 暗黙判定で一致を取りに行く
  private let enDeepKeyword: String?

  /// 受理する最低スコア（キーワード長との比較）
  private let minScore = 0.50

  init(titleWords: TitleWordsMasterFile = MasterDataStore.shared.titleWords) {
    var sizes: [(String, Int)] = []
    for s in titleWords.sizes {
      sizes.append((Self.normalizeKey(s.ja), s.slotCount))
      sizes.append((Self.normalizeKey(s.en), s.slotCount))
    }
    self.sizeKeys = sizes

    var colors: [(String, RelicColor)] = []
    for c in titleWords.colors {
      guard let col = RelicColor(rawValue: c.color) else { continue }
      colors.append((Self.normalizeKey(c.ja), col))
      colors.append((Self.normalizeKey(c.en), col))
    }
    self.colorKeys = colors

    var depths: [(String, RelicDepth)] = []
    var sceneKw: String? = nil
    var deepKw: String? = nil
    for d in titleWords.depths {
      guard let dep = RelicDepth(rawValue: d.depth) else { continue }
      // JA: 景色/昏景 はそれぞれ単独で normal/deep を一意に決める
      depths.append((Self.normalizeKey(d.ja), dep))
      // EN: Deep プレフィックスがある depth だけを登録（normal は暗黙）。
      if let prefix = d.enPrefix {
        depths.append((Self.normalizeKey(prefix), dep))
        deepKw = Self.normalizeKey(prefix)
      } else {
        sceneKw = Self.normalizeKey(d.en)
      }
    }
    self.depthKeys = depths
    self.enSceneKeyword = sceneKw
    self.enDeepKeyword = deepKw
  }

  func parse(_ raw: String) -> ParsedRelicTitle {
    let normalized = normalize(raw)

    let (slot, sScore) = bestMatch(keys: sizeKeys, in: normalized, fallback: 0)
    let (color, cScore) = bestMatch(keys: colorKeys, in: normalized, fallback: RelicColor.unknown)
    var (depth, dScore) = bestMatch(keys: depthKeys, in: normalized, fallback: RelicDepth.unknown)

    // EN フォールバック: depth が決まらず、size/color のいずれかが解決していて、
    // かつ EN の "scene" が含まれているなら通常（.normal） と推定する。
    //（"deep" も検出されていない場合のみ。両者あるなら上で .deep が拾えているはず。）
    if dScore < minScore,
       (sScore >= minScore || cScore >= minScore),
       let scene = enSceneKeyword {
      let sceneScore = approximateSubstringScore(needle: scene, haystack: normalized)
      let deepScore: Double = enDeepKeyword.map {
        approximateSubstringScore(needle: $0, haystack: normalized)
      } ?? 0
      if sceneScore >= 0.7 && deepScore < 0.7 {
        depth = .normal
        dScore = sceneScore
      }
    }

    return ParsedRelicTitle(
      slotCount: sScore >= minScore ? slot : 0,
      color: cScore >= minScore ? color : .unknown,
      depth: dScore >= minScore ? depth : .unknown,
      sizeScore: sScore,
      colorScore: cScore,
      depthScore: dScore,
      raw: raw
    )
  }

  /// マスタから取り出した語を haystack と同じ正規形に揃える（lowercase + 全角→半角 + 空白除去）。
  private static func normalizeKey(_ s: String) -> String {
    var r = s.lowercased()
    r = r.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    r = r.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? r
    return r
  }

  private func normalize(_ s: String) -> String {
    var r = s.lowercased()
    r = r.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    r = r.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? r
    return r
  }

  /// 各キーワードについて、`text` の中の最も近い部分文字列とのスコア (0...1) を計算し、最高得点を返す。
  private func bestMatch<V>(keys: [(String, V)], in text: String, fallback: V) -> (V, Double) {
    var bestValue = fallback
    var bestScore = 0.0
    for (kw, value) in keys {
      let s = approximateSubstringScore(needle: kw, haystack: text)
      if s > bestScore {
        bestScore = s
        bestValue = value
      }
    }
    return (bestValue, bestScore)
  }

  /// `needle` が `haystack` の部分列としてどの程度マッチするかを 0...1 で返す。
  /// haystack の各位置から needle.count 文字の窓を取り、編集距離が最小のものを採用。
  private func approximateSubstringScore(needle: String, haystack: String) -> Double {
    let needleArr = Array(needle)
    let hayArr = Array(haystack)
    let n = needleArr.count
    let h = hayArr.count
    guard n > 0, h > 0 else { return 0 }

    // 完全一致が含まれていれば 1.0
    if haystack.contains(needle) { return 1.0 }

    if h <= n {
      // テキスト全体と編集距離
      let d = levenshtein(Array(haystack), needleArr)
      return 1.0 - Double(d) / Double(n)
    }

    var best = Int.max
    // 窓サイズを needle の長さ ± 1 で動かす
    for windowSize in stride(from: max(1, n - 1), through: min(h, n + 1), by: 1) {
      for i in 0...(h - windowSize) {
        let window = Array(hayArr[i..<(i + windowSize)])
        let d = levenshtein(window, needleArr)
        if d < best { best = d }
        if best == 0 { return 1.0 }
      }
    }
    return max(0.0, 1.0 - Double(best) / Double(n))
  }

  private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
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
