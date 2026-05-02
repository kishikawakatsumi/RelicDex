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
        EffectPickerView(
          title: target.kind == .main ? "Change main effect" : "Change demerit",
          ocrText: target.ocrText,
          candidates: target.candidates,
          currentEffect: target.current,
          mode: target.kind == .main ? .main : .demerit,
          allowNil: target.allowNil
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
            .fill(candidate.recognized.color.swatch)
            .frame(width: 14, height: 14)
          Text(candidate.recognized.displayName)
            .font(.headline)
            .lineLimit(1)
          if candidate.recognized.isUnique {
            Text("Unique")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(.purple.opacity(0.18), in: Capsule())
              .foregroundStyle(.purple)
          }
          if candidate.recognized.depth == .deep {
            Text("Deep")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(.indigo.opacity(0.18), in: Capsule())
              .foregroundStyle(.indigo)
          }
          Spacer()
          Text("◆ \(candidate.recognized.slotCount)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
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
          Text(slot.main?.localizedText ?? String(localized: "(not selected)"))
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
            Text(demerit.localizedText)
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
