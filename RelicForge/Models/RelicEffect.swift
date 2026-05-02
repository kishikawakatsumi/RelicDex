import Foundation
import SwiftUI

enum RelicColor: String, Codable, CaseIterable {
  case red
  case blue
  case yellow
  case green
  case unknown

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
    case .unknown:
      String(localized: "Unknown")
    }
  }

  var swatch: Color {
    switch self {
    case .red:
        .red
    case .blue:
        .blue
    case .yellow:
        .yellow
    case .green:
        .green
    case .unknown:
        .gray
    }
  }
}

enum RelicDepth: String, Codable, CaseIterable {
  case normal
  case deep
  case unknown
}

struct RelicEffect: Identifiable, Codable, Hashable {
  let id: String
  let textJa: String
  let textEn: String
  let groupJa: String
  let groupEn: String
  let categoryJa: String
  let categoryEn: String
  let category: Category

  enum Category: String, Codable, CaseIterable {
    case attributes
    case attackPower
    case characterSkills
    case spells
    case damageNegation
    case ailmentResistance
    case restoration
    case actions
    case environment
    case startingArmamentSkill
    case startingArmamentImbue
    case startingArmamentAilment
    case startingArmamentSpell
    case startingItem
    case startingItemTear
    case teamMembers
    case characterSpecific
    case armamentSpecific
    case demerits
    case unknown
  }
}

extension RelicEffect {
  var baseName: String { Self.stripVariantSuffix(textJa) }

  static func stripVariantSuffix(_ text: String) -> String {
    text.replacingOccurrences(of: "[＋+][０-９0-9]+$", with: "", options: .regularExpression)
  }

  var localizedText: String {
    let isJa = Locale.current.language.languageCode?.identifier == "ja"
    return isJa ? textJa : textEn
  }

  func text(forJapanese prefersJapanese: Bool) -> String {
    prefersJapanese ? textJa : textEn
  }
}

struct EffectsMasterFile: Codable {
  let version: Int
  let effects: [RelicEffect]
}

struct EffectFilterSection: Identifiable {
  var id: String { groupJa }
  let groupJa: String
  let groupEn: String
  let categories: [EffectFilterCategory]

  var localizedName: String {
    Locale.current.language.languageCode?.identifier == "ja" ? groupJa : groupEn
  }
}

struct EffectFilterCategory: Identifiable {
  var id: String { groupJa + "/" + categoryJa }
  let groupJa: String
  let groupEn: String
  let categoryJa: String
  let categoryEn: String
  let effects: [EffectFilterItem]

  var localizedName: String {
    Locale.current.language.languageCode?.identifier == "ja" ? categoryJa : categoryEn
  }
}

struct EffectFilterItem: Identifiable, Hashable {
  var id: String { baseName }
  let baseName: String
  let baseNameEn: String

  var localizedName: String {
    Locale.current.language.languageCode?.identifier == "ja" ? baseName : baseNameEn
  }
}
