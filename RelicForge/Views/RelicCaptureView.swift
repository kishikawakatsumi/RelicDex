import SwiftUI
import SwiftData
import AVFoundation
import AudioToolbox
import UIKit
internal import Combine

/// ライブスキャン式キャプチャビュー（連続スキャン + 候補リスト方式）。
/// カメラを遺物詳細カードにかざす → 認識が安定すると自動的に候補リストに追加。
/// 候補リストは📋ボタンで一覧表示、選択した分だけ最後にまとめて保存する。
struct RelicCaptureView: View {
  /// シート/フルスクリーンとして提示されたときの閉じる動作。
  /// タブ直下で使うときは nil にすると ✕ ボタンが消える（タブ切り替えで離脱できるため）。
  var onClose: (() -> Void)? = nil

  private let guideAspect: CGFloat = 3.6  // width / height （やや縦に広く）

  @Environment(\.modelContext) private var modelContext
  @StateObject private var camera = CameraCaptureService()
  @StateObject private var live = LiveScanViewModel()
  @StateObject private var session = ScanSession()
  @State private var frameSize: FrameSize = .expanded

  @State private var showingCandidates = false
  @State private var showingDiscardConfirm = false
  /// 確定直後のフィードバック。ガイド枠近くにバッジ + カードの緑パルスを出す。
  @State private var confirmedFlash = false
  @State private var confirmedName: String = ""
  @State private var confirmedFlashTask: Task<Void, Never>?
  /// このスキャン画面で 1 回でも確定が成功したか。
  /// 初回確定までは案内テキスト/ステータスを表示し、操作に慣れたユーザー向けに
  /// 確定後はそれらを隠して画面を簡潔にする。
  @State private var hasConfirmedOnce = false

  /// スキャン画面の使い方説明（初回のみ自動表示）。`@AppStorage` で永続化し、
  /// 一度閉じたら次回以降は出さない。
  @AppStorage("relicforge.scan.howToSeen.v1") private var howToSeen = false
  @State private var showingHowTo = false

  /// 認識完了時の音（端末をスタンドに立てて使う想定でデフォルト ON）。
  /// silent スイッチ時の挙動はシステム音（`AudioServicesPlaySystemSound`） に従う。
  @AppStorage("relicforge.scan.soundEnabled.v1") private var soundEnabled = true

  enum FrameSize: Int, CaseIterable {
    case compact = 0
    case expanded = 1
    var widthRatio: CGFloat {
      switch self {
      case .compact:  0.72
      case .expanded: 0.95
      }
    }
    var nextLabel: String {
      switch self {
      case .compact:  String(localized: "To Wide")
      case .expanded: String(localized: "To Compact")
      }
    }
    func toggled() -> FrameSize {
      self == .compact ? .expanded : .compact
    }
  }

