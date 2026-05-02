import SwiftUI
import SwiftData

struct ManualRelicEntryView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var color: RelicColor = .red
  @State private var slotCount: Int = 1
  @State private var depth: RelicDepth = .normal
  @State private var slots: [ResolvedSlot] = [ResolvedSlot(main: nil, demerit: nil)]

  @State private var picking: PickerTarget?

  var body: some View {
    NavigationStack {
      Form {
        Section("Base Properties") {
          Picker("Characteristics", selection: $color) {
            ForEach(colorChoices, id: \.self) { c in
              Text(c.displayName).tag(c)
            }
          }
          Picker("Size", selection: $slotCount) {
            Text("Small").tag(1)
            Text("Medium").tag(2)
            Text("Large").tag(3)
          }
          Picker("Type", selection: $depth) {
            Text("Relic").tag(RelicDepth.normal)
            Text("Depths Relic").tag(RelicDepth.deep)
          }
          HStack {
            Text("Name").foregroundStyle(.secondary)
            Spacer()
            Text(derivedName)
              .foregroundStyle(.primary)
          }
        }

        Section("Relic Effect") {
          ForEach(0..<slotCount, id: \.self) { idx in
            slotSection(index: idx)
          }
        }
      }
      .navigationTitle("Add Manually")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Save") { save() }
            .disabled(!isValid)
        }
      }
      .onChange(of: slotCount) { _, newCount in
        if slots.count < newCount {
          slots.append(contentsOf:
            Array(repeating: ResolvedSlot(main: nil, demerit: nil),
                  count: newCount - slots.count))
        } else if slots.count > newCount {
          slots = Array(slots.prefix(newCount))
        }
      }
      .onChange(of: depth) { _, newDepth in
        if newDepth != .deep {
          slots = slots.map { ResolvedSlot(main: $0.main, demerit: nil) }
        }
      }
      .sheet(item: $picking) { target in
        EffectPickerView(
          title: target.kind == .main ? "Main Effect" : "Demerit",
          ocrText: nil,
          candidates: [],
          currentEffect: currentEffect(target),
          mode: target.kind == .main ? .main : .demerit,
          allowNil: target.kind == .demerit,
          onPick: { effect in
            apply(effect, to: target)
          }
        )
      }
    }
  }

  @ViewBuilder
  private func slotSection(index: Int) -> some View {
    let slot = slots[safe: index] ?? ResolvedSlot(main: nil, demerit: nil)
    VStack(alignment: .leading, spacing: 6) {
      Text("Slot \(index + 1)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Button {
        picking = PickerTarget(slotIndex: index, kind: .main)
      } label: {
        HStack {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.tertiary)
          if let m = slot.main {
            Text(m.localizedText).foregroundStyle(.primary)
          } else {
            Text("Select Effect").foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if depth == .deep {
        Button {
          picking = PickerTarget(slotIndex: index, kind: .demerit)
        } label: {
          HStack {
            Image(systemName: "circle.fill")
              .font(.system(size: 6))
              .foregroundStyle(Color.demeritEffect)
            if let d = slot.demerit {
              Text(d.localizedText).foregroundStyle(Color.demeritEffect)
            } else {
              Text("Select demerit (optional)").foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
      }
    }
    .padding(.vertical, 4)
  }

  private var colorChoices: [RelicColor] {
    [.red, .blue, .yellow, .green]
  }

  private var isValid: Bool {
    guard color != .unknown else { return false }
    return (0..<slotCount).contains { idx in
      (slots[safe: idx]?.main) != nil
    }
  }

  private func currentEffect(_ target: PickerTarget) -> RelicEffect? {
    let slot = slots[safe: target.slotIndex]
    return target.kind == .main ? slot?.main : slot?.demerit
  }

  private func apply(_ effect: RelicEffect?, to target: PickerTarget) {
    guard slots.indices.contains(target.slotIndex) else { return }
    let current = slots[target.slotIndex]
    switch target.kind {
    case .main:
      slots[target.slotIndex] = ResolvedSlot(main: effect, demerit: current.demerit)
    case .demerit:
      slots[target.slotIndex] = ResolvedSlot(main: current.main, demerit: effect)
    }
  }

  private func save() {
    let repo = RelicRepository(context: modelContext)
    repo.save(
      color: color,
      slotCount: slotCount,
      depth: depth,
      uniqueId: nil,
      slots: Array(slots.prefix(slotCount))
    )
    dismiss()
  }

  private var derivedName: String {
    MasterDataStore.shared.localizedRelicName(
      slotCount: slotCount, color: color, depth: depth
    )
  }
  
  private struct PickerTarget: Identifiable {
    enum Kind { case main, demerit }
    let slotIndex: Int
    let kind: Kind
    var id: String { "\(slotIndex)-\(kind == .main ? "m" : "d")" }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
