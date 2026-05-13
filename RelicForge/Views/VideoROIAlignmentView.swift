import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// 動画を背景にループ再生し、その上に **crop-box** 形式の ROI 矩形を重ねる。
/// 矩形は本体ドラッグで移動、四隅のハンドルでリサイズできる。
/// 自動検出された ROI があれば初期値として使い、無ければ画面中央寄りの妥当な初期矩形。
struct VideoROIAlignmentView: View {
  let videoURL: URL
  /// preferredTransform 適用後の動画実寸
  let videoSize: CGSize
  /// (roi, expectedCount) を返す。expectedCount は必須。
  let onConfirm: (CGRect, Int) -> Void
  let onCancel: () -> Void
  /// 自動検出された ROI。あれば初期値。
  var initialROI: CGRect? = nil

  @State private var roi: CGRect
  /// 確定済みの「遺物数」文字列。アラートで OK を押したときだけ更新される。
  /// スキャンボタンの enable 判定はこちらを見るので、アラート入力中はボタンが
  /// 反応しない。
  @State private var expectedCountText: String = ""
  /// アラート内 TextField の編集中ドラフト。OK で `expectedCountText` に commit。
  @State private var alertDraftText: String = ""
  @State private var showingExpectedAlert = false

  @State private var player: AVQueuePlayer = AVQueuePlayer()
  @State private var looper: AVPlayerLooper?

  init(
    videoURL: URL,
    videoSize: CGSize,
    onConfirm: @escaping (CGRect, Int) -> Void,
    onCancel: @escaping () -> Void,
    initialROI: CGRect? = nil
  ) {
    self.videoURL = videoURL
    self.videoSize = videoSize
    self.onConfirm = onConfirm
    self.onCancel = onCancel
    self.initialROI = initialROI
    self._roi = State(initialValue: Self.sanitize(initialROI))
  }

  /// 自動検出 ROI のサニタイズ。大きすぎる場合 (両パネル合算など) は安全な default に。
  private static func sanitize(_ roi: CGRect?) -> CGRect {
    let fallback = CGRect(x: 0.10, y: 0.60, width: 0.50, height: 0.25)
    guard let roi else { return fallback }
    // 動画の半分以上を占める ROI は誤検出の可能性が高い → fallback
    let area = roi.width * roi.height
    if area > 0.35 || roi.width > 0.8 || roi.height > 0.55 {
      return fallback
    }
    // 範囲内にクランプ
    let x = max(0, min(1, roi.minX))
    let y = max(0, min(1, roi.minY))
    let w = max(0.05, min(1 - x, roi.width))
    let h = max(0.05, min(1 - y, roi.height))
    return CGRect(x: x, y: y, width: w, height: h)
  }

  private var validExpectedCount: Int? {
    let trimmed = expectedCountText.trimmingCharacters(in: .whitespaces)
    guard let n = Int(trimmed), n > 0 else { return nil }
    return n
  }

  var body: some View {
    GeometryReader { geo in
      let fit = aspectFit(videoSize, in: geo.size)
      let videoTL = CGPoint(
        x: (geo.size.width - fit.width) / 2,
        y: (geo.size.height - fit.height) / 2
      )

      ZStack {
        Color.black.ignoresSafeArea()
        PlayerLayerView(player: player)
          .frame(width: fit.width, height: fit.height)

        CropBoxOverlay(
          roi: $roi,
          videoOrigin: videoTL,
          videoSize: fit,
          screenSize: geo.size
        )

        VStack(spacing: 12) {
          topBar
          expectedCountControl
          Spacer()
          recognizeButton
        }
      }
      .onAppear { setupPlayer() }
      .onDisappear { player.pause() }
      .alert("Number of relics", isPresented: $showingExpectedAlert) {
        TextField("e.g. 1931", text: $alertDraftText)
          .keyboardType(.numberPad)
        Button("Cancel", role: .cancel) {
          // Cancel は確定しない。次回開いたとき直前の確定値からやり直し。
          alertDraftText = expectedCountText
        }
        Button("OK") {
          // OK で初めて committed 値に反映する。
          expectedCountText = alertDraftText
        }
      } message: {
        Text("Enter the exact count of relics shown in the video. Required for accurate segmentation.")
      }
    }
  }

  // MARK: - Top bar (close + 説明バッジ)

