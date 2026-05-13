import SwiftUI
import SwiftData

struct ScanCandidatesView: View {
  @ObservedObject var session: ScanSession
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var showingDiscardConfirm = false

  @State private var pickerTarget: PickerTarget?

  struct PickerTarget: Identifiable {
    let id = UUID()
    let candidateIndex: Int
    let slotIndex: Int
    let kind: Kind
    let candidates: [EffectMatch]
    let ocrText: String?
    let current: RelicEffect?
    let allowNil: Bool
    enum Kind { case main, demerit }
  }

  var body: some View {
    NavigationStack {
      Group {
        if session.candidates.isEmpty {
          emptyView
        } else {
          list
        }
      }
      .navigationTitle("Scan Candidates (\(session.count))")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          if !session.candidates.isEmpty {
            Menu {
              Button("Select All") { session.selectAll(true) }
              Button("Deselect All") { session.selectAll(false) }
              Divider()
              Button("Discard All", role: .destructive) {
                showingDiscardConfirm = true
              }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if !session.candidates.isEmpty {
          saveBar
        }
      }
      .alert("Discard all candidates?", isPresented: $showingDiscardConfirm) {
        Button("Discard", role: .destructive) {
          session.clear()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      }
      .sheet(item: $pickerTarget) { target in
        // 対応する候補の OCR 言語に合わせてピッカーも日本語/英語で表示する。
        // 添え字範囲外のときだけ Locale 既定 (nil) にフォールバック。
        let prefersJa: Bool? = target.candidateIndex < session.candidates.count
          ? session.candidates[target.candidateIndex].recognized.isJapaneseScan
          : nil
        EffectPickerView(
          title: target.kind == .main ? "Change main effect" : "Change demerit",
          ocrText: target.ocrText,
          candidates: target.candidates,
          currentEffect: target.current,
          mode: target.kind == .main ? .main : .demerit,
          allowNil: target.allowNil,
          prefersJapanese: prefersJa
        ) { picked in
          apply(picked, target: target)
        }
      }
    }
  }

  private func apply(_ picked: RelicEffect?, target: PickerTarget) {
    guard target.candidateIndex < session.candidates.count else { return }
    var edits = session.candidates[target.candidateIndex].edits
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
    session.candidates[target.candidateIndex].edits = edits
  }

  @ViewBuilder
  private var list: some View {
    List {
      ForEach(Array(session.candidates.enumerated()), id: \.element.id) { idx, candidate in
        CandidateRow(
          candidate: $session.candidates[idx],
          onDelete: { session.remove(id: candidate.id) },
          onTapEffect: { kind, slotIndex in
            pickerTarget = makeTarget(for: candidate, idx: idx, kind: kind, slotIndex: slotIndex)
          }
        )
      }
    }
    .listStyle(.plain)
  }

  private func makeTarget(
    for candidate: ScanCandidate,
    idx: Int,
    kind: PickerTarget.Kind,
    slotIndex: Int
  ) -> PickerTarget {
    let recognizedSlot: RecognizedSlot? = {
      guard slotIndex < candidate.recognized.slots.count else { return nil }
      return candidate.recognized.slots[slotIndex]
    }()
    let line: RecognizedEffectLine? = {
      switch kind {
      case .main:    return recognizedSlot?.main
      case .demerit: return recognizedSlot?.demerit
      }
    }()
    let current: RelicEffect? = {
      switch kind {
      case .main:
        return slotIndex < candidate.edits.mains.count ? candidate.edits.mains[slotIndex] : nil
      case .demerit:
        return slotIndex < candidate.edits.demerits.count ? candidate.edits.demerits[slotIndex] : nil
      }
    }()
    return PickerTarget(
      candidateIndex: idx,
      slotIndex: slotIndex,
      kind: kind,
      candidates: line?.candidates ?? [],
      ocrText: line?.ocrLine.text,
      current: current,
      allowNil: kind == .demerit
    )
  }

  @ViewBuilder
  private var emptyView: some View {
    VStack(spacing: 12) {
      Image(systemName: "tray")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)
      Text("No candidates")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  @ViewBuilder
  private var saveBar: some View {
    VStack(spacing: 0) {
      Divider()
      HStack {
        Text("\(session.selectedCount) / \(session.count) selected")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          let repo = RelicRepository(context: modelContext)
          let saved = session.commitSelected(to: repo)
          if saved > 0 { dismiss() }
        } label: {
          Text("Save \(session.selectedCount) selected")
            .monospacedDigit()
            .frame(minWidth: 160)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.selectedCount == 0)
      }
      .padding()
      .background(.ultraThinMaterial)
    }
  }
}

private struct CandidateRow: View {
  @Binding var candidate: ScanCandidate
  let onDelete: () -> Void
  let onTapEffect: (ScanCandidatesView.PickerTarget.Kind, Int) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Toggle("", isOn: $candidate.isSelected)
        .labelsHidden()
        .tint(.accentColor)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 6) {
          Circle()
            .fill(candidate.color.swatch)
            .frame(width: 14, height: 14)
          Text(candidate.displayName)
            .font(.headline)
            .lineLimit(1)
          if candidate.recognized.isUnique {
            Text("Unique")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(.purple.opacity(0.18), in: Capsule())
              .foregroundStyle(.purple)
          }
          if candidate.depth == .deep {
            Text("Deep")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(.indigo.opacity(0.18), in: Capsule())
              .foregroundStyle(.indigo)
          }
          Spacer()
          Text("◆ \(candidate.slotCount)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        }

        // 固有遺物は属性が全て確定しているので Menu を出さない。
        if !candidate.recognized.isUnique {
          titleAttributesRow
        }

        VStack(spacing: 8) {
          ForEach(Array(candidate.finalSlots.enumerated()), id: \.offset) { slotIdx, slot in
            slotEditor(slotIdx: slotIdx, slot: slot)
          }
        }

        if candidate.recognized.isUnique {
          Text("Unique relic effects are fixed (not editable)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 8)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) { onDelete() } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }

  /// タイトル属性 (size/color/depth) を Menu で選び替えできる行。
  /// `CandidateEditorView` (動画スキャン用) と同じパターンを再利用する。
  private var titleAttributesRow: some View {
    let ja = candidate.recognized.isJapaneseScan
    return HStack(spacing: 8) {
      // value (= 選択後のトリガー表示) は短い形、選択肢は補足付き。
      attributeMenu(label: "Size",
                    value: AttributeLabel.size(slotCount: candidate.slotCount, ja: ja)) {
        Button { setSlotCount(1) } label: { Text(AttributeLabel.sizeWithHint(slotCount: 1, ja: ja)) }
        Button { setSlotCount(2) } label: { Text(AttributeLabel.sizeWithHint(slotCount: 2, ja: ja)) }
        Button { setSlotCount(3) } label: { Text(AttributeLabel.sizeWithHint(slotCount: 3, ja: ja)) }
      }
      attributeMenu(label: "Color",
                    value: AttributeLabel.color(candidate.color, ja: ja),
                    swatch: candidate.color.swatch) {
        Button { candidate.color = .red } label: { Text(AttributeLabel.colorWithHint(.red, ja: ja)) }
        Button { candidate.color = .blue } label: { Text(AttributeLabel.colorWithHint(.blue, ja: ja)) }
        Button { candidate.color = .yellow } label: { Text(AttributeLabel.colorWithHint(.yellow, ja: ja)) }
        Button { candidate.color = .green } label: { Text(AttributeLabel.colorWithHint(.green, ja: ja)) }
      }
      attributeMenu(label: "Depth",
                    value: AttributeLabel.depth(candidate.depth, ja: ja)) {
        Button { candidate.depth = .normal } label: { Text(AttributeLabel.depthWithHint(.normal, ja: ja)) }
        Button { candidate.depth = .deep } label: { Text(AttributeLabel.depthWithHint(.deep, ja: ja)) }
      }
    }
  }

  /// slotCount の上書きに合わせて edits.mains/demerits の長さを揃える。
  private func setSlotCount(_ n: Int) {
    candidate.slotCount = n
    candidate.edits.resize(to: n)
  }

  /// 属性 1 項目分の Menu ボタン (CandidateEditorView と同じ見た目)。
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
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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

  @ViewBuilder
  private func slotEditor(slotIdx: Int, slot: ResolvedSlot) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        guard !candidate.recognized.isUnique else { return }
        onTapEffect(.main, slotIdx)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(Image(systemName: "circle.fill"))
            .font(.system(size: 6))
            .baselineOffset(4)
            .foregroundStyle(.tertiary)
          Text(slot.main?.text(forJapanese: candidate.recognized.isJapaneseScan)
               ?? String(localized: "(not selected)"))
            .font(.subheadline)
            .foregroundStyle(slot.main == nil ? .secondary : .primary)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 4)
          if !candidate.recognized.isUnique {
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(candidate.recognized.isUnique)

      if let demerit = slot.demerit {
        Divider().padding(.horizontal, 8)
        Button {
          guard !candidate.recognized.isUnique else { return }
          onTapEffect(.demerit, slotIdx)
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Image(systemName: "circle.fill"))
              .font(.system(size: 6))
              .baselineOffset(4)
              .foregroundStyle(Color.demeritEffect)
            Text(demerit.text(forJapanese: candidate.recognized.isJapaneseScan))
              .font(.subheadline)
              .foregroundStyle(Color.demeritEffect)
              .lineLimit(3)
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !candidate.recognized.isUnique {
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            }
          }
          .padding(.vertical, 10)
          .padding(.horizontal, 8)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(candidate.recognized.isUnique)
      }
    }
    .background(.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
  }
}
