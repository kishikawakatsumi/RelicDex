import Foundation
import UIKit
internal import Combine

/// カメラフレームを連続OCRし、認識結果が安定したら **自動的に確定する** （タップ不要）。
///
/// 設計ポイント：
/// - `current` は毎フレーム更新するので、UI には常に最新の認識テキストが反映される
/// - 確定時は内部の安定検出ウィンドウをリセットして、進捗バーが 0% から再カウント開始
/// - 直前に確定したフィンガープリントを覚えておき（`lastConfirmedFp`）、同じ内容では再確定しない
///  （= カーソルが同じ遺物に居る間は重複追加しない）
/// - 別の FP（or 無効フレーム） が来たらロックアウトを解除し、新しい遺物を通常通り検出
@MainActor
final class LiveScanViewModel: ObservableObject {
  @Published private(set) var current: RecognizedRelic?
  @Published private(set) var stabilityProgress: Double = 0.0
  @Published private(set) var isStable: Bool = false

  /// 確定時のコールバック（RelicCaptureView から購読）
  var onConfirm: ((RecognizedRelic) -> Void)?

  /// シート表示中などにフレーム処理を一時停止する
  var paused: Bool = false {
    didSet {
      if paused {
        resetStability()
      }
    }
  }

  private var cancellables = Set<AnyCancellable>()
  private let recognizer = RelicRecognizer()
  private var processing = false

  /// 直近の **粗い** FP 履歴（タイトル+色+スロット数のみ）。
  /// OCR で効果の選択が微妙にブレてもこの FP は安定しやすいので、
  /// プログレスが「50%で止まる」現象を避けつつ確定を早く判定できる。
  private var recentFingerprints: [String] = []
  private let stabilityWindow = 4
  private let stabilityNeeded = 3

  /// 最後に確定した遺物の **詳細 FP** （効果IDまで含む）。
  /// この FP と同じ内容のフレームが続く間は再確定しない（重複追加防止）。
  /// 異なる FP （空の無効フレーム含む） が来た時点でクリア = ロックアウト解除。
  private var lastConfirmedDetailedFp: String?

  /// 同じ遺物（粗 FP 一致） で「これまでで最も完全に認識できたフレーム」を保持する。
  /// OCR は反射やノイズで効果を 1 つ取りこぼすことがあり、その瞬間は `isValid` が
  /// false になって確定が起きない。過去フレームでフル読みできた回をキャッシュ
  /// することで、確定タイミングで完全版を使える。粗 FP が変わったとき / 確定 /
  /// pause 時に破棄する。
  private var bestRecognizedForCurrentFp: RecognizedRelic?

  /// OCR にかける認識言語の現在値。
  /// 初期値はユーザロケールを優先しつつフォールバックも入れた 2 言語、
  /// 1 度でも有効認識できたら、その時の言語に絞り込んで以降固定する。
  ///（Vision は言語数だけモデルを並列実行するので、絞ると ~2 倍速くなる）
  private var ocrLanguages: [String] = LiveScanViewModel.initialLanguages()
  /// `ocrLanguages` を 1 言語に固定済みかどうか
  private var ocrLanguageLocked = false

  /// 直近で **実際に OCR を回した** フレームの dHash と認識結果。
  /// 端末をスタンドに置いて画面が静止しているケースでは毎フレームほぼ同じ画像が
  /// 流れてくるので、ハッシュが近ければ OCR をスキップして前回結果を再利用する。
  ///（Hamming 距離 4 以下 = ほぼ同一とみなす）
  private var lastOCRFrameHash: UInt64?
  private var lastOCRResult: RecognizedRelic?

  private static func initialLanguages() -> [String] {
    // 初期は **単一の `ja-JP`** にする（多言語並列を意図的に避ける）。
    //
    // 多言語 `["ja-JP", "en-US"]` を指定すると Vision が両モデルを並列実行する
    // ため理論上はどちらの言語でも当たるはずだが、実機では英語ロケール下で
    // 日本語ゲーム画面の認識率が大きく落ちるケースが確認できた（推定: 言語
    // コンテキスト補正の干渉 + ロケール由来のシステム側設定が影響）。
    //
    // 一方 JA OCR モデルは Latin 文字も扱えるので、英語ゲーム画面に対しても
    // タイトル/効果文を概ね正しく読み取れる。マスタ照合（`EffectMatcher` /
    // `TitleParser` / `UniqueRelicMatcher`） は内部で JA・EN 両方のテキストに
    // Levenshtein で当たるため、OCR が片言語であっても両言語のゲーム画面に
    // マッチできる。
    //
    // 副次効果として、初期フェーズも 1 言語並列なのでロック前から高速。
    // 「英語ゲーム画面」の場合だけ、最初の有効認識後に CJK 判定で
    // `["en-US"]` に切り替えて純粋 Latin OCR の精度を取り戻す。
    return ["ja-JP"]
  }

