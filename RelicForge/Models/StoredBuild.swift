import Foundation
import SwiftData

@Model
final class StoredBuild {
  @Attribute(.unique) var id: UUID

  var name: String
  var characterId: String
  var vesselId: String?

  var normalSlot1RelicId: UUID?
  var normalSlot2RelicId: UUID?
  var normalSlot3RelicId: UUID?

  var deepSlot1RelicId: UUID?
  var deepSlot2RelicId: UUID?
  var deepSlot3RelicId: UUID?

  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String = "Untitled",
    characterId: String,
    vesselId: String? = nil,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.characterId = characterId
    self.vesselId = vesselId
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

extension StoredBuild {
  var normalSlotRelicIds: [UUID?] {
    get { [normalSlot1RelicId, normalSlot2RelicId, normalSlot3RelicId] }
    set {
      normalSlot1RelicId = newValue.indices.contains(0) ? newValue[0] : nil
      normalSlot2RelicId = newValue.indices.contains(1) ? newValue[1] : nil
      normalSlot3RelicId = newValue.indices.contains(2) ? newValue[2] : nil
    }
  }

  var deepSlotRelicIds: [UUID?] {
    get { [deepSlot1RelicId, deepSlot2RelicId, deepSlot3RelicId] }
    set {
      deepSlot1RelicId = newValue.indices.contains(0) ? newValue[0] : nil
      deepSlot2RelicId = newValue.indices.contains(1) ? newValue[1] : nil
      deepSlot3RelicId = newValue.indices.contains(2) ? newValue[2] : nil
    }
  }

  func relicId(slotKind: BuildSlotKind, index: Int) -> UUID? {
    switch slotKind {
    case .normal: return normalSlotRelicIds[safe: index] ?? nil
    case .deep:   return deepSlotRelicIds[safe: index] ?? nil
    }
  }

  func setRelicId(_ relicId: UUID?, slotKind: BuildSlotKind, index: Int) {
    switch slotKind {
    case .normal:
      switch index {
      case 0: normalSlot1RelicId = relicId
      case 1: normalSlot2RelicId = relicId
      case 2: normalSlot3RelicId = relicId
      default: break
      }
    case .deep:
      switch index {
      case 0: deepSlot1RelicId = relicId
      case 1: deepSlot2RelicId = relicId
      case 2: deepSlot3RelicId = relicId
      default: break
      }
    }
    updatedAt = .now
  }
}

enum BuildSlotKind {
  case normal
  case deep
}

extension StoredBuild {
  func uses(relicId: UUID) -> Bool {
    (normalSlotRelicIds + deepSlotRelicIds).contains(where: { $0 == relicId })
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
