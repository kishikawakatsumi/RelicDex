import Foundation
import UIKit

// MARK: - 認識結果

struct RecognizedEffectLine: Identifiable {
  let id = UUID()
  let ocrLine: OCRLine
  let candidates: [EffectMatch]
  var selected: EffectMatch?
}

/// 1スロット = メイン効果 + （深層遺物のみ） 任意のデメリット効果。
struct RecognizedSlot: Identifiable {
  let id = UUID()
  let main: RecognizedEffectLine
  let demerit: RecognizedEffectLine?
}

struct TitleCandidate: Identifiable {
  let id = UUID()
  let text: String
  let parsed: ParsedRelicTitle
  var totalScore: Double {
    parsed.sizeScore + parsed.colorScore + parsed.depthScore
  }
}

/// 認識処理の最終結果。色/スロット数/深度はすべてテキスト由来。
struct RecognizedRelic {
  let title: String?
  let parsedTitle: ParsedRelicTitle?
  let titleCandidates: [TitleCandidate]
  let uniqueMatch: UniqueRelicMatch?
  let ocrLines: [OCRLine]
  let slots: [RecognizedSlot]

  var isUnique: Bool { uniqueMatch != nil }

  /// 認識したゲーム画面の言語が日本語か。
  ///
  /// 単に「CJK が 1 文字でもあれば JA」とすると、英語ゲーム画面でも Vision の
  /// 誤読でわずかに CJK っぽい字が混入したケース (例: 似形の漢字 1 文字) で
  /// 日本語扱いになり、表示が混在する事故が起きる。OCR 全行を集計して
  /// **CJK 文字数 vs Latin アルファベット文字数** を比べ、多数派を採用する。
  var isJapaneseScan: Bool {
    var cjk = 0
    var latin = 0
    func tally(_ s: String) {
      for sc in s.unicodeScalars {
        let v = sc.value
        if v >= 0x3000 { cjk += 1 }
        else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { latin += 1 }
      }
    }
    if let title { tally(title) }
    for line in ocrLines { tally(line.text) }
    // 文字がほぼ無いときは title 単独に従う (安全側で英語)。
    if cjk == 0 && latin == 0 { return false }
    return cjk > latin
  }

  /// 表示名はロケールではなく **スキャンした言語** に追従させる。
  /// 端末ロケールが英語でも、日本語ゲーム画面を読み取った結果は日本語名で表示される。
  /// （タイトルから CJK 検出して `isJapaneseScan` を判定）
  var displayName: String {
    let ja = isJapaneseScan
    if let unique = uniqueMatch?.relic {
      return MasterDataStore.shared.relicName(
        slotCount: unique.slotCount, color: unique.color, depth: .unknown,
        uniqueId: unique.id, forJapanese: ja
      )
    }
    if let p = parsedTitle, p.isFullyResolved {
      return MasterDataStore.shared.relicName(
        slotCount: p.slotCount, color: p.color, depth: p.depth, forJapanese: ja
      )
    }
    if let p = parsedTitle, p.resolvedComponentCount > 0 { return p.bestEffortCanonical }
    return title ?? String(localized: "(title not detected)")
  }

  var color: RelicColor {
    if let unique = uniqueMatch?.relic { return unique.color }
    return parsedTitle?.color ?? .unknown
  }

  var slotCount: Int {
    if let unique = uniqueMatch?.relic { return unique.slotCount }
    return parsedTitle?.slotCount ?? 0
  }

  /// 固有遺物は **通常（`.normal`） として扱う**。深度フィルタや slot 装着可否で
  /// 各所が `isUnique ? .normal : depth` のような workaround を持たなくて済むよう、
  /// 認識/保存の段階で常に `.normal` を返す。
  var depth: RelicDepth {
    if uniqueMatch != nil { return .normal }
    return parsedTitle?.depth ?? .unknown
  }

  /// 表示用のスロット配列。固有遺物の場合はマスタの固定効果から組み立てる
  /// （固有遺物はデメリット無し）。
  var resolvedSlots: [ResolvedSlot] {
    if let unique = uniqueMatch?.relic {
      return MasterDataStore.shared.resolvedEffects(for: unique).map {
        ResolvedSlot(main: $0, demerit: nil)
      }
    }
    return slots.map { slot in
      let main = slot.main.selected?.effect ?? slot.main.candidates.first?.effect
      let demerit = slot.demerit?.selected?.effect ?? slot.demerit?.candidates.first?.effect
      return ResolvedSlot(main: main, demerit: demerit)
    }
  }

