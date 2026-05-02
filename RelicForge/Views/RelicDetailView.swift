import SwiftUI
import SwiftData

struct RelicDetailView: View {
  @Bindable var relic: StoredRelic
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query private var allBuilds: [StoredBuild]
  @State private var showingDeleteConfirm = false
  @State private var inUseAlertMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        effectsSection
        metadataSection
      }
      .padding(.vertical)
    }
    .navigationTitle(relic.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            relic.isFavorite.toggle()
            try? context.save()
          } label: {
            Label(relic.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: relic.isFavorite ? "bookmark.slash" : "bookmark")
          }
          Divider()
          Button(role: .destructive) {
            attemptDelete()
          } label: {
            Label("Delete", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .alert("Delete this relic?", isPresented: $showingDeleteConfirm) {
      Button("Delete", role: .destructive) {
        context.delete(relic)
        try? context.save()
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Cannot delete",
           isPresented: Binding(get: { inUseAlertMessage != nil },
                                set: { if !$0 { inUseAlertMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(inUseAlertMessage ?? "")
    }
  }

  private func attemptDelete() {
    if relic.isFavorite {
      inUseAlertMessage = String(localized: "This relic is favorited.\nRemove it from favorites first.")
      return
    }
    let usingBuilds = allBuilds.filter { $0.uses(relicId: relic.id) }
    if usingBuilds.isEmpty {
      showingDeleteConfirm = true
    } else {
      let names = usingBuilds.map { $0.name }.joined(separator: ", ")
      inUseAlertMessage = String(localized: "This relic is used in builds: \(names)\n\nUnequip it from those builds first.")
    }
  }

  @ViewBuilder
  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      ColorBadge(color: relic.color, slotCount: relic.slotCount, depth: relic.depth)
        .frame(width: 64, height: 64)
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(relic.displayName)
            .font(.title2.weight(.semibold))
          if relic.isUnique {
            Text("Unique")
              .font(.caption.weight(.bold))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.purple.opacity(0.18), in: Capsule())
              .foregroundStyle(.purple)
          }
        }
        HStack(spacing: 8) {
          Tag(text: colorLabel(relic.color))
          Tag(text: sizeLabel(relic.slotCount))
          if !relic.isUnique {
            Tag(text: depthLabel(relic.depth))
          }
        }
}
      Spacer()
    }
    .padding(.horizontal)
  }

  private func colorLabel(_ c: RelicColor) -> String {
    switch c {
    case .red:
      String(localized: "Red")
    case .blue:
      String(localized: "Blue")
    case .yellow:
      String(localized: "Yellow")
    case .green:
      String(localized: "Green")
    case .unknown:
      String(localized: "Unknown")
    }
  }

  private func sizeLabel(_ n: Int) -> String {
    switch n {
    case 1:
      String(localized: "Small")
    case 2:
      String(localized: "Medium")
    case 3:
      String(localized: "Large")
    default: 
      "?"
    }
  }

  private func depthLabel(_ d: RelicDepth) -> String {
    switch d {
    case .normal:
      String(localized: "Relic")
    case .deep:
      String(localized: "Depths Relic")
    case .unknown:
      String(localized: "Unknown")
    }
  }

  @ViewBuilder
  private var effectsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Effects")
        .font(.headline)
        .padding(.horizontal)
      if relic.effects.isEmpty {
        Text("No effects").foregroundStyle(.secondary).padding(.horizontal)
      } else {
        let slots = relic.slotsGrouped
        ForEach(Array(slots.enumerated()), id: \.offset) { _, pair in
          SlotCell(main: pair.main, demerit: pair.demerit)
            .padding(.horizontal)
        }
      }
    }
  }

  @ViewBuilder
  private var metadataSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Registration Info").font(.headline).padding(.horizontal)
      VStack(alignment: .leading, spacing: 4) {
        Text("Registered: \(relic.capturedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
    }
  }
}

struct SlotCell: View {
  let main: StoredRelicEffect
  let demerit: StoredRelicEffect?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(Image(systemName: "circle.fill"))
          .font(.system(size: 7))
          .baselineOffset(5)
          .foregroundStyle(.tertiary)
        Text(main.localizedText).font(.body)
        Spacer()
      }
      if let demerit {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(Image(systemName: "circle.fill"))
            .font(.system(size: 6))
            .baselineOffset(4)
            .foregroundStyle(Color.demeritEffect)
          Text(demerit.localizedText)
            .font(.subheadline)
            .foregroundStyle(Color.demeritEffect)
          Spacer()
        }
        .padding(.leading, 16)
      }
    }
    .padding(12)
    .background(Color.gray.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}
