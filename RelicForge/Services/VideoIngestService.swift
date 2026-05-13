import AVFoundation
import CoreGraphics
import Foundation
import UIKit

/// 動画ファイルから「カーソルが切り替わった瞬間」をピーク検出で見つけ、
/// 各セグメントの中央 frame を `RecognizedRelic` として yield する。
///
/// 動作の流れ:
///   1. samplingFPS で thumbnail を巡回し、左下の詳細パネルだけ比較して
///      フレーム間 diff の数列を作る
///   2. diff の **極大値**（= カーソルが次の遺物に切り替わった瞬間） を検出
///   3. ピークの間 = 1 つの遺物が表示されていたセグメント。中央の frame を
///      取り出して OCR する
///
/// 高速カーソル送り（1 遺物 4 フレーム前後） でも長さ 1 のセグメントを残せる。
final class VideoIngestService: @unchecked Sendable {

  /// 操作がタイムアウトしたとき投げる
  struct TimeoutError: Error {}

  /// 結果を一度だけ書き込めるアクター。withTimeout で
  /// op タスクと timeout タスクのどちらが先に完了したかを保持する。
  private actor TimeoutLatch<T: Sendable> {
    private var done: Result<T, Error>?
    private var continuation: CheckedContinuation<T, Error>?

    func complete(_ r: Result<T, Error>) {
      guard done == nil else { return }
      done = r
      if let c = continuation {
        continuation = nil
        switch r {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
      }
    }

    func value() async throws -> T {
      if let r = done { return try r.get() }
      return try await withCheckedThrowingContinuation { c in
        continuation = c
      }
    }
  }

  /// `seconds` 以内に `op` が完了しなければ TimeoutError を throw する。
  ///
  /// `withThrowingTaskGroup` を使う実装は **op が cooperative cancellation を
  /// 尊重しない場合に永久に待つ** バグがあった (TaskGroup は子タスク完了まで戻らない)。
  /// これを避けるため、専用 actor で「先に完了した結果」を取り出し、
  /// 戻り値を返した後 op タスクの完了は待たない構造に変更している。
  /// 副作用: op が hung した場合タスクが残り続ける (リソース消費は発生する) が、
  /// 呼び出し元はブロックされない。
  private static func withTimeout<T: Sendable>(
    _ seconds: Double,
    op: @Sendable @escaping () async throws -> T
  ) async throws -> T {
    let latch = TimeoutLatch<T>()
    let opTask = Task<Void, Never> {
      do {
        let r = try await op()
        await latch.complete(.success(r))
      } catch {
        await latch.complete(.failure(error))
      }
    }
    Task<Void, Never> {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      await latch.complete(.failure(TimeoutError()))
      opTask.cancel()
    }
    return try await latch.value()
  }

  enum Mode {
    /// 通常: ピーク検出 + 中央 frame OCR
    case full
    /// ピーク検出のみ。OCR をスキップして「いくつ区間が見つかったか」を確認
    case detectOnly
    /// ピーク検出も OCR もスキップし、`samplingFPS` で抽出した
    /// **全 frame** を順に出す。AVAssetImageGenerator の挙動を見るための debug 用。
    case sampleAll
  }

  struct Settings {
    var mode: Mode = .full
    /// frame 抽出 fps。元動画の fps（高速カーソル送りなら 60） 推奨。
    var samplingFPS: Double = 30.0
    /// ピーク（フレーム間 diff の極大値）と判定する最低高さ。
    /// この値を超えた極大値だけを「カーソルが次の遺物に動いた瞬間」とみなす。
    /// 0..255 の平均絶対差スケール。低すぎるとノイズで過分割、高すぎると取りこぼし。
    var peakMinHeight: Double = 4.0
    /// 隣り合うピーク間の最小フレーム数。短い場合は高い方を採用する。
    /// 1 = 隣接 peak を許す。expected を使うときは絞り込まれるので 1 で OK。
    var peakMinSpacing: Int = 1
    /// セグメント数の上限。指定すると、検出されたピークから「diff の高い順」に
    /// `expectedSegments - 1` 個だけ採用してこの数のセグメントに揃える。
    /// 動画内の遺物数が既知のときに使う。
    var expectedSegments: Int? = nil
    /// 差分計算用 thumbnail のサイズ（短辺ピクセル相当）
    var thumbMaxDimension: CGFloat = 540
    /// 詳細パネルが入っている領域（PIL 座標 = 左上原点、左/上/右/下 の 0..1）
    var panelROI = CGRect(x: 0.10, y: 0.65, width: 0.45, height: 0.15)
  }

  /// 検出パイプラインの内部統計。デバッグ用。
  struct Diagnostics {
    var sampledFrames: Int = 0
    var totalRuns: Int = 0   // 検出されたセグメント数
    var keptRuns: Int = 0    // expectedSegments 適用後のセグメント数
    var ocrSucceeded: Int = 0
    /// セグメントの中央 frame を full-res で取り出そうとして失敗した数
    var frameExtractFailed: Int = 0
    /// frame は取れたが OCR が throw した数
    var ocrFailed: Int = 0
    var firstFrameSize: CGSize = .zero
    /// diff 数列の統計（チューニング用）
    var diffMedian: Double = 0
    var diffP90: Double = 0
    var diffMax: Double = 0
  }

  enum Event {
    case scanning(progress: Double, currentSample: Int, totalSamples: Int)
    case detectedFrame(UIImage, sampleIndex: Int)
    /// `done` は完了済みセグメント数、`current` は「今処理中の (1-indexed) セグメント番号」。
    case ocrProgress(done: Int, total: Int, current: Int)
    /// - `frameImage`: 元 frame 全体の縮小サムネ (文脈確認用)
    /// - `ocrImage`: 実際に OCR に渡した ROI クロップ済み画像 (デバッグ用)
    case recognized(RecognizedRelic, frameImage: UIImage, ocrImage: UIImage)
    case diagnostics(Diagnostics)
    case finished(totalRecognized: Int)
    case failed(String)
  }

  private let recognizer: RelicRecognizer
  let settings: Settings

  init(recognizer: RelicRecognizer = RelicRecognizer(), settings: Settings = Settings()) {
    self.recognizer = recognizer
    self.settings = settings
  }

  func ingest(videoURL: URL) -> AsyncStream<Event> {
    AsyncStream { continuation in
      let task = Task {
        do {
          try await self.run(videoURL: videoURL, yield: { continuation.yield($0) })
        } catch is CancellationError {
        } catch {
          continuation.yield(.failed(error.localizedDescription))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  // MARK: - 実装

  private func run(videoURL: URL, yield: @escaping (Event) -> Void) async throws {
    let asset = AVURLAsset(url: videoURL)
    let duration = try await asset.load(.duration).seconds
    guard duration > 0 else {
      yield(.failed("動画の長さを取得できませんでした"))
      return
    }
    let totalSamples = max(1, Int(duration * settings.samplingFPS))

    // ── フェーズ 1: 全 frame を巡回し、隣接 diff の数列を作る ──────
    func makeThumbGen() -> AVAssetImageGenerator {
      let g = AVAssetImageGenerator(asset: asset)
      g.appliesPreferredTrackTransform = true
      // 59.94fps (PS5 等) で 1/60 sec のトレランスだと真ん中のフレームに当てるのが
      // 厳しすぎて何度もリトライ → 詰まる原因になる。1/20 sec まで緩める。
      g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
      g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
      g.maximumSize = CGSize(width: settings.thumbMaxDimension,
                             height: settings.thumbMaxDimension)
      return g
    }
    var thumbGen = makeThumbGen()

    var prevPanel: [UInt8]? = nil
    var diffs: [Double] = []
    /// diffs[k] が示す「frame index k+1」を逆引きするためのテーブル。
    /// 抽出失敗で skip した frame があった場合に整合させるために持つ。
    var sampleIndices: [Int] = []  // sampleIndices[k] = フレーム実 index for diffs[k+1] 側
    var diag = Diagnostics()
    /// 連続でハングする frame が来た場合の保険。ある程度の頻度で thumbGen を
    /// 作り直す。AVAssetImageGenerator は同一インスタンスで連続 seek を続けると
    /// -12785 などのエラー / ハング状態に陥る既知の挙動がある。
    let thumbRecreateEvery = 500

    for i in 0..<totalSamples {
      try Task.checkCancellation()
      if i > 0 && i % thumbRecreateEvery == 0 {
        thumbGen.cancelAllCGImageGeneration()
        thumbGen = makeThumbGen()
      }
      let t = CMTime(seconds: Double(i) / settings.samplingFPS, preferredTimescale: 60000)
      // タイムアウトなしの素の `image(at:)` だと、PS5 動画のように 1 frame の
      // seek でハングするケースがあり、ここで永久停止していた。
      let cg: CGImage
      do {
        let gen = thumbGen
        cg = try await Self.withTimeout(3) {
          try await gen.image(at: t).image
        }
      } catch {
        // タイムアウト or 取得失敗 → generator をリセットして次フレームへ
        thumbGen.cancelAllCGImageGeneration()
        thumbGen = makeThumbGen()
        continue
      }
      diag.sampledFrames += 1
      if diag.sampledFrames == 1 {
        diag.firstFrameSize = CGSize(width: cg.width, height: cg.height)
      }

      // sampleAll: そのまま emit して終わり
      if settings.mode == .sampleAll {
        let raw = UIImage(cgImage: cg)
        let img: UIImage
        if let jpeg = raw.jpegData(compressionQuality: 0.6),
           let decoded = UIImage(data: jpeg) {
          img = decoded
        } else {
          img = raw
        }
        yield(.detectedFrame(img, sampleIndex: i))
        if i % 30 == 0 {
          yield(.scanning(progress: Double(i) / Double(totalSamples),
                          currentSample: i, totalSamples: totalSamples))
        }
        continue
      }

      let panel = downsamplePanel(cg)
      if let prev = prevPanel {
        diffs.append(meanAbsDiff(prev, panel))
      }
      sampleIndices.append(i)
      prevPanel = panel

      // 10 サンプルおきに更新 (1.0/samplingFPS * 10 = ~0.17 sec at 60fps)。
      // PS5 動画は 1 サンプル抽出にも時間がかかるので、見た目の更新間隔は
      // 動画の長さに比例するが、少なくとも処理進行のフィードバックは残る。
      if i % 10 == 0 {
        yield(.scanning(progress: Double(i) / Double(totalSamples),
                        currentSample: i, totalSamples: totalSamples))
      }
    }
    yield(.scanning(progress: 1.0, currentSample: totalSamples, totalSamples: totalSamples))

    if settings.mode == .sampleAll {
      yield(.diagnostics(diag))
      yield(.finished(totalRecognized: 0))
      return
    }

    // diff 数列の分布をログに残す
    if !diffs.isEmpty {
      let sorted = diffs.sorted()
      diag.diffMedian = sorted[sorted.count / 2]
      diag.diffP90 = sorted[Int(Double(sorted.count) * 0.9)]
      diag.diffMax = sorted.last ?? 0
    }

    // ── フェーズ 2: ピーク検出 ──────────────────────────────────
    // expectedSegments が指定されたら minHeight を 0 にして「全 local maxima」を集める。
    // そこから diff 降順で expected-1 個を採る。動画内の遺物数が分かっている前提で
    // diff の絶対値に依存しない最も robust な方法。
    var peakIndices: [Int]
    if let expected = settings.expectedSegments {
      let allMaxima = findPeaks(diffs,
                                minHeight: 0,
                                minSpacing: settings.peakMinSpacing)
      let sortedByHeight = allMaxima.sorted { diffs[$0] > diffs[$1] }
      peakIndices = Array(sortedByHeight.prefix(max(0, expected - 1))).sorted()
    } else {
      peakIndices = findPeaks(diffs,
                              minHeight: settings.peakMinHeight,
                              minSpacing: settings.peakMinSpacing)
    }

    // ── フェーズ 3: ピーク間をセグメントとして切り出す ───────────
    // peak が diffs[k] にあるとき、それは「sampleIndices[k] と sampleIndices[k+1] の境界」。
    // つまり次のセグメントは sampleIndices[k+1] から開始。
    var segments: [(start: Int, end: Int)] = []  // sampleIndices 上の [start, end)
    var segStart = 0
    for p in peakIndices {
      let boundary = p + 1
      segments.append((segStart, boundary))
      segStart = boundary
    }
    segments.append((segStart, sampleIndices.count))

    diag.totalRuns = segments.count
    diag.keptRuns = segments.count
    yield(.diagnostics(diag))

    // ── フェーズ 4: 各セグメントの中央 frame を full-res で取り出す ──
    // tolerance はフェーズ 1 と揃えて NTSC 系のフレーム精度ずれを吸収する。
    var fullGen = makeFullGenerator(asset: asset)

    var done = 0
    let recreateEvery = 20  // -12785 対策で予防的に作り直す
    for (idx, seg) in segments.enumerated() {
      try Task.checkCancellation()
      guard seg.end > seg.start else { continue }
      if idx > 0 && idx % recreateEvery == 0 {
        // 古い generator の pending request を明示的にキャンセルしておく。
        // withTimeout は hung task を放置するので、放っておくと「タイムアウト
        // で先に進んだのに古い generator がリソースを掴んだまま」という状態が
        // 累積して新しい generator もスタックする原因になる。
        fullGen.cancelAllCGImageGeneration()
        fullGen = makeFullGenerator(asset: asset)
      }
      // セグメント開始の signal。done は据え置きで current だけ進める。
      // PS5 動画のように 1 セグメントに何秒もかかるケースで、UI 上「止まったように
      // 見える」のを防ぐためのハートビート。
      yield(.ocrProgress(done: done, total: segments.count, current: idx + 1))
      try await processSegment(
        seg: seg,
        sampleIndices: sampleIndices,
        asset: asset,
        generator: &fullGen,
        diag: &diag,
        yield: yield
      )
      done += 1
      yield(.ocrProgress(done: done, total: segments.count, current: idx + 1))
      if idx % 25 == 0 {
        print("[VideoIngest] processed segment \(idx + 1)/\(segments.count)")
      }
    }
    yield(.diagnostics(diag))
    yield(.finished(totalRecognized: done))
  }

  private func makeFullGenerator(asset: AVAsset) -> AVAssetImageGenerator {
    let g = AVAssetImageGenerator(asset: asset)
    g.appliesPreferredTrackTransform = true
    g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
    g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
    return g
  }

  /// 1 セグメントの中央 frame を取り出して OCR/yield する処理を別関数に切り出すことで、
  /// 大きな UIImage を local 変数に閉じ込めて、関数を抜けた時点で確実に解放する。
  /// セグメント内の **複数フレームを OCR して最初に valid 判定になったものを採用** する。
  /// valid が出なければ「最初に成功した OCR」を yield (= 従来通りの中央フレーム結果)。
  /// 中央 → ±1 → ±2 ... の順で試すので、stable なセグメントは中央 1 回で抜ける。
  /// Mid-update 等で valid にならないセグメントだけ追加 OCR 時間がかかる。
  private func processSegment(
    seg: (start: Int, end: Int),
    sampleIndices: [Int],
    asset: AVAsset,
    generator: inout AVAssetImageGenerator,
    diag: inout Diagnostics,
    yield: (Event) -> Void
  ) async throws {
    if settings.mode == .full {
      let positions = candidatePositions(in: seg)
      var firstAttempt: (RecognizedRelic, UIImage, UIImage)?

      for pos in positions {
        try Task.checkCancellation()
        let safeIdx = min(pos, sampleIndices.count - 1)
        let frameIndex = sampleIndices[safeIdx]
        guard let result = try await tryFrameRecognize(
          frameIndex: frameIndex,
          asset: asset,
          generator: &generator,
          diag: &diag
        ) else { continue }

        if firstAttempt == nil {
          firstAttempt = result
        }
        if result.0.isValid {
          diag.ocrSucceeded += 1
          yield(.recognized(result.0, frameImage: result.1, ocrImage: result.2))
          return
        }
      }
      // どの位置でも valid が出なかった → 最初の成功例を Needs review 候補として yield
      if let (recognized, thumb, ocrImg) = firstAttempt {
        diag.ocrSucceeded += 1
        yield(.recognized(recognized, frameImage: thumb, ocrImage: ocrImg))
      }
    } else if settings.mode == .detectOnly {
      let mid = (seg.start + seg.end) / 2
      let safeIdx = min(mid, sampleIndices.count - 1)
      let frameIndex = sampleIndices[safeIdx]
      let t = CMTime(seconds: Double(frameIndex) / settings.samplingFPS, preferredTimescale: 60000)
      let genCopy = generator
      let cgImage: CGImage
      do {
        cgImage = try await Self.withTimeout(5) {
          try await genCopy.image(at: t).image
        }
      } catch {
        diag.frameExtractFailed += 1
        generator.cancelAllCGImageGeneration()
        generator = makeFullGenerator(asset: asset)
        return
      }
      let ui = UIImage(cgImage: cgImage)
      let thumb = makeThumbnailJPEG(ui, maxDim: 240)
      yield(.detectedFrame(thumb, sampleIndex: frameIndex))
    }
  }

  /// 1 frame の取り出し + OCR を実行。失敗時は nil。
  /// 戻り値: (認識結果, full frame サムネ, OCR に渡したクロップ画像のサムネ)
  private func tryFrameRecognize(
    frameIndex: Int,
    asset: AVAsset,
    generator: inout AVAssetImageGenerator,
    diag: inout Diagnostics
  ) async throws -> (RecognizedRelic, UIImage, UIImage)? {
    let t = CMTime(seconds: Double(frameIndex) / settings.samplingFPS, preferredTimescale: 60000)
    let genCopy = generator
    let cgImage: CGImage
    do {
      cgImage = try await Self.withTimeout(5) {
        try await genCopy.image(at: t).image
      }
    } catch {
      diag.frameExtractFailed += 1
      generator.cancelAllCGImageGeneration()
      generator = makeFullGenerator(asset: asset)
      return nil
    }
    // OCR は ROI に限定する。PS5 横置き動画のように画面に詳細パネルが複数
    // 写っているケースで、ROI 外 (= 反対側のパネル) の文字が混ざるのを防ぐ。
    // 縮小サムネは「文脈確認」のために full frame のまま残し、修正画面で
    // どの遺物を見ているか分かるようにする。OCR に渡したクロップ画像も
    // デバッグ確認用に縮小して返す。
    let ocrCG = croppedToPanelROI(cgImage)
    let ocrImage = UIImage(cgImage: ocrCG)
    let thumbSource = UIImage(cgImage: cgImage)
    do {
      let recCapture = recognizer
      let recognized = try await Self.withTimeout(8) {
        try await recCapture.recognize(image: ocrImage)
      }
      let trimmed = trimGhostEffects(recognized)
      let thumb = makeThumbnailJPEG(thumbSource, maxDim: 256)
      // OCR クロップ画像は元の解像度に近い方が文字を読み取りやすいので
      // 短辺 maxDim を大きめにしておく。
      let ocrThumb = makeThumbnailJPEG(ocrImage, maxDim: 512)
      return (trimmed, thumb, ocrThumb)
    } catch {
      diag.ocrFailed += 1
      return nil
    }
  }

  /// `settings.panelROI` で示される領域だけを切り出した `CGImage` を返す。
  /// ROI が画像外/0 サイズの場合は元画像をそのまま返す。
  private func croppedToPanelROI(_ cg: CGImage) -> CGImage {
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let r = settings.panelROI
    let rect = CGRect(x: r.minX * w, y: r.minY * h,
                      width: r.width * w, height: r.height * h).integral
    guard rect.width >= 1, rect.height >= 1,
          let cropped = cg.cropping(to: rect)
    else { return cg }
    return cropped
  }

  /// パネル UI が「直前 relic の効果文字を薄く残したまま」次の relic を表示する
  /// ケースの post-process。 Title の slot 数 (parsed) よりも検出 slot 数が多い場合、
  /// 上から `parsed.slotCount` 個だけを採用し、残骸の effect を捨てる。
  ///
  /// 適用条件:
  ///   - 固有遺物ではない
  ///   - Title が 3 要素 (size/color/depth) すべて解決済
  ///   - パース slot 数 ≥ 1
  ///   - 検出 slot 数 > パース slot 数
  ///
  /// 例: title "端正な滴る景色" (slot 2) で 3 effects 検出 → 上 2 個を採用
  private func trimGhostEffects(_ r: RecognizedRelic) -> RecognizedRelic {
    guard !r.isUnique,
          let parsed = r.parsedTitle,
          parsed.isFullyResolved,
          parsed.slotCount > 0,
          r.slots.count > parsed.slotCount
    else { return r }
    return RecognizedRelic(
      title: r.title,
      parsedTitle: r.parsedTitle,
      titleCandidates: r.titleCandidates,
      uniqueMatch: r.uniqueMatch,
      ocrLines: r.ocrLines,
      slots: Array(r.slots.prefix(parsed.slotCount))
    )
  }

  /// セグメント内で OCR を試すフレーム位置のリストを返す。
  /// 中央 → ±1 → ±2 → ±3 の順で、segment 内に収まる位置だけ重複なく集める。
  private func candidatePositions(in seg: (start: Int, end: Int)) -> [Int] {
    let len = seg.end - seg.start
    guard len >= 1 else { return [seg.start] }
    if len == 1 { return [seg.start] }
    let mid = (seg.start + seg.end) / 2
    var positions = [mid]
    for offset in 1..<min(3, len) {
      let lower = mid - offset
      let upper = mid + offset
      if lower >= seg.start, !positions.contains(lower) { positions.append(lower) }
      if upper < seg.end, !positions.contains(upper) { positions.append(upper) }
    }
    return positions
  }

  /// UIImage を `maxDim` の長辺サイズに縮小して JPEG にエンコード、
  /// その data から再構築した data-backed `UIImage` を返す。
  /// 数千個保持しても問題ない程度（1 個 ~10-30KB） に圧縮される。
  private func makeThumbnailJPEG(_ source: UIImage, maxDim: CGFloat) -> UIImage {
    let size = source.size
    guard size.width > 0, size.height > 0 else { return source }
    let scale = min(maxDim / size.width, maxDim / size.height, 1.0)
    let target: UIImage
    if scale < 1.0 {
      let newSize = CGSize(width: size.width * scale, height: size.height * scale)
      target = UIGraphicsImageRenderer(size: newSize).image { _ in
        source.draw(in: CGRect(origin: .zero, size: newSize))
      }
    } else {
      target = source
    }
    if let data = target.jpegData(compressionQuality: 0.6),
       let decoded = UIImage(data: data) {
      return decoded
    }
    return target
  }

  // MARK: - ピーク検出

  /// `values` から **strict な極大値** の index を抽出する。
  /// - 立ち上がり後に下降に転じた瞬間を「極大」と判定（plateaus にも対応）
  /// - `minHeight` 未満は無視
  /// - 直前のピークから `minSpacing` 未満の場合は「高い方を残す」
  private func findPeaks(_ values: [Double], minHeight: Double, minSpacing: Int) -> [Int] {
    guard values.count >= 3 else { return [] }
    var peaks: [Int] = []
    var rising = false
    for i in 1..<values.count {
      if values[i] > values[i - 1] {
        rising = true
      } else if rising && values[i] < values[i - 1] {
        let candidate = i - 1
        if values[candidate] > minHeight {
          if let last = peaks.last, candidate - last < minSpacing {
            // 近すぎる場合は高い方を採用
            if values[candidate] > values[last] {
              peaks[peaks.count - 1] = candidate
            }
          } else {
            peaks.append(candidate)
          }
        }
        rising = false
      }
    }
    return peaks
  }

  // MARK: - フレーム抽出

  private func image(at time: CMTime, generator: AVAssetImageGenerator) async throws -> CGImage? {
    let result = try await generator.image(at: time)
    return result.image
  }

  /// `image(at:)` が失敗したら generator を作り直して 1 回リトライする。
  /// AVAssetImageGenerator は同一インスタンスで連続 seek していると
  /// `-12785` (謎エラー) を返すようになる既知の挙動があり、このリトライで救う。
  private func imageWithRetry(
    at time: CMTime,
    asset: AVAsset,
    generator: inout AVAssetImageGenerator
  ) async throws -> CGImage {
    do {
      let result = try await generator.image(at: time)
      return result.image
    } catch {
      // generator を作り直して 1 回だけリトライ
      generator.cancelAllCGImageGeneration()
      generator = makeFullGenerator(asset: asset)
      let result = try await generator.image(at: time)
      return result.image
    }
  }

  // MARK: - 詳細パネルだけ取り出して 96×32 のグレースケール bytes に縮小

  private func downsamplePanel(_ cg: CGImage) -> [UInt8] {
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let r = settings.panelROI
    let panelRect = CGRect(x: r.minX * w, y: r.minY * h,
                           width: r.width * w, height: r.height * h).integral
    guard panelRect.width >= 1, panelRect.height >= 1,
          let cropped = cg.cropping(to: panelRect)
    else { return [UInt8](repeating: 0, count: 96 * 32) }
    let outW = 96, outH = 32
    var bytes = [UInt8](repeating: 0, count: outW * outH)
    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(data: &bytes,
                              width: outW, height: outH,
                              bitsPerComponent: 8,
                              bytesPerRow: outW,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return bytes }
    ctx.interpolationQuality = .low
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return bytes
  }

  private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    let n = min(a.count, b.count)
    if n == 0 { return 0 }
    var sum = 0
    for i in 0..<n {
      let d = Int(a[i]) - Int(b[i])
      sum += d >= 0 ? d : -d
    }
    return Double(sum) / Double(n)
  }
}