  /// この認識結果が「実在する遺物」として扱えるかどうか。
  /// - 固有遺物としてマッチ済み → 有効
  /// - 一般遺物：タイトル3要素すべて解決 + メインスロット数一致
  ///   - 通常（景色） はデメリットがあってはいけない
  ///   - 深層（昏景） はデメリットの数は問わない（0..slotCount）
  var isValid: Bool {
    if isUnique { return true }
    guard let parsed = parsedTitle, parsed.isFullyResolved, parsed.slotCount > 0 else {
      return false
    }
    guard slots.count == parsed.slotCount else { return false }
    if parsed.depth == .normal {
      return slots.allSatisfy { $0.demerit == nil }
    }
    return true
  }
}

/// 表示・保存用に解決した1スロットの情報。
struct ResolvedSlot: Identifiable {
  let id = UUID()
  let main: RelicEffect?
  let demerit: RelicEffect?
}

// MARK: - キャプチャ入力

struct CapturedRelic {
  let image: UIImage
  let textRegionInImage: CGRect
}

// MARK: - 認識器

final class RelicRecognizer {
  private let ocr: OCRService
  private let matcher: EffectMatcher
  private let titleParser: TitleParser
  private let uniqueMatcher: UniqueRelicMatcher

  private let maxMainEffects = 3
  private let effectScoreFloor: Double = 0.45
  private let effectScoreAutoConfirm: Double = 0.70

  init(
    ocr: OCRService = OCRService(),
    matcher: EffectMatcher = EffectMatcher(),
    titleParser: TitleParser = TitleParser(),
    uniqueMatcher: UniqueRelicMatcher = UniqueRelicMatcher()
  ) {
    self.ocr = ocr
    self.matcher = matcher
    self.titleParser = titleParser
    self.uniqueMatcher = uniqueMatcher
  }

  func recognize(
    captured: CapturedRelic,
    mode: OCRMode = .accurate,
    languages: [String] = ["ja-JP", "en-US"]
  ) async throws -> RecognizedRelic {
    let image = captured.image.normalizedOrientation()
    let textImage = crop(image: image, normalized: captured.textRegionInImage) ?? image
    return try await recognize(image: image, ocrTarget: textImage, mode: mode, languages: languages)
  }

  func recognize(
    image: UIImage,
    mode: OCRMode = .accurate,
    languages: [String] = ["ja-JP", "en-US"],
    lineFilterROI: CGRect? = nil
  ) async throws -> RecognizedRelic {
    let normalized = image.normalizedOrientation()
    return try await recognize(image: normalized, ocrTarget: normalized,
                               mode: mode, languages: languages,
                               lineFilterROI: lineFilterROI)
  }

  // MARK: - 内部実装

  private func recognize(
    image: UIImage,
    ocrTarget: UIImage,
    mode: OCRMode,
    languages: [String],
    lineFilterROI: CGRect? = nil
  ) async throws -> RecognizedRelic {
    let allLines = try await ocr.recognizeLines(in: ocrTarget, mode: mode, languages: languages)
    // ROI フィルタ: bounding box の中心が ROI 内にある行だけ残す。
    // ROI は画像座標 (左上原点) で渡される。OCRLine の boundingBox は Vision 座標
    // (左下原点) なので、Y を flip して比較する。
    let lines: [OCRLine]
    if let roi = lineFilterROI {
      let visionROI = CGRect(x: roi.minX, y: 1.0 - roi.maxY,
                             width: roi.width, height: roi.height)
      lines = allLines.filter { line in
        let center = CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
        return visionROI.contains(center)
      }
    } else {
      lines = allLines
    }
    let topToBottom = lines.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }

    // 1） タイトル抽出 → depth が決まる
    let (title, titleLineId, titleCandidates) = extractTitle(from: topToBottom)
    let parsed = title.map { titleParser.parse($0) }
    let depth = parsed?.depth ?? .unknown

    // 2） スロット抽出（depth を考慮、デメリットは深層のみ採用）
    let slots = extractSlots(from: topToBottom, excludingTitleLineId: titleLineId, depth: depth)