  /// 左上に閉じるボタン (RelicCaptureView と同じ floating ✕ パターン)、中央に
  /// 操作ヘルプを置く。Recognize/Cancel が下にあると Cancel の位置が
  /// アプリの他のモーダル (top-left) と違って混乱するので、Cancel を上に移した。
  private var topBar: some View {
    ZStack {
      HStack {
        Button {
          onCancel()
        } label: {
          Image(systemName: "xmark")
            .font(.subheadline.weight(.semibold))
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.55), in: Circle())
            .foregroundStyle(.white)
        }
        Spacer()
      }
      Text("Adjust the box so the relic detail text fits inside.")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 56)  // ✕ ボタンに被らないよう左右に余白
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }

  // MARK: - 遺物数入力 (上部に配置)

  /// 「遺物の数」入力エリア。下に置くと見つけにくいので、help バブル直下に
  /// 置いて目に入りやすくする。Recognize ボタンと縦サイズを揃えるため
  /// `minHeight: 50` (= controlSize .large 相当) を指定。
  private var expectedCountControl: some View {
    Button {
      // アラートを開くときは現在の確定値を draft の初期値にする。
      alertDraftText = expectedCountText
      showingExpectedAlert = true
    } label: {
      HStack(spacing: 8) {
        Text("Number of relics")
          .foregroundStyle(.white)
          .font(.body.weight(.semibold))
        if validExpectedCount == nil {
          Text("Required")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.25), in: Capsule())
        }
        Spacer()
        Text(expectedCountText.isEmpty
             ? String(localized: "Tap to enter")
             : expectedCountText)
          .foregroundStyle(expectedCountText.isEmpty ? .white.opacity(0.6) : .white)
          .font(.body.monospacedDigit())
        Image(systemName: "chevron.right")
          .foregroundStyle(.white.opacity(0.7))
          .font(.footnote.weight(.semibold))
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 50)
      // help バブル (ultraThinMaterial) と差別化するため、不透明な暗色ベタを
      // 敷いて文字コントラストを確保する。Material 系は背景が明るいと白文字が
      // 沈むので、ビデオの上に重ねる場合は不向き。
      .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(.white.opacity(0.22), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
  }

  // MARK: - スキャン開始ボタン (下部)

  private var recognizeButton: some View {
    Button {
      guard let expected = validExpectedCount, !showingExpectedAlert else { return }
      onConfirm(roi, expected)
    } label: {
      Text("Scan")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    // 確定値がない、またはアラート編集中は無効。アラート編集中の
    // TextField 入力で「ボタンだけ enable に見える」混乱を避ける。
    .disabled(validExpectedCount == nil || showingExpectedAlert)
    .padding(.horizontal, 16)
    .padding(.bottom, 32)
  }

  // MARK: - Player

  private func setupPlayer() {
    let item = AVPlayerItem(url: videoURL)
    player.removeAllItems()
    player.insert(item, after: nil)
    looper = AVPlayerLooper(player: player, templateItem: item)
    player.isMuted = true
    player.play()
  }

  private func aspectFit(_ size: CGSize, in container: CGSize) -> CGSize {
    guard size.width > 0, size.height > 0 else { return container }
    let s = min(container.width / size.width, container.height / size.height)
    return CGSize(width: size.width * s, height: size.height * s)
  }
}

// MARK: - AVPlayerLayer ホスト

private struct PlayerLayerView: UIViewRepresentable {
  let player: AVQueuePlayer

  func makeUIView(context: Context) -> Hosting {
    let v = Hosting()
    v.player = player
    return v
  }
  func updateUIView(_ uiView: Hosting, context: Context) {
    if uiView.player !== player {
      uiView.player = player
    }
  }

  final class Hosting: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVQueuePlayer? {
      get { playerLayer.player as? AVQueuePlayer }
      set {
        playerLayer.player = newValue
        playerLayer.videoGravity = .resize
      }
    }
  }
}

// MARK: - Crop-box オーバーレイ

/// 動画上に重ねる調整可能な ROI 矩形。
/// - 矩形本体ドラッグで移動
/// - 四隅のハンドルでリサイズ
/// - 周辺はディムで覆い、矩形内はくり抜く
private struct CropBoxOverlay: View {
  @Binding var roi: CGRect   // 正規化 (動画内 0..1 top-left 原点)
  let videoOrigin: CGPoint   // 動画の画面上の TL 座標
  let videoSize: CGSize      // 動画の画面上のサイズ
  let screenSize: CGSize

