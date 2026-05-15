import SwiftUI

/// 「動画の撮り方」チュートリアル。最初に動画を選ぶ前に必ず必要な録画方法を
/// **図とアニメーション主体** で伝えるための画面。初回自動表示 + toolbar の
/// info ボタンで再表示できる。
struct VideoHowToView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      TabView {
        page1
        page2
        page3
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .indexViewStyle(.page(backgroundDisplayMode: .always))
      .navigationTitle("How to record")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            dismiss()
          } label: {
            Text("Close").fontWeight(.semibold)
          }
        }
      }
    }
  }

  // MARK: - ページ 1: 画面録画を使う

  private var page1: some View {
    Step(number: 1, title: "Use screen recording",
         description: "The built-in screen recording feature of your game console or computer gives the best results. You can also record the TV with a smartphone camera, but recognition accuracy will be lower.") {
      // 録画 + デバイスのイラスト
      VStack(spacing: 24) {
        HStack(spacing: 32) {
          deviceTile(icon: "gamecontroller.fill", label: "Console")
          deviceTile(icon: "laptopcomputer", label: "PC")
        }
        Image(systemName: "record.circle.fill")
          .font(.system(size: 56))
          .foregroundStyle(.red)
          .symbolEffect(.pulse, options: .repeating)
      }
    }
  }

  private func deviceTile(icon: String, label: LocalizedStringKey) -> some View {
    VStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 44))
        .foregroundStyle(.tint)
      Text(label)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(width: 110, height: 110)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
  }

  // MARK: - ページ 2: 遺物儀式の画面を開く

  private var page2: some View {
    Step(number: 2, title: "Open the relic inventory",
         description: "Open the Relic Rites screen so the whole grid of relics is visible. The detail panel will appear next to the cursor.") {
      GameScreenMockup()
    }
  }

  // MARK: - ページ 3: カーソルを押しっぱなしで一気にスキャン

  private var page3: some View {
    Step(number: 3, title: "Hold the direction button",
         description: "Hold the D-pad / stick / arrow key down so the cursor advances through every cell from the first relic to the last. Recording each relic for the same duration gives the best OCR result.") {
      CursorAnimation()
    }
  }
}

// MARK: - 共通レイアウト

private struct Step<Content: View>: View {
  let number: Int
  let title: LocalizedStringKey
  let description: LocalizedStringKey
  @ViewBuilder let visual: () -> Content

  var body: some View {
    VStack(spacing: 24) {
      // 図/アニメ領域 (中央寄せで一番目立つ位置)
      visual()
        .frame(maxWidth: .infinity, minHeight: 240)

      // 説明テキスト
      VStack(spacing: 8) {
        HStack(spacing: 8) {
          Text("Step \(number)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint, in: Capsule())
          Text(title)
            .font(.title3.weight(.semibold))
        }
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 24)
      }
      .padding(.bottom, 48)
    }
    .padding(.top, 24)
  }
}

// MARK: - 図: ゲーム画面全体のレイアウト (簡略化)

/// 遺物儀式画面の俯瞰イメージ。左にキャラ/装備セクション、右に一覧グリッド、
/// 下に詳細パネルが並ぶゲーム画面構成をワイヤーフレーム的に再現する。
private struct GameScreenMockup: View {
  private let bg = Color.secondary.opacity(0.08)
  private let panel = Color.secondary.opacity(0.16)
  private let cell = Color.secondary.opacity(0.32)

  /// マス・間隔・セクション幅をすべて定数化して、左右の幅と各セクションの
  /// 縦位置が揃うように設計する。
  private let cellSize: CGFloat = 12
  private let gap: CGFloat = 3
  // 右グリッド (8 列 × 5 行) で決まる幅 = 8 * 12 + 7 * 3 = 117
  private var sectionWidth: CGFloat { 8 * cellSize + 7 * gap }
  // 同じくグリッドで決まる高さ = 5 * 12 + 4 * 3 = 72
  private var gridHeight: CGFloat { 5 * cellSize + 4 * gap }
  private let sectionGap: CGFloat = 10

