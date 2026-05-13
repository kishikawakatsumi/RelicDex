import SwiftUI

/// "Needs review" の候補をフルスクリーンで詳しく確認する画面。
/// 画像をピンチでズーム、OCR で取れたテキストと失敗理由を一覧表示。
struct ReviewDetailView: View {
  // VideoIngestView.Candidate を直接参照すると private で見えないので、
  // 必要なフィールドだけ受け取る形にする。
  let candidate: Candidate
  let reasonText: String
  @Environment(\.dismiss) private var dismiss

  @State private var scale: CGFloat = 1
  @State private var committedScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var committedOffset: CGSize = .zero

  /// VideoIngestView から渡される最低限のデータ。
  /// 互換性確保のため、VideoIngestView 側の Candidate を直接 export しない。
  struct Candidate {
    let frameImage: UIImage
    let title: String?
    let ocrLines: [OCRLine]
    let displayName: String
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // 画像エリア (ピンチ・ドラッグ操作可能)
        GeometryReader { geo in
          Color.black
            .overlay {
              Image(uiImage: candidate.frameImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(combinedGesture)
                .onTapGesture(count: 2) {
                  withAnimation(.snappy) {
                    if scale > 1 {
                      scale = 1; committedScale = 1
                      offset = .zero; committedOffset = .zero
                    } else {
                      scale = 2.5; committedScale = 2.5
                    }
                  }
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity)
        // 情報エリア
        infoPanel
      }
      .background(Color.black)
      .navigationTitle("Review")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") { dismiss() }
        }
      }
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
  }

  // MARK: - 情報パネル

  private var infoPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(reasonText)
            .font(.headline)
            .foregroundStyle(.orange)
          Spacer()
        }

        if !candidate.displayName.isEmpty {
          row(label: "Display name", text: candidate.displayName)
        }
        if let title = candidate.title, !title.isEmpty {
          row(label: "OCR title", text: title, mono: true)
        }
        if !candidate.ocrLines.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("All OCR lines")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
              ForEach(candidate.ocrLines) { line in
                Text(line.text)
                  .font(.caption.monospaced())
                  .foregroundStyle(.white.opacity(0.9))
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .padding(10)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .padding(16)
    }
    .frame(maxHeight: 260)
    .background(.black)
    .foregroundStyle(.white)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(.white.opacity(0.1))
        .frame(height: 0.5)
    }
  }

  private func row(label: LocalizedStringKey, text: String, mono: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(text)
        .font(mono ? .footnote.monospaced() : .footnote)
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - ジェスチャ (ピンチ + ドラッグ)

  private var combinedGesture: some Gesture {
    let drag = DragGesture()
      .onChanged { v in
        offset = CGSize(
          width: committedOffset.width + v.translation.width,
          height: committedOffset.height + v.translation.height
        )
      }
      .onEnded { _ in committedOffset = offset }
    let pinch = MagnificationGesture()
      .onChanged { v in
        scale = max(1, min(6, committedScale * v))
      }
      .onEnded { _ in committedScale = scale }
    return SimultaneousGesture(drag, pinch)
  }
}
