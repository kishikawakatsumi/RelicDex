import Foundation
import SwiftData

@Model
final class StoredRelic {
  @Attribute(.unique) var id: UUID

  var colorRaw: String
  var slotCount: Int
  var depthRaw: String

  var uniqueId: String?

  var capturedAt: Date
  var notes: String?
  var isFavorite: Bool = false

  @Relationship(deleteRule: .cascade, inverse: \StoredRelicEffect.relic)
  var effects: [StoredRelicEffect] = []

  var color: RelicColor { RelicColor(rawValue: colorRaw) ?? .unknown }
  var depth: RelicDepth { RelicDepth(rawValue: depthRaw) ?? .unknown }
  var isUnique: Bool { uniqueId != nil }

  var displayName: String {
    MasterDataStore.shared.localizedRelicName(
      slotCount: slotCount, color: color, depth: depth, uniqueId: uniqueId
    )
  }

  init(
    id: UUID = UUID(),
    color: RelicColor,
    slotCount: Int,
    depth: RelicDepth,
    uniqueId: String? = nil,
    capturedAt: Date = .now,
    notes: String? = nil,
    isFavorite: Bool = false
  ) {
    self.id = id
    self.colorRaw = color.rawValue
    self.slotCount = slotCount
    self.depthRaw = depth.rawValue
    self.uniqueId = uniqueId
    self.capturedAt = capturedAt
    self.notes = notes
    self.isFavorite = isFavorite
  }
}

@Model
final class StoredRelicEffect {
  var effectId: String
  var text: String
  var categoryRaw: String
  var slotIndex: Int
  var isDemerit: Bool
  var relic: StoredRelic?

  var category: RelicEffect.Category { RelicEffect.Category(rawValue: categoryRaw) ?? .unknown }
  var baseName: String { RelicEffect.stripVariantSuffix(text) }

  var localizedText: String {
    let isJa = Locale.current.language.languageCode?.identifier == "ja"
    if isJa { return text }
    if let master = MasterDataStore.shared.effect(forId: effectId) { return master.textEn }

    return text
  }

  init(
    effectId: String,
    text: String,
    category: RelicEffect.Category,
    slotIndex: Int,
    isDemerit: Bool = false
  ) {
    self.effectId = effectId
    self.text = text
    self.categoryRaw = category.rawValue
    self.slotIndex = slotIndex
    self.isDemerit = isDemerit
  }
}

extension StoredRelic {
  var slotsGrouped: [(main: StoredRelicEffect, demerit: StoredRelicEffect?)] {
    let grouped = Dictionary(grouping: effects, by: \.slotIndex)
    return grouped.keys.sorted().compactMap { idx in
      let inSlot = grouped[idx] ?? []
      guard let main = inSlot.first(where: { !$0.isDemerit }) else { return nil }
      let demerit = inSlot.first { $0.isDemerit }
      return (main, demerit)
    }
  }
}