  var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .top, spacing: sectionGap) {
        // Left: 装備中スロット帯 (6 マス、同サイズ)。残りはブランク。
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: gap) {
            ForEach(0..<6, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 2)
                .fill(cell)
                .frame(width: cellSize, height: cellSize)
            }
          }
          Spacer(minLength: 0)
        }
        .frame(width: sectionWidth, height: gridHeight, alignment: .topLeading)

        // Right: 遺物一覧グリッド (8 列 × 5 行)
        VStack(spacing: gap) {
          ForEach(0..<5, id: \.self) { row in
            HStack(spacing: gap) {
              ForEach(0..<8, id: \.self) { col in
                ZStack {
                  RoundedRectangle(cornerRadius: 2)
                    .fill(cell)
                    .frame(width: cellSize, height: cellSize)
                  if row == 2 && col == 5 {
                    RoundedRectangle(cornerRadius: 3)
                      .stroke(.yellow, lineWidth: 1.5)
                      .frame(width: cellSize + 4, height: cellSize + 4)
                  }
                }
                .frame(width: cellSize, height: cellSize)
              }
            }
          }
        }
        .frame(width: sectionWidth, height: gridHeight)
      }

      // Bottom: 左右の詳細パネル。同じ大きさ、上揃え。
      HStack(alignment: .top, spacing: sectionGap) {
        detailPanel().frame(width: sectionWidth)
        detailPanel().frame(width: sectionWidth)
      }
    }
    .padding(10)
    .background(bg, in: RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(panel, lineWidth: 1)
    )
    .fixedSize()  // 内容に合わせてコンパクトに、親に引き伸ばされない
  }

  private func detailPanel() -> some View {
    HStack(alignment: .top, spacing: 5) {
      RoundedRectangle(cornerRadius: 3)
        .fill(cell)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 2) {
        ForEach(0..<3, id: \.self) { i in
          RoundedRectangle(cornerRadius: 1)
            .fill(cell)
            // 行ごとに少しずつ短くしてテキストっぽさを出す
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 3)
            .padding(.trailing, CGFloat(i) * 6)
        }
      }
    }
    .padding(5)
    .background(panel, in: RoundedRectangle(cornerRadius: 4))
  }
}

// MARK: - 図 + アニメ: カーソルがグリッドを順に進み、詳細パネルも同期して変わる

private struct CursorAnimation: View {
  private let cols = 6
  private let rows = 4
  private let cellSize: CGFloat = 28
  private let gap: CGFloat = 4
  private let stepDuration: TimeInterval = 0.32

  /// マス毎の (slot 数, アイコン色) パターン。ランダムっぽく見えるよう
  /// バラついた並び。3 / 2 / 1 をまんべんなく出す。
  private let pattern: [(slot: Int, color: Color)] = [
    (3, .red), (2, .blue), (1, .yellow), (3, .green),
    (2, .red), (3, .blue), (1, .green), (2, .yellow),
    (3, .red), (1, .blue), (2, .green), (3, .yellow),
    (2, .red), (1, .yellow), (3, .blue), (2, .green),
    (1, .red), (3, .yellow), (2, .blue), (3, .green),
  ]

  var body: some View {
    TimelineView(.animation(minimumInterval: stepDuration, paused: false)) { context in
      let total = cols * rows
      let elapsed = context.date.timeIntervalSinceReferenceDate
      let cursor = Int(elapsed / stepDuration) % total
      let entry = pattern[cursor % pattern.count]

      VStack(spacing: 14) {
        // グリッド + カーソル
        VStack(spacing: gap) {
          ForEach(0..<rows, id: \.self) { row in
            HStack(spacing: gap) {
              ForEach(0..<cols, id: \.self) { col in
                let index = row * cols + col
                ZStack {
                  Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: cellSize, height: cellSize)
                  if index == cursor {
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Color.yellow, lineWidth: 2.5)
                      .frame(width: cellSize + 4, height: cellSize + 4)
                  }
                }
                .frame(width: cellSize, height: cellSize)
              }
            }
          }
        }

        // 同期して変わる詳細パネル
        detailPanel(slotCount: entry.slot, iconColor: entry.color)

        // Hold インジケータ: D-pad の右ボタンが押されているイメージ。
        // `dpad.right.filled` で右だけ filled (= 押下) 表示、pulse で
        // 「現在押しっぱなし中」というアクティブ感を出す。
        HStack(spacing: 8) {
          Image(systemName: "dpad.right.filled")
            .symbolEffect(.pulse, options: .repeating)
            .foregroundStyle(.tint)
            .font(.title)
          Text("Hold")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// `slotCount` ぶんの効果ラインを持つ詳細パネル。パネル自体の高さは固定して
  /// グリッドが上下にジャンプしないようにする。
  private func detailPanel(slotCount: Int, iconColor: Color) -> some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 4)
        .fill(iconColor.opacity(0.45))
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(0..<slotCount, id: \.self) { i in
          RoundedRectangle(cornerRadius: 1)
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 100 - CGFloat(i) * 12, height: 5)
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
    }
    .padding(8)
    .frame(width: 190, height: 56, alignment: .topLeading)
    .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
  }
}

#Preview {
  VideoHowToView()
}
