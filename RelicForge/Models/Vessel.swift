import Foundation
import SwiftUI

enum VesselSlotColor: String, Codable, CaseIterable {
  case red, blue, yellow, green, white

  var displayName: String {
    switch self {
    case .red:
      String(localized: "Red")
    case .blue:
      String(localized: "Blue")
    case .yellow:
      String(localized: "Yellow")
    case .green:
      String(localized: "Green")
    case .white:
      String(localized: "White (any color)")
    }
  }

  func accepts(_ relicColor: RelicColor) -> Bool {
    if self == .white {
      return true
    }

    switch (self, relicColor) {
    case (.red, .red), (.blue, .blue), (.yellow, .yellow), (.green, .green):
      return true
    default:
      return false
    }
  }

  var swatch: Color {
    switch self {
    case .red:
      return .red
    case .blue:
      return .blue
    case .yellow:
      return .yellow
    case .green:
      return .green
    case .white:
      return .gray.opacity(0.4)
    }
  }
}

struct Vessel: Identifiable, Codable, Hashable {
  let id: String
  let nameJa: String
  let nameEn: String
  let characterId: String?
  let baseSlots: [VesselSlotColor]
  let deepSlots: [VesselSlotColor]
  let isForsaken: Bool
  let descriptionEn: String

  func availableFor(characterId: String) -> Bool {
    self.characterId == nil || self.characterId == characterId
  }
}

struct VesselsMasterFile: Codable {
  let version: Int
  let vessels: [Vessel]
}

extension Vessel {
  var localizedName: String {
    let isJa = Locale.current.language.languageCode?.identifier == "ja"
    if isJa, !nameJa.isEmpty { return nameJa }
    return nameEn.isEmpty ? nameJa : nameEn
  }
}