  var body: some View {
    ZStack {
#if targetEnvironment(simulator)
      // シミュレータには実カメラが無い: サンプル画像を背景に敷いて、その上に
      // 通常の認識オーバーレイ（黄色枠 / ステータス / 候補リスト） を載せる。
      // App Store 用スクショ撮影に使用。
      if let stub = CameraCaptureService.stubImage {
        Image(uiImage: stub)
          .resizable()
          .scaledToFill()
          .ignoresSafeArea()
      } else {
        Color.black.ignoresSafeArea()
      }
#else
      CameraPreviewView(session: camera.session)
        .ignoresSafeArea()
#endif

      GeometryReader { geo in
        let frame = guideFrame(in: geo.size, size: frameSize)
        ZStack(alignment: .topLeading) {
          Rectangle()
            .fill(.black.opacity(0.55))
            .mask {
              Rectangle()
                .overlay(
                  Rectangle()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .blendMode(.destinationOut)
                )
                .compositingGroup()
            }
          // 控えめな白枠: 認識中は半透明白、安定/確定時のみ緑にする。
          // 黄色のような派手な色を常に出さないことで、ゲーム画面の色味を邪魔しない。
          RoundedRectangle(cornerRadius: 6)
            .stroke(confirmedFlash ? Color.green.opacity(0.85)
                    : (live.isStable ? Color.green.opacity(0.85)
                       : Color.white.opacity(0.65)),
                    lineWidth: 1.5)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(.easeInOut(duration: 0.2), value: frameSize)
            .animation(.easeInOut(duration: 0.2), value: live.isStable)
            .animation(.easeOut(duration: 0.35), value: confirmedFlash)
          // 起動直後の案内: 初回確定までは表示し、以降は隠す
          // （認識中にすぐ消えると体感的に瞬間表示になってしまうため）。
          if !hasConfirmedOnce {
            Text("Aim the camera at the relic description")
              .font(.caption.weight(.medium))
              .foregroundStyle(.white.opacity(0.85))
              .position(x: frame.midX, y: frame.minY - 12)
              .transition(.opacity)
          }
          // 認識結果カードはガイド枠のすぐ下に配置。
          if let result = live.current {
            LiveResultCard(result: result, isStable: live.isStable, confirmed: confirmedFlash)
              .padding(.horizontal, 16)
              .frame(width: geo.size.width)
              .offset(y: frame.maxY + 12)
              .transition(.opacity)
          }
          // 確定フィードバック: ガイド枠の上にバッジをフェード表示。
          // ガイド枠とは重ねず、必ず枠の上側に配置する。
          HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text(confirmedName).lineLimit(1)
          }
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(.green.opacity(0.92), in: Capsule())
          .foregroundStyle(.white)
          .frame(maxWidth: geo.size.width - 32)
          .frame(width: geo.size.width, alignment: .center)
          .offset(y: frame.minY - 36)
          .opacity(confirmedFlash ? 1 : 0)
          .animation(.easeInOut(duration: 0.25), value: confirmedFlash)
          .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: hasConfirmedOnce)
      }
      .ignoresSafeArea()

      VStack {
        topBar
        Spacer()
        bottomBar
      }

      if case .denied = camera.state { deniedOverlay }

      if showingHowTo { howToOverlay }
    }
    .onAppear {
      camera.start()
      live.bind(camera: camera, frameSize: frameSize, guideAspect: guideAspect)
      live.onConfirm = { [weak session] result in
        handleAutoConfirm(result, into: session)
      }
      // スキャン中は画面が触られないので自動スリープを抑止する
      UIApplication.shared.isIdleTimerDisabled = true
      // 初回のみ使い方ガイドを自動表示
      if !howToSeen { showingHowTo = true }
    }
    .onDisappear {
      confirmedFlashTask?.cancel()
      camera.stop()
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .onChange(of: frameSize) { _, newValue in
      live.updateFrameSize(newValue)
    }
    .onChange(of: showingCandidates) { _, isShown in
      // シート表示中はライブスキャン処理を止めて、戻ったら再開
      live.paused = isShown
    }
    .onChange(of: showingHowTo) { _, isShown in
      // 使い方ガイド表示中もライブスキャンは止める（CPU 節約 + 認識通知が裏で起きないように）
      live.paused = isShown
    }
    .sheet(isPresented: $showingCandidates) {
      ScanCandidatesView(session: session)
    }
  }

  // MARK: - 上部 / 下部バー