  /// ドラッグ開始時の正規化 ROI を保持し、累積ドラッグで再計算する
  @State private var startROI: CGRect? = nil

  /// 矩形の最小サイズ (正規化座標で 5%)
  private let minSize: CGFloat = 0.05
  /// ハンドルの当たり判定サイズ
  private let handleHitSize: CGFloat = 44

  var body: some View {
    let r = screenRect()
    ZStack {
      // 周辺をディム + ROI 部分をくり抜き
      Path { p in
        p.addRect(CGRect(origin: .zero, size: screenSize))
        p.addRect(r)
      }
      .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
      .allowsHitTesting(false)

      // ROI 枠線
      Rectangle()
        .strokeBorder(Color.yellow, lineWidth: 2)
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(false)

      // 本体ドラッグ (移動)
      Color.clear
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .position(x: r.midX, y: r.midY)
        .gesture(bodyDragGesture)

      // 各辺ハンドル (片側だけリサイズ)
      edgeHandle(rect: r, edge: .top)
      edgeHandle(rect: r, edge: .bottom)
      edgeHandle(rect: r, edge: .left)
      edgeHandle(rect: r, edge: .right)

      // 四隅のハンドル (2 辺同時リサイズ)
      handle(at: CGPoint(x: r.minX, y: r.minY), corner: .tl)
      handle(at: CGPoint(x: r.maxX, y: r.minY), corner: .tr)
      handle(at: CGPoint(x: r.minX, y: r.maxY), corner: .bl)
      handle(at: CGPoint(x: r.maxX, y: r.maxY), corner: .br)
    }
    // 親 GeometryReader はセーフエリアを尊重した座標系なので、ここでも
    // ignoresSafeArea を付けない。付けると box 描画は画面 (0,0) 原点になる
    // のに対し videoOrigin は GR 原点 (= safe-area 内側) で計算されているため
    // 上方向に top-inset ぶんずれてしまう。
  }

  private enum Edge { case top, bottom, left, right }

  /// 辺ハンドル: 細長い透明領域 + 中央に視覚インジケータ。
  /// 当たり判定領域は corner ハンドルと重ならないよう、辺の中央 60% に絞る。
  @ViewBuilder
  private func edgeHandle(rect r: CGRect, edge: Edge) -> some View {
    let thickness: CGFloat = 28
    let inset: CGFloat = 22  // corner hit area とのオーバーラップを避ける
    switch edge {
    case .top:
      Color.clear
        .frame(width: max(0, r.width - 2 * inset), height: thickness)
        .contentShape(Rectangle())
        .position(x: r.midX, y: r.minY)
        .gesture(edgeDragGesture(edge: .top))
      Capsule().fill(Color.white.opacity(0.8))
        .frame(width: 24, height: 3)
        .position(x: r.midX, y: r.minY)
        .allowsHitTesting(false)
    case .bottom:
      Color.clear
        .frame(width: max(0, r.width - 2 * inset), height: thickness)
        .contentShape(Rectangle())
        .position(x: r.midX, y: r.maxY)
        .gesture(edgeDragGesture(edge: .bottom))
      Capsule().fill(Color.white.opacity(0.8))
        .frame(width: 24, height: 3)
        .position(x: r.midX, y: r.maxY)
        .allowsHitTesting(false)
    case .left:
      Color.clear
        .frame(width: thickness, height: max(0, r.height - 2 * inset))
        .contentShape(Rectangle())
        .position(x: r.minX, y: r.midY)
        .gesture(edgeDragGesture(edge: .left))
      Capsule().fill(Color.white.opacity(0.8))
        .frame(width: 3, height: 24)
        .position(x: r.minX, y: r.midY)
        .allowsHitTesting(false)
    case .right:
      Color.clear
        .frame(width: thickness, height: max(0, r.height - 2 * inset))
        .contentShape(Rectangle())
        .position(x: r.maxX, y: r.midY)
        .gesture(edgeDragGesture(edge: .right))
      Capsule().fill(Color.white.opacity(0.8))
        .frame(width: 3, height: 24)
        .position(x: r.maxX, y: r.midY)
        .allowsHitTesting(false)
    }
  }

