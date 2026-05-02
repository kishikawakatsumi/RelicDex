import SwiftUI

struct VesselPickerView: View {
  let characterId: String
  let currentVesselId: String?
  let onSelect: (Vessel?) -> Void

  @Environment(\.dismiss) private var dismiss

  private let master = MasterDataStore.shared

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button(role: .destructive) {
            onSelect(nil)
            dismiss()
          } label: {
            HStack {
              Text("Clear Selection")
              Spacer()
              if currentVesselId == nil {
                Image(systemName: "checkmark").foregroundStyle(.tint)
              }
            }
          }
        }
        Section("\(characterDisplayName) only") {
          ForEach(characterVessels) { v in
            row(v)
          }
        }
        Section("Common") {
          ForEach(genericVessels) { v in
            row(v)
          }
        }
      }
      .navigationTitle("Select Vessel")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
    }
  }

  private var characterDisplayName: String {
    master.character(forId: characterId)?.localizedName ?? characterId
  }

  private var genericVessels: [Vessel] {
    master.vessels.filter { $0.characterId == nil }
  }

  private var characterVessels: [Vessel] {
    master.vessels.filter { $0.characterId == characterId }
  }

  private func row(_ v: Vessel) -> some View {
    Button {
      onSelect(v)
      dismiss()
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(v.localizedName)
            .font(.body)
            .foregroundStyle(.primary)
          HStack(spacing: 14) {
            slotColors(v.baseSlots)
            slotColors(v.deepSlots)
          }
        }
        Spacer()
        if v.id == currentVesselId {
          Image(systemName: "checkmark").foregroundStyle(.tint)
        }
      }
    }
  }

  private func slotColors(_ colors: [VesselSlotColor]) -> some View {
    HStack(spacing: 3) {
      ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
        Circle().fill(c.swatch).frame(width: 10, height: 10)
          .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
      }
    }
  }
}