    // 3） 固有遺物マッチ
    let uniqueMatch = matchUnique(title: title, lines: topToBottom)

    _ = image  // sourceImage は保持しない（詳細画面で使わなくなったため）
    return RecognizedRelic(
      title: title,
      parsedTitle: parsed,
      titleCandidates: titleCandidates,
      uniqueMatch: uniqueMatch,
      ocrLines: topToBottom,
      slots: slots
    )
  }

  /// 全OCR行 + 隣接2行の連結に TitleParser を当て、合計スコアが最高の候補を採用。
  /// 採用したラインのIDも返し、効果抽出時に除外できるようにする。
  private func extractTitle(
    from lines: [OCRLine]
  ) -> (title: String?, titleLineId: UUID?, candidates: [TitleCandidate]) {
    var candidates: [(text: String, parsed: ParsedRelicTitle, lineId: UUID?)] = []

    for line in lines {
      let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard t.count >= 2 else { continue }
      candidates.append((t, titleParser.parse(t), line.id))
    }
    for i in 0..<max(0, lines.count - 1) {
      let combined = (lines[i].text + lines[i + 1].text)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard combined.count >= 2 else { continue }
      candidates.append((combined, titleParser.parse(combined), nil))
    }

    let titleCandidates = candidates.map { TitleCandidate(text: $0.text, parsed: $0.parsed) }
      .sorted { $0.totalScore > $1.totalScore }
      .prefix(5)

    let sorted = candidates.sorted {
      $0.parsed.sizeScore + $0.parsed.colorScore + $0.parsed.depthScore
      > $1.parsed.sizeScore + $1.parsed.colorScore + $1.parsed.depthScore
    }

    if let best = sorted.first,
       best.parsed.sizeScore + best.parsed.colorScore + best.parsed.depthScore >= 1.0 {
      return (best.text, best.lineId, Array(titleCandidates))
    }
    let fallback = lines.first?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return (fallback, lines.first?.id, Array(titleCandidates))
  }

  /// OCR行を上から走査し、メイン効果と直下のデメリット効果をペアにする。
  ///
  /// 各位置で **連続する 1〜3 行を結合** して効果マスターと照合し、最高スコアの k を採用する。
  /// 同点なら長い k を優先 — ゲーム画面で1効果が2行に折り返されているケースをまとめて1スロットに
  /// 統合できる（例: "【葬儀屋】祈祷を使用して、自身に補助効果発生時" + "物理攻撃力上昇"）。
  /// デメリットは depth == .deep のときのみ採用。
  private func extractSlots(
    from lines: [OCRLine],
    excludingTitleLineId: UUID?,
    depth: RelicDepth
  ) -> [RecognizedSlot] {
    var slots: [RecognizedSlot] = []
    var pendingMain: RecognizedEffectLine?

    var i = 0
    while i < lines.count {
      // タイトルとして使われた行はスキップ
      if lines[i].id == excludingTitleLineId {
        i += 1
        continue
      }

      // 1〜3行の組み合わせを試す。
      // - 効果はゲーム画面で複数行に折り返されるケースがあるため、k=2/3 で
      //   **同じ効果** の raw score が高くなるなら採用する (折り返し効果の救済)。
      // - **違う効果** が長い k で勝つ場合は偶然のマッチである可能性が高いので
      //   閾値 (+0.10) を要求する (= 例: 隣の独立 effect が結合で混ざったケース)。
      // - 各行の OCR は Vision の上位3候補を持つので、行内の代替テキストも試す。
      var bestK = 0
      var bestRawScore = 0.0
      var bestCands: [EffectMatch] = []
      let maxLookahead = min(3, lines.count - i)
      let differentEffectThreshold = 0.10
      let maxCombinationsPerK = 12

      for k in 1...maxLookahead {
        // タイトル行を跨ぐ結合は行わない
        if k > 1, lines[i + k - 1].id == excludingTitleLineId {
          break
        }

        // 各行の OCR 候補テキスト一覧（主候補 + 代替） → 重複除去 + 最大3件
        let perLineCandidates: [[String]] = (i..<(i + k)).map { idx -> [String] in
          let line = lines[idx]
          let primary = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
          let alts = line.alternativeTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          var seen = Set<String>()
          var out: [String] = []
          for s in [primary] + alts where !s.isEmpty && !seen.contains(s) {
            seen.insert(s); out.append(s)
            if out.count >= 3 { break }
          }
          return out
        }
        // 直積で結合テキスト群を作る（上限あり）
        var combos: [String] = [""]
        for cands in perLineCandidates {
          combos = combos.flatMap { acc in cands.map { acc + $0 } }
          if combos.count > maxCombinationsPerK {
            combos = Array(combos.prefix(maxCombinationsPerK))
          }
        }

        // 全組み合わせを照合し、結果をマスター効果ID単位でデデュープ + 高スコア優先
        var pool: [String: EffectMatch] = [:]
        for combined in combos where combined.count >= 3 {
          let matches = matcher.topMatches(for: combined, limit: 3)
          for m in matches {
            if let prev = pool[m.effect.id], prev.score >= m.score { continue }
            pool[m.effect.id] = m
          }
        }
        let merged = pool.values.sorted { $0.score > $1.score }
        guard let top = merged.first else { continue }
        let raw = top.score

        // k > 1 の採用基準:
        //   - 直前の bestCands (これまで見つかった top 効果) と同じ効果なら raw が
        //     strict に高い時のみ更新 (= 折り返し効果がフルテキストでスコアアップしたケース)
        //   - 違う効果なら、偶然のマッチを排除するために +0.10 の差を要求する
        //     (ex: 0643 で k=3 が "持久カ+1睡眠耐性上昇" を結合して別 effect が
        //      0.600 を出すケース → k=1 の 0.591 を超えても 0.10 差なし → 不採用)
        let isImprovement: Bool
        if bestK == 0 {
          isImprovement = true
        } else if let cur = bestCands.first?.effect, top.effect.id == cur.id {
          isImprovement = raw > bestRawScore
        } else {
          isImprovement = raw >= bestRawScore + differentEffectThreshold
        }
        if isImprovement {
          bestRawScore = raw
          bestK = k
          // ピッカーで「鞭」を救えるよう、上位5件まで候補として残す
          bestCands = Array(merged.prefix(5))
        }
      }

      if bestK == 0 || bestRawScore < effectScoreFloor {
        i += 1
        continue
      }
      let bestScore = bestRawScore

      // 結合 OCR 行を合成
      let span = i..<(i + bestK)
      let combinedText = span
        .map { lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      let combinedBox = span.reduce(CGRect.null) { $0.union(lines[$1].boundingBox) }
      let combinedConfidence = span.map { lines[$0].confidence }
        .reduce(0, +) / Float(bestK)
      let synthesizedOCR = OCRLine(text: combinedText,
                                   alternativeTexts: [],
                                   boundingBox: combinedBox,
                                   confidence: combinedConfidence)
      let effectLine = RecognizedEffectLine(
        ocrLine: synthesizedOCR,
        candidates: bestCands,
        selected: bestScore >= effectScoreAutoConfirm ? bestCands.first : nil
      )

      if let topEffect = bestCands.first?.effect, topEffect.category == .demerits {
        // 深層のみ受け入れ、直前のメインに紐づけ
        if depth == .deep, let main = pendingMain {
          slots.append(RecognizedSlot(main: main, demerit: effectLine))
          pendingMain = nil
        }
        // それ以外はノイズとして無視
      } else {
        if let m = pendingMain {
          slots.append(RecognizedSlot(main: m, demerit: nil))
        }
        pendingMain = effectLine
        if slots.count >= maxMainEffects {
          pendingMain = nil
          break
        }
      }
      i += bestK
    }
    if let m = pendingMain, slots.count < maxMainEffects {
      slots.append(RecognizedSlot(main: m, demerit: nil))
    }
    return slots
  }

  private func matchUnique(title: String?, lines: [OCRLine]) -> UniqueRelicMatch? {
    var candidates: [String] = []
    if let title { candidates.append(title) }
    for line in lines.prefix(10) {
      let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { candidates.append(t) }
    }
    return uniqueMatcher.bestMatch(in: candidates)
  }

  private func crop(image: UIImage, normalized rect: CGRect) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let pixelRect = CGRect(
      x: rect.minX * w,
      y: rect.minY * h,
      width: rect.width * w,
      height: rect.height * h
    ).integral
    guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
    guard let cropped = cg.cropping(to: pixelRect) else { return nil }
    return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
  }
}
