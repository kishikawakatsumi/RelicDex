import SwiftUI
import UIKit

/// 動画取り込み後、候補の効果を 1 件ずつ手動修正するための画面。
/// 大きな画像 (ピンチでズーム可) を上半分に表示し、下半分に編集可能な効果リストを置く。
/// 効果をタップすると EffectPickerView がハーフモーダル sheet (detents) で開き、
/// 画像を見ながら効果を選べる。
struct CandidateEditorView: View {
  /// 編集対象の入力データ。Candidate モデル本体に依存しないシリアライズ可能な形にしてある。
  struct Input {
    let title: String
    let recognized: RecognizedRelic
    let frameImage: UIImage
    /// 実際に OCR に渡したクロップ済み画像 (ROI 内のみ)。
    let ocrImage: UIImage
    let initialEdits: CandidateEdits
    let initialIsSelected: Bool
    let reason: String?
  }

  let input: Input
  /// onSave(edits, isSelected, color, slotCount, depth, uniqueId)
  let onSave: (CandidateEdits, Bool, RelicColor, Int, RelicDepth, String?) -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var edits: CandidateEdits
  @State private var isSelected: Bool
  // タイトル属性 (size/color/depth/unique) は recognized から初期化、
  // ユーザーが Menu で変更可能。
  @State private var color: RelicColor
  @State private var slotCount: Int
  @State private var depth: RelicDepth
  @State private var uniqueId: String?
  @State private var pickerTarget: PickerTarget?

  // ピンチズーム状態
  @State private var scale: CGFloat = 1
  @State private var committedScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var committedOffset: CGSize = .zero
  /// 画像エリアに「OCR に渡したクロップ画像」を表示するか
  /// (false なら full frame サムネを表示)。
  @State private var showOCRImage: Bool = false

  init(input: Input,
       onSave: @escaping (CandidateEdits, Bool, RelicColor, Int, RelicDepth, String?) -> Void,
       onCancel: @escaping () -> Void) {
    self.input = input
    self.onSave = onSave
    self.onCancel = onCancel
    self._isSelected = State(initialValue: input.initialIsSelected)
    self._color = State(initialValue: input.recognized.color)
    // recognized.slotCount が 0 (= parse 失敗) のときは安全策で 2 (端正) を default
    let initSlot = max(1, min(3, input.recognized.slotCount == 0 ? 2 : input.recognized.slotCount))
    self._slotCount = State(initialValue: initSlot)
    self._depth = State(initialValue: input.recognized.depth == .unknown ? .normal : input.recognized.depth)
    self._uniqueId = State(initialValue: input.recognized.uniqueMatch?.relic.id)
    // OCR で検出された効果数が title の slotCount より少ない場合、ここで
    // edits をスロット数に合わせてパディングしないと「未検出スロットを編集
    // しても保存先が無くて反映されない」現象が起きる。
    var e = input.initialEdits
    e.resize(to: initSlot)
    self._edits = State(initialValue: e)
  }