  private func edgeDragGesture(edge: Edge) -> some Gesture {
    DragGesture()
      .onChanged { v in
        let start = startROI ?? roi
        if startROI == nil { startROI = roi }
        let dx = v.translation.width / videoSize.width
        let dy = v.translation.height / videoSize.height
        var minX = start.minX, minY = start.minY
        var maxX = start.maxX, maxY = start.maxY
        switch edge {
        case .top:    minY += dy
        case .bottom: maxY += dy
        case .left:   minX += dx
        case .right:  maxX += dx
        }
        let lx = max(0, min(1, min(minX, maxX)))
        let ly = max(0, min(1, min(minY, maxY)))
        let hx = max(0, min(1, max(minX, maxX)))
        let hy = max(0, min(1, max(minY, maxY)))
        var w = max(minSize, hx - lx)
        var h = max(minSize, hy - ly)
        if lx + w > 1 { w = 1 - lx }
        if ly + h > 1 { h = 1 - ly }
        roi = CGRect(x: lx, y: ly, width: w, height: h)
      }
      .onEnded { _ in startROI = nil }
  }

  // MARK: - 描画ヘルパー

  private func screenRect() -> CGRect {
    CGRect(
      x: videoOrigin.x + roi.minX * videoSize.width,
      y: videoOrigin.y + roi.minY * videoSize.height,
      width: roi.width * videoSize.width,
      height: roi.height * videoSize.height
    )
  }

  private func handle(at p: CGPoint, corner: Corner) -> some View {
    // 視覚は小さい円、当たり判定はそれより大きい透明矩形にする
    ZStack {
      Color.clear
        .frame(width: handleHitSize, height: handleHitSize)
      Circle()
        .fill(Color.white)
        .frame(width: 16, height: 16)
        .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
    }
    .contentShape(Rectangle())
    .position(p)
    .gesture(cornerDragGesture(corner: corner))
  }

  // MARK: - ジェスチャ

  private enum Corner { case tl, tr, bl, br }

  private var bodyDragGesture: some Gesture {
    DragGesture()
      .onChanged { v in
        let start = startROI ?? roi
        if startROI == nil { startROI = roi }
        let dx = v.translation.width / videoSize.width
        let dy = v.translation.height / videoSize.height
        var newX = start.minX + dx
        var newY = start.minY + dy
        newX = max(0, min(1 - start.width, newX))
        newY = max(0, min(1 - start.height, newY))
        roi = CGRect(x: newX, y: newY, width: start.width, height: start.height)
      }
      .onEnded { _ in startROI = nil }
  }

  private func cornerDragGesture(corner: Corner) -> some Gesture {
    DragGesture()
      .onChanged { v in
        let start = startROI ?? roi
        if startROI == nil { startROI = roi }
        let dx = v.translation.width / videoSize.width
        let dy = v.translation.height / videoSize.height
        roi = resize(start: start, by: CGSize(width: dx, height: dy), corner: corner)
      }
      .onEnded { _ in startROI = nil }
  }

  /// 指定コーナーを delta ドラッグしたあとの新しい正規化矩形。
  private func resize(start: CGRect, by delta: CGSize, corner: Corner) -> CGRect {
    var minX = start.minX
    var minY = start.minY
    var maxX = start.maxX
    var maxY = start.maxY
    switch corner {
    case .tl: minX += delta.width; minY += delta.height
    case .tr: maxX += delta.width; minY += delta.height
    case .bl: minX += delta.width; maxY += delta.height
    case .br: maxX += delta.width; maxY += delta.height
    }
    // 反転を許す: min/max を入れ替えて正規化
    let lo = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
    let hi = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
    // 動画矩形内にクランプ
    let lx = max(0, min(1, lo.x))
    let ly = max(0, min(1, lo.y))
    let hx = max(0, min(1, hi.x))
    let hy = max(0, min(1, hi.y))
    var w = hx - lx
    var h = hy - ly
    // 最小サイズを下回らない
    if w < minSize { w = minSize }
    if h < minSize { h = minSize }
    if lx + w > 1 { w = 1 - lx }
    if ly + h > 1 { h = 1 - ly }
    return CGRect(x: lx, y: ly, width: w, height: h)
  }
}