  @ViewBuilder
  private var topBar: some View {
    HStack {
      // タブ直下利用時（onClose == nil） は ✕ ボタンを出さない
      if let onClose {
        Button {
          if session.candidates.isEmpty {
            onClose()
          } else {
            showingDiscardConfirm = true
          }
        } label: {
          Image(systemName: "xmark")
            .font(.subheadline.weight(.semibold))
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.55), in: Circle())
            .foregroundStyle(.white)
        }
        .alert("\(session.count) candidates pending", isPresented: $showingDiscardConfirm) {
          Button("Discard and Close", role: .destructive) {
            session.clear()
            onClose()
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Unsaved candidates will be discarded. Continue?")
        }
      }
      Spacer()
      // 認識完了時の音 ON/OFF （スタンド利用時に役立つ）
      Button {
        soundEnabled.toggle()
      } label: {
        Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
          .font(.subheadline.weight(.semibold))
          .frame(width: 32, height: 32)
          .background(.black.opacity(0.55), in: Circle())
          .foregroundStyle(.white)
      }
      // 使い方ボタン: 初回以降に再表示したいとき用
      Button {
        showingHowTo = true
      } label: {
        Image(systemName: "questionmark")
          .font(.subheadline.weight(.semibold))
          .frame(width: 32, height: 32)
          .background(.black.opacity(0.55), in: Circle())
          .foregroundStyle(.white)
      }
    }
    .padding()
  }

  /// 初回 / `?` ボタン押下時に被せる使い方ガイド。半透明の暗幕の上に
  /// カード状の説明を中央寄せで出す。OK で閉じると `howToSeen = true` で永続化。
  @ViewBuilder
  private var howToOverlay: some View {
    ZStack {
      Color.black.opacity(0.7).ignoresSafeArea()
        .onTapGesture { dismissHowTo() }
      VStack(alignment: .leading, spacing: 16) {
        Text("How to Scan")
          .font(.title2.weight(.bold))
        ScanIllustration()
          .frame(height: 150)
          .frame(maxWidth: .infinity)
        VStack(alignment: .leading, spacing: 12) {
          howToStep(number: 1, text: "Aim the camera at the relic detail panel (lower-right of the Relic Rites screen).")
          howToStep(number: 2, text: "Hold steady — recognized relics are added to candidates.")
          howToStep(number: 3, text: "Tap the tray icon to review and save.")
        }
        Button {
          dismissHowTo()
        } label: {
          Text("Got it")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .padding(.top, 4)
      }
      .padding(20)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      .padding(.horizontal, 24)
      .frame(maxWidth: 420)
    }
    .transition(.opacity)
  }

  private func howToStep(number: Int, text: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.weight(.bold).monospacedDigit())
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Color.accentColor, in: Circle())
      Text(text)
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func dismissHowTo() {
    withAnimation(.easeOut(duration: 0.2)) { showingHowTo = false }
    howToSeen = true
  }

  @ViewBuilder
  private var bottomBar: some View {
    // バッジが上にはみ出す分も含めて、認識ラベルと十分な間隔を確保する
    VStack(spacing: 22) {
      // ステータスメッセージも初回確定までは案内として表示し、以降は隠す。
      if !hasConfirmedOnce {
        Text(live.statusMessage)
          .font(.callout.weight(.medium))
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.black.opacity(0.55), in: Capsule())
          .transition(.opacity)
      }

      // 候補一覧: カプセル + 件数バッジ
      Button {
        showingCandidates = true
      } label: {
        Image(systemName: "tray.full.fill")
          .font(.title3.weight(.semibold))
          .padding(.horizontal, 28).padding(.vertical, 14)
          .background(.black.opacity(0.55), in: Capsule())
          .foregroundStyle(.white)
          .overlay(alignment: .topTrailing) {
            if session.count > 0 {
              Text("\(session.count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color.accentColor, in: Capsule())
                .overlay(Capsule().stroke(.black.opacity(0.4), lineWidth: 1))
                .offset(x: 6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
          }
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: session.count)
      }
      .disabled(session.count == 0)
    }
    .padding(.bottom, 28)
    .animation(.easeInOut(duration: 0.25), value: hasConfirmedOnce)
  }

  private var deniedOverlay: some View {
    VStack(spacing: 12) {
      Text("Camera access is denied").font(.headline)
      Text("Please allow camera access from Settings.")
        .font(.callout).foregroundStyle(.secondary)
      if let onClose {
        Button("Close", action: onClose).buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }

  // MARK: - 自動確定処理

  private func handleAutoConfirm(_ result: RecognizedRelic, into session: ScanSession?) {
    guard let session else { return }
    session.add(result)
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    if soundEnabled {
      // 1057 = Tink.caf。短く控えめだが認識完了が分かるシステム音。
      // silent スイッチ ON なら鳴らない（= ユーザの設定に従う）。
      AudioServicesPlaySystemSound(1057)
    }
    triggerConfirmedFlash(name: result.displayName)
    if !hasConfirmedOnce { hasConfirmedOnce = true }
  }

  private func triggerConfirmedFlash(name: String) {
    confirmedFlashTask?.cancel()
    // フラッシュ中は recognize を止めて main を解放し、アニメーションを滑らかにする。
    live.paused = true
    confirmedName = name
    confirmedFlash = true
    confirmedFlashTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      confirmedFlash = false
      // フェードアウトを終えてから recognize を再開。ただしトレイ / How-to が
      // 開かれていればそちらが pause を握り続けるべきなので、ここでは触らない。
      try? await Task.sleep(nanoseconds: 300_000_000)
      if !showingCandidates && !showingHowTo {
        live.paused = false
      }
    }
  }

  // MARK: - レイアウト

  private func guideFrame(in container: CGSize, size: FrameSize) -> CGRect {
    let isLandscape = container.width > container.height
    let longSide = max(container.width, container.height)
    let frameW: CGFloat = (isLandscape ? longSide : container.width) * size.widthRatio
    let frameH = frameW / guideAspect
    let x = (container.width - frameW) / 2
    let y = (container.height - frameH) / 2
    return CGRect(x: x, y: y, width: frameW, height: frameH)
  }
}

/// ライブ認識結果のサマリ（画面下に常時表示）
struct LiveResultCard: View {
  let result: RecognizedRelic
  let isStable: Bool
  /// 確定直後の強調表示（緑枠パルス）
  var confirmed: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Circle()
          .fill(result.color.swatch)
          .frame(width: 14, height: 14)
        Text(result.displayName)
          .font(.headline).lineLimit(1)
        if result.isUnique {
          Text("Unique")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.purple.opacity(0.25), in: Capsule())
            .foregroundStyle(.purple)
        }
        if result.depth == .deep {
          Text("Deep")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.indigo.opacity(0.4), in: Capsule())
            .foregroundStyle(.white)
        }
        Spacer()
        Text("◆ \(result.slotCount)").font(.caption.weight(.semibold).monospacedDigit())
      }
      ForEach(result.resolvedSlots) { slot in
        VStack(alignment: .leading, spacing: 4) {
          if let main = slot.main {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(Image(systemName: "circle.fill"))
                .font(.system(size: 5))
                .baselineOffset(3)
                .foregroundStyle(.white.opacity(0.6))
              Text(main.text(forJapanese: result.isJapaneseScan))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          if let demerit = slot.demerit {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(Image(systemName: "circle.fill"))
                .font(.system(size: 5))
                .baselineOffset(3)
                .foregroundStyle(Color.demeritEffectOnCameraOverlay)
              Text(demerit.text(forJapanese: result.isJapaneseScan))
                .font(.caption2)
                .foregroundStyle(Color.demeritEffectOnCameraOverlay)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
          }
        }
      }
    }
    .padding(12)
    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.green.opacity(confirmed ? 0.7 : 0), lineWidth: 1.5)
        .animation(.easeOut(duration: 0.35), value: confirmed)
    )
    .foregroundStyle(.white)
  }
}