  struct PickerTarget: Identifiable {
    let id = UUID()
    let slotIndex: Int
    let kind: Kind
    let line: RecognizedEffectLine?
    let current: RelicEffect?
    enum Kind { case main, demerit }
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geo in
        VStack(spacing: 0) {
          imageArea
            .frame(height: geo.size.height * 0.55)
          effectsArea
        }
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle(input.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") {
            onCancel()
            dismiss()
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            resizeEditsIfNeeded()
            onSave(edits, isSelected, color, slotCount, depth, uniqueId)
            dismiss()
          }
          .bold()
        }
      }
      .sheet(item: $pickerTarget) { target in
        EffectPickerView(
          title: target.kind == .main ? "Change main effect" : "Change demerit",
          ocrText: target.line?.ocrLine.text,
          candidates: target.line?.candidates ?? [],
          currentEffect: target.current,
          mode: target.kind == .main ? .main : .demerit,
          allowNil: target.kind == .demerit,
          prefersJapanese: input.recognized.isJapaneseScan
        ) { picked in
          applyPick(picked, target: target)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
      }
    }
  }

  // MARK: - 画像エリア

  private var imageArea: some View {
    ZStack(alignment: .topTrailing) {
      Color.black
      Image(uiImage: showOCRImage ? input.ocrImage : input.frameImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .scaleEffect(scale)
        .offset(offset)
        .gesture(zoomGesture)
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
      // OCR に実際に渡した画像との切り替えトグル。
      // 認識結果と画面の見た目がずれているとき「何が OCR されたか」を
      // 直接見られるようにする。
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          showOCRImage.toggle()
          // 切り替え時はズーム状態をリセット
          scale = 1; committedScale = 1
          offset = .zero; committedOffset = .zero
        }
      } label: {
        Label(showOCRImage ? "Show full frame" : "Show OCR region",
              systemImage: showOCRImage ? "rectangle.dashed" : "rectangle.inset.filled")
          .font(.caption.weight(.medium))
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: Capsule())
          .foregroundStyle(.white)
      }
      .padding(10)
    }
    .clipped()
  }

  private var zoomGesture: some Gesture {
    let drag = DragGesture()
      .onChanged { v in
        offset = CGSize(
          width: committedOffset.width + v.translation.width,
          height: committedOffset.height + v.translation.height
        )
      }
      .onEnded { _ in committedOffset = offset }
    let pinch = MagnificationGesture()
      .onChanged { v in scale = max(1, min(6, committedScale * v)) }
      .onEnded { _ in committedScale = scale }
    return SimultaneousGesture(drag, pinch)
  }

  // MARK: - 効果リストエリア

  private var effectsArea: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let reason = input.reason {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Text(reason)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.orange)
            Spacer()
          }
          .padding(.horizontal, 16)
          .padding(.top, 12)
        }

        Toggle(isOn: $isSelected) {
          Text("Include in import")
            .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()
        titleAttributesRow
        Divider()

        ForEach(Array(0..<slotCount), id: \.self) { slotIdx in
          effectRow(slotIndex: slotIdx, kind: .main)
          Divider()
          if depth == .deep {
            effectRow(slotIndex: slotIdx, kind: .demerit)
            Divider()
          }
        }
      }
      .padding(.bottom, 24)
    }
    .onChange(of: slotCount) { _, _ in resizeEditsIfNeeded() }
  }

  /// タイトル属性 (size/color/depth) を Menu で選び替えできる行。
  /// メニューの各項目はスキャン元の言語 (`isJapaneseScan`) に合わせて
  /// 「大 (壮大)」「Red (Burning)」のように in-game 用語を補足表示する。
  private var titleAttributesRow: some View {
    let ja = input.recognized.isJapaneseScan
    return VStack(alignment: .leading, spacing: 8) {
      Text("Title attributes")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        // value (= 選択後のトリガー表示) は短い形、メニュー選択肢は補足付きの長い形。
        attributeMenu(label: "Size", value: AttributeLabel.size(slotCount: slotCount, ja: ja)) {
          Button { slotCount = 1 } label: { Text(AttributeLabel.sizeWithHint(slotCount: 1, ja: ja)) }
          Button { slotCount = 2 } label: { Text(AttributeLabel.sizeWithHint(slotCount: 2, ja: ja)) }
          Button { slotCount = 3 } label: { Text(AttributeLabel.sizeWithHint(slotCount: 3, ja: ja)) }
        }
        attributeMenu(label: "Color", value: AttributeLabel.color(color, ja: ja), swatch: color.swatch) {
          Button { color = .red } label: { Text(AttributeLabel.colorWithHint(.red, ja: ja)) }
          Button { color = .blue } label: { Text(AttributeLabel.colorWithHint(.blue, ja: ja)) }
          Button { color = .yellow } label: { Text(AttributeLabel.colorWithHint(.yellow, ja: ja)) }
          Button { color = .green } label: { Text(AttributeLabel.colorWithHint(.green, ja: ja)) }
        }
        attributeMenu(label: "Depth", value: AttributeLabel.depth(depth, ja: ja)) {
          Button { depth = .normal } label: { Text(AttributeLabel.depthWithHint(.normal, ja: ja)) }
          Button { depth = .deep } label: { Text(AttributeLabel.depthWithHint(.deep, ja: ja)) }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  /// 属性 1 項目分の Menu ボタン (タップで選択肢を表示)。
  /// `label` は静的 string literal なので Text() で自動ローカライズされる。
  /// `value` は動的なので String(localized:) で先に解決済の文字列を渡す。
  @ViewBuilder
  private func attributeMenu<Content: View>(
    label: LocalizedStringKey,
    value: String,
    swatch: Color? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Menu {
      content()
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption2)
          .foregroundStyle(.secondary)
        HStack(spacing: 4) {
          if let swatch {
            Circle().fill(swatch).frame(width: 10, height: 10)
          }
          Text(value)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color(uiColor: .secondarySystemBackground),
                  in: RoundedRectangle(cornerRadius: 8))
    }
  }

  /// slotCount に合わせて edits.mains/demerits の長さを揃える。
  private func resizeEditsIfNeeded() {
    edits.resize(to: slotCount)
  }

  @ViewBuilder
  private func effectRow(slotIndex: Int, kind: PickerTarget.Kind) -> some View {
    let value: RelicEffect? = {
      switch kind {
      case .main:
        return edits.mains.indices.contains(slotIndex) ? edits.mains[slotIndex] : nil
      case .demerit:
        return edits.demerits.indices.contains(slotIndex) ? edits.demerits[slotIndex] : nil
      }
    }()
    let label: String = kind == .main
      ? String(localized: "Slot \(slotIndex + 1)")
      : String(localized: "Demerit slot \(slotIndex + 1)")
    let iconName: String = kind == .main ? "checkmark.square" : "minus.square"
    Button {
      let recognizedSlot: RecognizedSlot? = slotIndex < input.recognized.slots.count
        ? input.recognized.slots[slotIndex] : nil
      let line: RecognizedEffectLine? = kind == .main
        ? recognizedSlot?.main
        : recognizedSlot?.demerit
      pickerTarget = PickerTarget(
        slotIndex: slotIndex, kind: kind, line: line, current: value
      )
    } label: {
      HStack(spacing: 12) {
        Image(systemName: iconName)
          .foregroundStyle(.tertiary)
          .frame(width: 20)
        VStack(alignment: .leading, spacing: 2) {
          Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
          // value 有り → 値を表示 / 無し → ローカライズされたプレースホルダ
          // スキャン元 (タイトル) と効果テキストの言語を揃えるため、
          // recognized.isJapaneseScan を使って forJapanese 指定する。
          if let v = value {
            Text(v.text(forJapanese: input.recognized.isJapaneseScan))
              .font(.body)
              .lineLimit(3)
              .multilineTextAlignment(.leading)
          } else {
            Text("(tap to set)")
              .font(.body)
              .foregroundStyle(.secondary)
              .lineLimit(3)
              .multilineTextAlignment(.leading)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
          .font(.caption)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func applyPick(_ picked: RelicEffect?, target: PickerTarget) {
    switch target.kind {
    case .main:
      if target.slotIndex < edits.mains.count {
        edits.mains[target.slotIndex] = picked
      }
    case .demerit:
      if target.slotIndex < edits.demerits.count {
        edits.demerits[target.slotIndex] = picked
      }
    }
  }
}
