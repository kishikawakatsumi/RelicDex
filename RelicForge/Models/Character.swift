import Foundation

struct Nightfarer: Identifiable, Codable, Hashable {
  let id: String
  let nameJa: String
  let nameEn: String
  let isForsaken: Bool
}

struct CharactersMasterFile: Codable {
  let version: Int
  let characters: [Nightfarer]
}

extension Nightfarer {
  var localizedName: String {
    let isJa = Locale.current.language.languageCode?.identifier == "ja"
    if isJa, !nameJa.isEmpty { return nameJa }
    return nameEn.isEmpty ? nameJa : nameEn
  }
}