  /// 確定直後にラベル/安定検出を「凍結」するデッドライン。
  /// この時刻までは新しいフレームの結果が来ても UI を上書きせず、
  /// 認識完了の状態をユーザーが落ち着いて確認できるようにする
  /// （カメラのブレで一瞬別の認識結果が出るのを抑止）。
  private var holdUntil: Date?
  /// 確定後の凍結時間。フラッシュの余韻（~0.45s） より少し長めに。
  private let confirmHoldDuration: TimeInterval = 0.8

  private var frameSize: RelicCaptureView.FrameSize = .compact
  private var guideAspect: CGFloat = 4.0

  var statusMessage: String {
    if paused { return String(localized: "Paused") }
    if isStable { return String(localized: "Recognized (added to candidates)") }
    guard let cur = current else { return String(localized: "Align the relic description with the yellow frame") }
    if !cur.isValid {
      if cur.isUnique || cur.parsedTitle?.isFullyResolved == true {
        return String(localized: "Reading effect text…")
      }
      return String(localized: "Fit the relic description title in the frame")
    }
    return String(localized: "Recognizing…")
  }

  func bind(
    camera: CameraCaptureService,
    frameSize: RelicCaptureView.FrameSize,
    guideAspect: CGFloat
  ) {
    self.frameSize = frameSize
    self.guideAspect = guideAspect
    cancellables.removeAll()
    camera.frameSubject
      .sink { [weak self] image in
        self?.process(frame: image)
      }
      .store(in: &cancellables)
  }

  func updateFrameSize(_ size: RelicCaptureView.FrameSize) {
    self.frameSize = size
    resetStability()
    lastConfirmedDetailedFp = nil
    // 切り出し範囲が変わるので過去の dHash を比較対象にできない
    lastOCRFrameHash = nil
    lastOCRResult = nil
  }

  private func resetStability() {
    recentFingerprints.removeAll()
    stabilityProgress = 0
    isStable = false
    bestRecognizedForCurrentFp = nil
  }

  private func process(frame: UIImage) {
    if paused || processing { return }
    let captured = makeCaptured(image: frame)

    // フレームハッシュで重複検知 → 静止フレームでは OCR を丸ごとスキップ。
    // dHash は 8x8 → 64bit、Hamming 距離 4 以下なら「ほぼ同じ画像」として再利用。
    if let frameHash = Self.computeDHash(of: frame, region: captured.textRegionInImage) {
      if let last = lastOCRFrameHash,
         (frameHash ^ last).nonzeroBitCount <= 4,
         let cached = lastOCRResult {
        // OCR は走らせず stability ウィンドウだけ進める（確定タイミングの基底になる）。
        Task { @MainActor in await self.update(with: cached) }
        return
      }
      // ハッシュは「OCR を実際に回したフレーム」のものだけを保持したいので、
      // この時点では更新せず、recognize 完了後に MainActor で書き込む。
      processing = true
      let recognizer = self.recognizer
      let languages = ocrLanguages
      Task.detached(priority: .userInitiated) { [weak self] in
        defer { Task { @MainActor in self?.processing = false } }
        do {
          let result = try await recognizer.recognize(captured: captured, mode: .live, languages: languages)
          await MainActor.run {
            self?.lastOCRFrameHash = frameHash
            self?.lastOCRResult = result
          }
          await self?.update(with: result)
        } catch {
          // フレーム単位の失敗は無視
        }
      }
      return
    }

    // ハッシュが取れなかった（= cgImage 取得失敗等のレアケース） は素直に OCR
    processing = true
    let recognizer = self.recognizer
    let languages = ocrLanguages
    Task.detached(priority: .userInitiated) { [weak self] in
      defer { Task { @MainActor in self?.processing = false } }
      do {
        let result = try await recognizer.recognize(captured: captured, mode: .live, languages: languages)
        await self?.update(with: result)
      } catch {
        // フレーム単位の失敗は無視
      }
    }
  }