/// 使い方ガイドの図解: 左に iPhone、右に TV （ゲーム画面）。
/// TV 内部はゲームの遺物儀式画面のレイアウトを大まかに模倣する:
///   - 左 40%: キャラクター / NPC のいるエリア（簡略な四角）
///   - 右 60% 上部: 遺物アイコンのグリッド（5×6 のドット）
///   - 右 60% 下部: 遺物詳細パネル（アクセント色で囲んでハイライト）
/// iPhone のカメラから視野コーンが「詳細パネル」に向かって伸びることで、
/// 「画面のこの部分を狙う」という意図を一目で伝える。
struct ScanIllustration: View {
  var body: some View {
    GeometryReader { geo in
      let h = geo.size.height
      let w = geo.size.width

      let phoneH: CGFloat = h * 0.78
      let phoneW: CGFloat = phoneH * 0.50

      // TV は 16:9 でゲーム画面を再現
      let tvH: CGFloat = h * 0.70
      let tvW: CGFloat = tvH * (16.0 / 9.0)
      let tvStandH: CGFloat = h * 0.12

      let phoneCenter = CGPoint(x: w * 0.13, y: h / 2)
      let tvCenter = CGPoint(x: w * 0.62, y: (h - tvStandH) / 2)

      // 詳細パネルの位置（TV の右下） — 視野コーンの照準
      let panelInset: CGFloat = 4
      let panelW = tvW * 0.55
      let panelH = tvH * 0.28
      let panelMaxX = tvCenter.x + tvW / 2 - panelInset
      let panelMinX = panelMaxX - panelW
      let panelMaxY = tvCenter.y + tvH / 2 - panelInset
      let panelMinY = panelMaxY - panelH

      // iPhone のカメラレンズ位置（右上）。視認性のため大きめにデフォルメ。
      let lensSize: CGFloat = 14
      let lensX = phoneCenter.x + phoneW / 2 - lensSize / 2 - 4
      let lensY = phoneCenter.y - phoneH / 2 + lensSize / 2 + 4

      let cone = ViewCone(
        apex: CGPoint(x: lensX, y: lensY),
        left: CGPoint(x: panelMinX, y: panelMinY),
        right: CGPoint(x: panelMinX, y: panelMaxY)
      )

      ZStack {
        // ① TV / ディスプレイ
        VStack(spacing: 0) {
          // 画面（ゲーム UI 風）
          ZStack {
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.black.opacity(0.9))

            HStack(alignment: .top, spacing: 4) {
              // 左: キャラクター/NPC エリアの示唆（ぼんやりした矩形）
              RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.18))
                .overlay(
                  // キャラっぽいシルエット（頭+胴） を控えめに
                  VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    Circle()
                      .fill(.secondary.opacity(0.35))
                      .frame(width: tvH * 0.10, height: tvH * 0.10)
                    Capsule()
                      .fill(.secondary.opacity(0.35))
                      .frame(width: tvH * 0.18, height: tvH * 0.20)
                    Spacer(minLength: 0)
                  }
                )
                .frame(width: tvW * 0.38)

              // 右: 遺物グリッド + 詳細パネル
              VStack(alignment: .leading, spacing: 4) {
                // 5×6 の遺物アイコングリッド
                VStack(spacing: 2) {
                  ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: 2) {
                      ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                          .fill(.white.opacity(0.30))
                          .aspectRatio(1, contentMode: .fit)
                      }
                    }
                  }
                }
                Spacer(minLength: 0)
              }
              .frame(maxHeight: .infinity)
            }
            .padding(panelInset)

            // 詳細パネル（右下） — ハイライトで強調
            VStack(alignment: .leading, spacing: 2) {
              // タイトル
              RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.9))
                .frame(width: panelW * 0.55, height: 3)
              // 効果ライン x3
              RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.55))
                .frame(width: panelW * 0.78, height: 2)
              RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.55))
                .frame(width: panelW * 0.72, height: 2)
              RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.55))
                .frame(width: panelW * 0.68, height: 2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(width: panelW, height: panelH, alignment: .leading)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
            .overlay(
              RoundedRectangle(cornerRadius: 3)
                .stroke(Color.accentColor, lineWidth: 1.4)
            )
            .position(x: panelMinX + panelW / 2 - (tvCenter.x - tvW / 2),
                      y: panelMinY + panelH / 2 - (tvCenter.y - tvH / 2))
          }
          .frame(width: tvW, height: tvH)
          .overlay(
            RoundedRectangle(cornerRadius: 4)
              .stroke(.secondary, lineWidth: 1)
          )
          // スタンド
          Rectangle()
            .fill(.secondary.opacity(0.6))
            .frame(width: tvW * 0.08, height: tvStandH * 0.55)
          Capsule()
            .fill(.secondary.opacity(0.6))
            .frame(width: tvW * 0.28, height: tvStandH * 0.40)
        }
        .position(x: tvCenter.x, y: tvCenter.y + tvStandH * 0.5)

        // ② 視野コーン（iPhone カメラ → 詳細パネルの左辺）。
        //    TV の上に重ねて描く必要があるので順序が重要。
        //    背景に依らず視認できるよう、白いハロー + アクセント色の破線の 2 重描画。
        cone
          .stroke(style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
          .foregroundStyle(.white.opacity(0.55))
        cone
          .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [7, 4]))
          .foregroundStyle(Color.accentColor)

        // ③ iPhone
        ZStack {
          RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.25))
          RoundedRectangle(cornerRadius: 6).stroke(.secondary, lineWidth: 1)
          // カメラレンズ: 大きめにデフォルメ。外側リング + 内側のレンズ目で
          // 「ここがカメラ」が一目で分かる絵にする。
          ZStack {
            Circle().fill(Color.primary.opacity(0.85))
            Circle()
              .fill(Color.accentColor)
              .frame(width: lensSize * 0.55, height: lensSize * 0.55)
            // 反射のハイライト
            Circle()
              .fill(.white.opacity(0.85))
              .frame(width: lensSize * 0.20, height: lensSize * 0.20)
              .offset(x: -lensSize * 0.12, y: -lensSize * 0.12)
          }
          .frame(width: lensSize, height: lensSize)
          .position(x: phoneW - lensSize / 2 - 4, y: lensSize / 2 + 4)
          // 画面イメージ（黄色枠ライクな細い枠）
          RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor, lineWidth: 1)
            .frame(width: phoneW * 0.62, height: phoneH * 0.18)
            .position(x: phoneW / 2, y: phoneH / 2)
        }
        .frame(width: phoneW, height: phoneH)
        .position(phoneCenter)
      }
    }
    .accessibilityHidden(true)
  }
}

/// 視野の三角（頂点 → 左点 → 右点 → 頂点）。
private struct ViewCone: Shape {
  var apex: CGPoint
  var left: CGPoint
  var right: CGPoint
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: apex)
    p.addLine(to: left)
    p.move(to: apex)
    p.addLine(to: right)
    return p
  }
}

/// AVCaptureVideoPreviewLayer をSwiftUIに載せる
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  func makeUIView(context: Context) -> PreviewView {
    let v = PreviewView()
    v.videoPreviewLayer.session = session
    v.videoPreviewLayer.videoGravity = .resizeAspectFill
    return v
  }
  func updateUIView(_ uiView: PreviewView, context: Context) {}
  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  }
}
