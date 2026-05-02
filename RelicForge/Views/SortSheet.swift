import SwiftUI

enum RelicSortOption: String, CaseIterable, Codable {
  case registered
  case size
  case color

  var labelKey: LocalizedStringResource {
    switch self {
    case .registered:
      "Order Registered"
    case .size:
      "Order by Size"
    case .color:
      "Order by Color"
    }
  }
}

struct RelicSortConfig: Equatable, Codable {
  var option: RelicSortOption
  var ascending: Bool
}

extension RelicColor {
  var sortIndex: Int {
    switch self {
    case .red: 0
    case .blue: 1
    case .yellow: 2
    case .green: 3
    case .unknown: 4
    }
  }
}

extension Array where Element == StoredRelic {
  func sorted(by config: RelicSortConfig) -> [StoredRelic] {
    let asc = config.ascending
    switch config.option {
    case .registered:
      return self.sorted { asc ? $0.capturedAt < $1.capturedAt : $0.capturedAt > $1.capturedAt }
    case .size:
      return self.sorted { a, b in
        if a.slotCount != b.slotCount {
          return asc ? a.slotCount < b.slotCount : a.slotCount > b.slotCount
        }
        return a.capturedAt > b.capturedAt
      }
    case .color:
      return self.sorted { a, b in
        let ai = a.color.sortIndex, bi = b.color.sortIndex
        if ai != bi { return asc ? ai < bi : ai > bi }
        return a.capturedAt > b.capturedAt
      }
    }
  }
}

struct SortSheet: View {
  @Binding var config: RelicSortConfig
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(RelicSortOption.allCases, id: \.self) { option in
          Button {
            if config.option == option {
              config.ascending.toggle()
            } else {
              config.option = option
              config.ascending = true
            }
          } label: {
            HStack {
              Text(option.labelKey)
                .foregroundStyle(.primary)
              Spacer()
              if config.option == option {
                Image(systemName: config.ascending ? "arrow.up" : "arrow.down")
                  .foregroundStyle(Color.accentColor)
                  .font(.subheadline.weight(.semibold))
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .navigationTitle("Sort")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
