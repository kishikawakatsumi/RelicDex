import Foundation

struct UniqueRelic: Identifiable, Codable {
  let id: String
  let nameJa: String
  let nameEn: String
  let color: RelicColor
  let effects: [Reference]

  var slotCount: Int { effects.count }

  struct Reference: Codable, Hashable {
    let textJa: String
    let effectId: String?
  }
}

struct UniqueRelicsMasterFile: Codable {
  let version: Int
  let uniqueRelics: [UniqueRelic]
}
