import AVKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 動画から複数の遺物を一括取り込みするプロトタイプ画面。
///
/// 1) PhotosPicker または Files から動画を選ぶ
/// 2) `VideoIngestService` が静止区間を検出し、各区間を OCR
/// 3) 取り込み候補リストを表示。`isValid` のものだけ「一括インポート」可能
struct VideoIngestView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var allRelics: [StoredRelic]
  @Query private var allBuilds: [StoredBuild]

  /// 取り込み時の動作。
  /// - `replace`: 既存の遺物を全て削除してから新しい候補を保存する。動画 1 本で
  ///   セーブデータ全体を取り直すのが想定の主用途なので default はこちら。
  /// - `append`: 既存に追加するだけ。差分撮影に使う。
  enum ImportMode: Hashable { case replace, append }
  @State private var importMode: ImportMode = .replace
  @State private var showingReplaceConfirm = false

  @State private var pickerItem: PhotosPickerItem?
  @State private var isShowingFilePicker = false
  @State private var videoURL: URL?
  @State private var videoSize: CGSize?
  @State private var videoNominalFPS: Double = 60
  @State private var showingAlignment = false
  @State private var configuredROI: CGRect?
  @State private var isProcessing = false
  @State private var scanProgress: Double = 0
  @State private var scanCurrentSample: Int = 0
  @State private var scanTotalSamples: Int = 0
  @State private var ocrTotal: Int = 0
  @State private var ocrDone: Int = 0
  @State private var ocrCurrent: Int = 0
  @State private var errorMessage: String?
  @State private var candidates: [Candidate] = []
  @State private var detectedFrames: [DetectedFrame] = []
  @State private var ingestMode: VideoIngestService.Mode = .full
  @State private var ingestTask: Task<Void, Never>?
  @State private var diagnostics: VideoIngestService.Diagnostics?

  private struct DetectedFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let sampleIndex: Int
  }

  private struct Candidate: Identifiable {
    let id = UUID()
    let recognized: RecognizedRelic
    let frameImage: UIImage
    /// 実際に OCR に渡したクロップ済み画像 (ROI 内のみ)。
    /// 認識結果が期待と違うときに「何が読まれたか」を確認するためのデバッグ用画像。
    let ocrImage: UIImage
    var include: Bool
    /// 効果の手動編集状態。初期値は OCR 認識結果。
    /// 編集後は finalSlots() を使って Import 時に反映される。
    var edits: CandidateEdits
    // タイトル属性の override (CandidateEditorView で編集可能)。
    // 初期値は OCR の認識結果。Import 時は recognized ではなくこれらを使う。
    var color: RelicColor
    var slotCount: Int
    var depth: RelicDepth
    var uniqueId: String?

    init(recognized: RecognizedRelic, frameImage: UIImage, ocrImage: UIImage, include: Bool) {
      self.recognized = recognized
      self.frameImage = frameImage
      self.ocrImage = ocrImage
      self.include = include
      self.color = recognized.color
      self.slotCount = recognized.slotCount
      self.depth = recognized.depth
      self.uniqueId = recognized.uniqueMatch?.relic.id
      // OCR で取れた効果数が title の slotCount に足りない場合に備えて、
      // edits を slotCount に揃えてから保持する (詳細は CandidateEdits.resize)。
      var e = CandidateEdits(from: recognized)
      e.resize(to: max(1, recognized.slotCount))
      self.edits = e
    }

    var finalSlots: [ResolvedSlot] {
      edits.apply()
    }

    /// override 値から組み立てた display name。
    /// 行表示や editor のタイトルで使う。
    var displayName: String {
      let ja = recognized.isJapaneseScan
      if let uid = uniqueId {
        return MasterDataStore.shared.relicName(
          slotCount: slotCount, color: color, depth: .unknown,
          uniqueId: uid, forJapanese: ja
        )
      }
      return MasterDataStore.shared.relicName(
        slotCount: slotCount, color: color, depth: depth, forJapanese: ja
      )
    }

    /// ユーザー編集後の状態で「保存に必要な情報が揃っているか」を判定する。
    /// section 分け (Needs review / Ready to import) や Import 可否に使う。
    /// `recognized.isValid` と違って **edits/override を見る**ので、
    /// 編集で修正済みのものは valid 扱いになる。
    var effectiveIsValid: Bool {
      if uniqueId != nil { return true }
      guard color != .unknown, depth != .unknown, slotCount > 0 else { return false }
      guard edits.mains.count >= slotCount else { return false }
      guard edits.mains.prefix(slotCount).allSatisfy({ $0 != nil }) else { return false }
      if depth == .normal {
        return edits.demerits.prefix(slotCount).allSatisfy({ $0 == nil })
      }
      return true
    }
  }

  /// 編集画面に渡す候補 ID
  private struct EditingWrapper: Identifiable {
    let id: UUID
  }
  @State private var editingWrapper: EditingWrapper?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Add from Video")
        .navigationBarTitleDisplayMode(.inline)
        // スワイプでの dismiss は常に無効。状況によって挙動が変わると分かりにくい
        // ので、画面を閉じるには必ず Close ボタンを押す。
        .interactiveDismissDisabled()
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close") {
              ingestTask?.cancel()
              dismiss()
            }
          }
        }
        .onChange(of: pickerItem) { _, item in
          guard let item else { return }
          loadFromPhotosItem(item)
          // PhotosPicker は前回の選択を覚えていて、次回開いたとき同じ写真が
          // 「選択中」状態で表示される。そのまま同じ写真をタップすると
          // 「選択解除 → picker 自動 dismiss」になり何も起きなくなる。
          // 消費したら明示的に nil に戻して、毎回まっさらな状態で開かせる。
          pickerItem = nil
        }
        .fileImporter(isPresented: $isShowingFilePicker,
                      allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
          switch result {
          case .success(let url): loadVideo(url: url)
          case .failure(let err): errorMessage = err.localizedDescription
          }
        }
        .fullScreenCover(isPresented: $showingAlignment) {
          if let url = videoURL, let size = videoSize {
            VideoROIAlignmentView(
              videoURL: url,
              videoSize: size,
              onConfirm: { roi, expected in
                showingAlignment = false
                configuredROI = roi
                ingestMode = .full
                startIngest(url: url, roi: roi, fps: videoNominalFPS, expected: expected)
              },
              onCancel: {
                showingAlignment = false
                videoURL = nil
                videoSize = nil
              },
              initialROI: nil
            )
          }
        }
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var content: some View {
    if videoURL == nil && candidates.isEmpty && detectedFrames.isEmpty {
      pickerSection
    } else if isProcessing {
      progressSection
    } else if ingestMode != .full && !detectedFrames.isEmpty {
      detectedFramesGrid
    } else if !candidates.isEmpty {
      VStack(spacing: 0) {
        resultsList
        saveBar
      }
    } else {
      ContentUnavailableView(
        "No frames detected",
        systemImage: "questionmark.video",
        description: Text("Try a video where each relic is held for ≥ 0.3 sec, or re-align the ROI.")
      )
    }
  }

  private var pickerSection: some View {
    VStack(spacing: 24) {
      Image(systemName: "film.stack")
        .font(.system(size: 56))
        .foregroundStyle(.tint)
      VStack(spacing: 6) {
        Text("Import relics from video")
          .font(.title3.weight(.semibold))
        Text("Pan slowly across the relic list, holding each relic for ≥ 0.3 sec.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal)
      VStack(spacing: 12) {
        PhotosPicker(selection: $pickerItem, matching: .videos) {
          Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        Button {
          isShowingFilePicker = true
        } label: {
          Label("Choose from Files", systemImage: "folder")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
      .padding(.horizontal, 32)
      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .padding(.horizontal)
      }
      Spacer()
    }
    .padding(.top, 48)
  }

  private var progressSection: some View {
    VStack(spacing: 28) {
      Spacer()
      Image(systemName: "wand.and.stars")
        .font(.system(size: 48))
        .symbolEffect(.pulse, options: .repeating)
        .foregroundStyle(.tint)
      VStack(spacing: 12) {
        Text(progressLabel)
          .font(.headline.monospacedDigit())
        ProgressView(value: combinedProgress)
          .progressViewStyle(.linear)
          .tint(.accentColor)
          .padding(.horizontal, 40)
        Text("\(Int(combinedProgress * 100))%")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      if !candidates.isEmpty {
        VStack(spacing: 4) {
          Text("\(candidates.count)")
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
          Text("relic candidate(s) so far")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Button(role: .destructive) {
        ingestTask?.cancel()
      } label: {
        Label("Cancel", systemImage: "stop.circle")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
    }
  }

  private var detectedFramesGrid: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        // ヘッダ統計
        VStack(alignment: .leading, spacing: 4) {
          Text(ingestMode == .sampleAll
               ? "\(detectedFrames.count) frames sampled"
               : "\(detectedFrames.count) stable frames detected")
            .font(.headline)
          if let d = diagnostics {
            Text(String(format: """
            Frames sampled: %d
            Segments (peak detection): %d
            Diff median / p90 / max: %.2f / %.2f / %.2f
            First frame: %d×%d
            """,
              d.sampledFrames,
              d.keptRuns,
              d.diffMedian, d.diffP90, d.diffMax,
              Int(d.firstFrameSize.width), Int(d.firstFrameSize.height)
            ))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal)

        let cols = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
          ForEach(detectedFrames) { f in
            VStack(spacing: 2) {
              Image(uiImage: f.image)
                .resizable()
                .aspectRatio(9/16, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .cornerRadius(6)
              Text("#\(f.sampleIndex)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
      }
    }
  }

  private var resultsList: some View {
    let invalidCandidates = candidates.filter { !$0.effectiveIsValid }
    let validCandidates = candidates.filter { $0.effectiveIsValid }
    return List {
      summarySection
      if !invalidCandidates.isEmpty {
        Section {
          ForEach(invalidCandidates) { c in
            invalidCandidateRow(c)
              .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
          }
        } header: {
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text("Needs review")
            Spacer()
            Text("\(invalidCandidates.count)")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        } footer: {
          Text("Tap an image to view it full screen. These could not be auto-imported.")
            .font(.caption2)
        }
      }
      if !validCandidates.isEmpty {
        Section {
          ForEach(validCandidates) { c in
            validCandidateRow(c)
          }
        } header: {
          HStack {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text("Ready to import")
            Spacer()
            Text("\(validCandidates.count)")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .fullScreenCover(item: $editingWrapper) { editing in
      if let candidate = candidates.first(where: { $0.id == editing.id }) {
        CandidateEditorView(
          input: CandidateEditorView.Input(
            title: candidate.displayName,
            recognized: candidate.recognized,
            frameImage: candidate.frameImage,
            ocrImage: candidate.ocrImage,
            initialEdits: candidate.edits,
            initialIsSelected: candidate.include,
            reason: candidate.recognized.isValid ? nil : invalidReason(for: candidate.recognized)
          ),
          onSave: { newEdits, newSelected, newColor, newSlotCount, newDepth, newUniqueId in
            if let idx = candidates.firstIndex(where: { $0.id == editing.id }) {
              candidates[idx].edits = newEdits
              candidates[idx].include = newSelected
              candidates[idx].color = newColor
              candidates[idx].slotCount = newSlotCount
              candidates[idx].depth = newDepth
              candidates[idx].uniqueId = newUniqueId
            }
            editingWrapper = nil
          },
          onCancel: {
            editingWrapper = nil
          }
        )
      }
    }
  }

  private var summarySection: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          Text("\(includedCount)")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.tint)
          Text("/ \(candidates.count) selected")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
        }
        HStack(spacing: 8) {
          Button {
            for idx in candidates.indices where candidates[idx].recognized.isValid {
              candidates[idx].include = true
            }
          } label: {
            Label("Select all", systemImage: "checkmark.circle")
              .font(.caption)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          Button {
            for idx in candidates.indices {
              candidates[idx].include = false
            }
          } label: {
            Label("Deselect", systemImage: "circle")
              .font(.caption)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      }
      .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
    }
  }

  // インデックス管理を避けるため、トグルは id 経由で binding する。
  private func includeBinding(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { candidates.first(where: { $0.id == id })?.include ?? false },
      set: { newValue in
        if let idx = candidates.firstIndex(where: { $0.id == id }) {
          candidates[idx].include = newValue
        }
      }
    )
  }

  private func validCandidateRow(_ c: Candidate) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(uiImage: c.frameImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 4) {
        Text(c.displayName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        ForEach(Array(c.finalSlots.enumerated()), id: \.offset) { _, slot in
          if let main = slot.main {
            // スキャン元の言語に合わせて表示 (タイトルも同様)。
            Text("• \(main.text(forJapanese: c.recognized.isJapaneseScan))")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
      Spacer()
      includeToggleIcon(for: c)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      editingWrapper = EditingWrapper(id: c.id)
    }
  }

  /// 選択トグル (タップで include 反転)。行タップとの混同を避けるため独自の onTapGesture。
  private func includeToggleIcon(for c: Candidate) -> some View {
    let on = candidates.first(where: { $0.id == c.id })?.include == true
    return Image(systemName: on ? "checkmark.circle.fill" : "circle")
      .font(.title3)
      .foregroundStyle(on ? Color.accentColor : .secondary)
      .frame(width: 32, height: 32)
      .contentShape(Rectangle())
      .onTapGesture {
        includeBinding(for: c.id).wrappedValue.toggle()
      }
  }

  /// "Needs review" 行: 大きな画像 + 失敗理由 + 現在の編集状態。
  /// タップで CandidateEditorView を開く。
  private func invalidCandidateRow(_ c: Candidate) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(uiImage: c.frameImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
      HStack(alignment: .center, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(invalidReason(for: c.recognized))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.orange)
        Spacer()
        includeToggleIcon(for: c)
      }
      // 現在の (編集後の) タイトル + 効果を表示
      HStack(spacing: 6) {
        if c.color != .unknown {
          Circle().fill(c.color.swatch).frame(width: 10, height: 10)
        }
        Text(c.displayName)
          .font(.headline)
      }
      ForEach(Array(c.finalSlots.enumerated()), id: \.offset) { _, slot in
        if let main = slot.main {
          Text("• \(main.text(forJapanese: c.recognized.isJapaneseScan))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else {
          Text("• (not set)")
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
      Text("Tap to fix this entry")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      editingWrapper = EditingWrapper(id: c.id)
    }
  }

  private func invalidReason(for r: RecognizedRelic) -> String {
    if r.isUnique { return String(localized: "OK (unique)") }
    guard let p = r.parsedTitle, p.isFullyResolved else {
      return String(localized: "Title not fully parsed")
    }
    if p.slotCount == 0 { return String(localized: "Slot count not detected") }
    if r.slots.count != p.slotCount {
      return String(localized: "Effects \(r.slots.count) / expected \(p.slotCount)")
    }
    if p.depth == .normal && r.slots.contains(where: { $0.demerit != nil }) {
      return String(localized: "Demerit on a normal relic")
    }
    return String(localized: "Unknown reason")
  }

  // MARK: - Helpers

  private var combinedProgress: Double {
    if ocrTotal > 0 {
      return 0.5 + 0.5 * Double(ocrDone) / Double(ocrTotal)
    }
    return 0.5 * scanProgress
  }

  private var progressLabel: String {
    if ocrTotal > 0 {
      var s = String(localized: "Scanning \(ocrDone) / \(ocrTotal)")
      // 「今 N 番目を処理中」の補足だけ付ける。完了数が同じでも、現在処理中の
      // 番号は前進するので「止まったように」見えるのを防げる。
      if ocrCurrent > ocrDone {
        s += " · " + String(localized: "working on #\(ocrCurrent)")
      }
      return s
    }
    if scanTotalSamples > 0 {
      return String(localized: "Scanning frame \(scanCurrentSample) / \(scanTotalSamples) (\(Int(scanProgress * 100))%)")
    }
    return String(localized: "Scanning frames \(Int(scanProgress * 100))%")
  }

  private var includedCount: Int { candidates.filter { $0.include }.count }

  private func thumbnail(for image: UIImage) -> UIImage {
    let target = CGSize(width: 128, height: 128)
    return UIGraphicsImageRenderer(size: target).image { _ in
      let size = image.size
      let scale = max(target.width / size.width, target.height / size.height)
      let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
      let origin = CGPoint(x: (target.width - drawSize.width) / 2,
                           y: (target.height - drawSize.height) / 2)
      image.draw(in: CGRect(origin: origin, size: drawSize))
    }
  }

  // MARK: - Loading

  private func loadFromPhotosItem(_ item: PhotosPickerItem) {
    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else { return }
        let url = URL.temporaryDirectory.appending(path: "ingest_\(UUID().uuidString).mov")
        try data.write(to: url)
        loadVideo(url: url)
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription }
      }
    }
  }

  /// 動画のメタデータ（preferredTransform 適用後のサイズ） を読み、
  /// ROI 位置合わせ画面に遷移する。
  private func loadVideo(url: URL) {
    Task {
      let asset = AVURLAsset(url: url)
      do {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
          await MainActor.run { errorMessage = "No video track" }
          return
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominalFPS = try await track.load(.nominalFrameRate)
        let transformed = natural.applying(transform)
        let size = CGSize(
          width: abs(transformed.width),
          height: abs(transformed.height)
        )
        await MainActor.run {
          videoURL = url
          videoSize = size
          videoNominalFPS = nominalFPS > 0 ? Double(nominalFPS) : 60
          showingAlignment = true
        }
      } catch {
        await MainActor.run { errorMessage = error.localizedDescription }
      }
    }
  }

  private func startIngest(url: URL, roi: CGRect, fps: Double, expected: Int?) {
    let mode: VideoIngestService.Mode = .full
    isProcessing = true
    candidates.removeAll()
    detectedFrames.removeAll()
    diagnostics = nil
    scanProgress = 0
    scanCurrentSample = 0
    scanTotalSamples = 0
    ocrTotal = 0
    ocrDone = 0
    ocrCurrent = 0
    errorMessage = nil
    // 長時間処理中に画面ロックされないように
    UIApplication.shared.isIdleTimerDisabled = true
    var settings = VideoIngestService.Settings()
    settings.panelROI = roi
    settings.mode = mode
    settings.samplingFPS = fps
    settings.expectedSegments = expected
    if mode == .sampleAll {
      // sampleAll は thumbnail を全部メモリに乗せるので 240px に縮小
      settings.thumbMaxDimension = 240
    }
    let service = VideoIngestService(settings: settings)
    ingestTask?.cancel()
    ingestTask = Task {
      for await event in service.ingest(videoURL: url) {
        await MainActor.run {
          handle(event)
        }
      }
      await MainActor.run {
        isProcessing = false
        UIApplication.shared.isIdleTimerDisabled = false
      }
    }
  }

  private func handle(_ event: VideoIngestService.Event) {
    switch event {
    case .scanning(let p, let cur, let total):
      scanProgress = p
      scanCurrentSample = cur
      scanTotalSamples = total
    case .ocrProgress(let d, let t, let cur):
      ocrDone = d
      ocrTotal = t
      ocrCurrent = cur
    case .detectedFrame(let img, let idx):
      detectedFrames.append(DetectedFrame(image: img, sampleIndex: idx))
    case .recognized(let r, let img, let ocrImg):
      candidates.append(Candidate(recognized: r,
                                  frameImage: img,
                                  ocrImage: ocrImg,
                                  include: r.isValid))
    case .diagnostics(let d):
      diagnostics = d
    case .finished:
      break
    case .failed(let msg):
      errorMessage = msg
    }
  }

  // MARK: - 保存バー (画面下部)

  /// 画面下部に固定する保存バー。Camera scan の `ScanCandidatesView` と同じ
  /// 構造で、左に「Replace / Append」のセグメント、右に Save ボタン。
  private var saveBar: some View {
    VStack(spacing: 0) {
      Divider()
      VStack(alignment: .leading, spacing: 10) {
        Picker("Import mode", selection: $importMode) {
          Text("Replace all").tag(ImportMode.replace)
          Text("Append").tag(ImportMode.append)
        }
        .pickerStyle(.segmented)

        HStack(alignment: .firstTextBaseline) {
          Text(importMode == .replace
               ? String(localized: "Existing: \(allRelics.count) → \(includedCount)")
               : String(localized: "Will add \(includedCount) to \(allRelics.count) existing"))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
          Spacer()
          Button {
            attemptSave()
          } label: {
            Text(importMode == .replace
                 ? String(localized: "Replace with \(includedCount)")
                 : String(localized: "Save \(includedCount)"))
              .monospacedDigit()
              .frame(minWidth: 160)
          }
          .buttonStyle(.borderedProminent)
          .disabled(includedCount == 0)
        }
      }
      .padding()
      .background(.ultraThinMaterial)
    }
    .alert("Replace all relics?", isPresented: $showingReplaceConfirm) {
      Button("Replace", role: .destructive) { performSave() }
      Button("Cancel", role: .cancel) {}
    } message: {
      let buildRefs = allBuilds.reduce(0) { acc, b in
        acc + allRelics.filter { b.uses(relicId: $0.id) }.count
      }
      if buildRefs > 0 {
        Text("\(allRelics.count) existing relics will be deleted and replaced with \(includedCount) new ones. \(buildRefs) build slot(s) currently reference relics that will be deleted.")
      } else {
        Text("\(allRelics.count) existing relics will be deleted and replaced with \(includedCount) new ones.")
      }
    }
  }

  // MARK: - Import

  private func attemptSave() {
    if importMode == .replace && !allRelics.isEmpty {
      showingReplaceConfirm = true
    } else {
      performSave()
    }
  }

  private func performSave() {
    if importMode == .replace {
      for relic in allRelics { modelContext.delete(relic) }
      try? modelContext.save()
    }
    let repo = RelicRepository(context: modelContext)
    var saved = 0
    for c in candidates where c.include {
      // override されたタイトル属性 + 編集を反映した最終スロットを使う
      repo.save(
        color: c.color,
        slotCount: c.slotCount,
        depth: c.depth,
        uniqueId: c.uniqueId,
        slots: c.finalSlots
      )
      saved += 1
    }
    if saved > 0 {
      dismiss()
    }
  }
}