  /// 8x8 grayscale 縮小して隣接ピクセル比較で 64bit dHash を作る。
  /// 微小な明度変化やわずかな手ぶれには非常に安定で、OCR の重複検出に十分。
  /// 計算コストはネイティブ ~1ms 以下。
  private static func computeDHash(of image: UIImage, region: CGRect) -> UInt64? {
    guard let cg = image.cgImage else { return nil }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let pixelRect = CGRect(
      x: floor(region.minX * w),
      y: floor(region.minY * h),
      width: max(1, floor(region.width * w)),
      height: max(1, floor(region.height * h))
    )
    guard let cropped = cg.cropping(to: pixelRect) else { return nil }
    guard let ctx = CGContext(
      data: nil,
      width: 9, height: 8,
      bitsPerComponent: 8,
      bytesPerRow: 9,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .low
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 9, height: 8))
    guard let data = ctx.data else { return nil }
    let pixels = data.assumingMemoryBound(to: UInt8.self)

    var hash: UInt64 = 0
    for y in 0..<8 {
      for x in 0..<8 {
        let left = pixels[y * 9 + x]
        let right = pixels[y * 9 + x + 1]
        hash = (hash << 1) | (left > right ? 1 : 0)
      }
    }
    return hash
  }

  private func makeCaptured(image: UIImage) -> CapturedRelic {
    let imageAspect = image.size.width / max(image.size.height, 1)
    let widthRatio: CGFloat = frameSize.widthRatio
    let heightRatio = widthRatio / guideAspect / imageAspect
    let x = (1.0 - widthRatio) / 2
    let y = (1.0 - heightRatio) / 2
    let rect = CGRect(x: x, y: max(0, y),
                      width: widthRatio,
                      height: max(0.05, heightRatio))
    return CapturedRelic(image: image, textRegionInImage: rect)
  }

  private func update(with result: RecognizedRelic) async {
    // ① 確定直後の凍結期間: 新しい認識結果でラベルを上書きしない。
    //    カメラのブレで別の認識が混じってもユーザーから見ると「完了状態」が保たれる。
    if let holdUntil, Date() < holdUntil {
      return
    }
    self.holdUntil = nil

    // 認識言語のロック: 一度でも `isValid` のフレームが取れたら、その認識結果の
    // タイトルから JA / EN を判定して 1 言語に絞り込む（= 以降の OCR が ~2 倍速く）。
    // 判定基準: タイトル文字列に CJK 範囲の文字が含まれていれば JA、なければ EN。
    if !ocrLanguageLocked, result.isValid, let title = result.title {
      let hasCJK = title.unicodeScalars.contains { $0.value >= 0x3000 }
      ocrLanguages = hasCJK ? ["ja-JP"] : ["en-US"]
      ocrLanguageLocked = true
    }

    // 粗 FP は isValid に依らず、タイトル+色+スロット数だけで判定する。
    // 効果が一瞬取りこぼされて isValid が false になっても、安定検出は title
    // 単位で進めたいため。
    let coarseFp = coarseFingerprint(of: result)

    // 同じ粗 FP の中で「直近の有効フレーム」を保持する。
    // 粗 FP が変わったらキャッシュを破棄。常に最新の有効フレームで上書きするので、
    // 確定の瞬間にユーザがライブで見ているテキスト（= 最新フレーム） と確定内容が
    // 食い違わない。最新が無効なフレームに飛んだ場合のみ、直前の有効フレームに
    // 退避してフリッカーを救う。
    if !coarseFp.isEmpty {
      if let prev = bestRecognizedForCurrentFp,
         coarseFingerprint(of: prev) != coarseFp {
        bestRecognizedForCurrentFp = nil
      }
      if result.isValid {
        bestRecognizedForCurrentFp = result
      }
    } else {
      bestRecognizedForCurrentFp = nil
    }

    // 確定対象: 最新フレームが有効ならそれをそのまま使う（= ライブ表示と完全一致）。
    // 最新が無効なときだけ、同じ粗 FP のキャッシュにフォールバックする
    // （効果のフリッカーで一瞬無効になっても確定できるよう）。
    let confirmCandidate: RecognizedRelic
    if result.isValid {
      confirmCandidate = result
    } else if let cached = bestRecognizedForCurrentFp,
              !coarseFp.isEmpty,
              coarseFingerprint(of: cached) == coarseFp {
      confirmCandidate = cached
    } else {
      confirmCandidate = result
    }
    let detailedFp = confirmCandidate.isValid
      ? detailedFingerprint(of: confirmCandidate)
      : ""

    // ② ロックアウト中: 直前に確定したのと同じ詳細 FP のフレームは何もしない。
    //    （カーソルがまだ同じ遺物に居る、ハプティック直後の残留フレーム等）
    //    ここで早期 return することで @Published の publish も走らず、
    //    SwiftUI の再評価コストを丸ごとスキップできる。
    if let lastFp = lastConfirmedDetailedFp {
      if detailedFp == lastFp {
        return
      }
      // 異なる FP （無効フレーム含む） が来たのでロックアウト解除
      lastConfirmedDetailedFp = nil
    }

    // ③ UI には最新の結果を反映（テキストはすぐ切り替わる）
    self.current = result

    // ④ 粗 FP で安定検出ウィンドウを更新（効果のブレに引きずられない）
    recentFingerprints.append(coarseFp)
    if recentFingerprints.count > stabilityWindow {
      recentFingerprints.removeFirst()
    }
    let valid = recentFingerprints.filter { !$0.isEmpty }
    let counts = Dictionary(grouping: valid, by: { $0 }).mapValues { $0.count }
    let topCount = counts.values.max() ?? 0
    let progress = min(1.0, Double(topCount) / Double(stabilityNeeded))
    let stable = topCount >= stabilityNeeded

    self.stabilityProgress = progress
    self.isStable = stable

    if stable, confirmCandidate.isValid, !detailedFp.isEmpty {
      // ⑤ 確定: 詳細 FP をロックアウト用に保存。安定履歴をリセットして次に備える
      lastConfirmedDetailedFp = detailedFp
      holdUntil = Date().addingTimeInterval(confirmHoldDuration)
      resetStability()
      // 同じ MainActor 関数内で self.current = result の publish 直後に onConfirm を
      // 呼ぶと、SwiftUI が再描画する前にハプティック/トーストが先に走ってしまい、
      // ユーザーから見ると「ラベルが古いまま確定」したように見える。
      // 1 フレーム待ってから発火することでラベル描画 → ハプティック の順序を保証する。
      let confirmed = confirmCandidate
      let callback = onConfirm
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000)  // ~50ms（3+ フレーム at 60Hz）
        callback?(confirmed)
      }
    }
  }

  /// 粗いフィンガープリント（タイトル+色+スロット数のみ）。
  /// 効果のマッチが微妙にブレても変化しないので、安定検出を素直に進められる。
  /// タイトルからは深度キーワード（景色/昏景） を除く: 「昏景」が「景色」に
  /// 誤読されたフレームでも同じ FP として扱い、安定検出を阻害しない。
  private func coarseFingerprint(of r: RecognizedRelic) -> String {
    if let unique = r.uniqueMatch?.relic.id { return "u:\(unique)" }
    let title = depthInvariantTitle(of: r)
    if title.isEmpty { return "" }
    return "n:\(title)|c:\(r.color.rawValue)|s:\(r.slotCount)"
  }

  /// 詳細フィンガープリント（効果IDまで含む）。再確定防止のロックアウト判定用。
  /// 同じくタイトルから深度キーワードを除き、深層効果（デメリット） も除外。
  /// → 同じ物理カードについて「景色 / 昏景」の判定がフレーム間で揺れても
  ///    1 つの確定として扱える。
  private func detailedFingerprint(of r: RecognizedRelic) -> String {
    if let unique = r.uniqueMatch?.relic.id { return "u:\(unique)" }
    let mainIds: [String] = r.slots.enumerated().map { (i, slot) in
      let mainId = slot.main.candidates.first?.effect.id ?? ""
      return "\(i):\(mainId)"
    }
    let title = depthInvariantTitle(of: r)
    return "n:\(title)|\(mainIds.joined(separator: ","))|c:\(r.color.rawValue)|s:\(r.slotCount)"
  }

  /// タイトルから深度キーワードを除いたベース名。
  /// JA: "端正な燃える昏景" / "端正な燃える景色" → "端正な燃える"
  /// EN: "Deep Polished Burning Scene" / "Polished Burning Scene" → "Polished Burning"
  /// `parsedTitle.canonical` は常に JA 形式なので JA 用キーワードで足りるが、
  /// 解析失敗時にフォールバックする `r.title` （生 OCR） は EN の可能性もあるので
  /// master の両言語キーワードをすべて除去する。
  private func depthInvariantTitle(of r: RecognizedRelic) -> String {
    var title = r.parsedTitle?.canonical ?? r.title ?? ""
    for d in MasterDataStore.shared.titleWords.depths {
      title = title.replacingOccurrences(of: d.ja, with: "")
      title = title.replacingOccurrences(of: d.en, with: "", options: .caseInsensitive)
      if let prefix = d.enPrefix {
        title = title.replacingOccurrences(of: prefix, with: "", options: .caseInsensitive)
      }
    }
    return title.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
