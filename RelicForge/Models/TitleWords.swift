import Foundation

struct TitleWordsMasterFile: Codable {
  let version: Int
  let sizes: [SizeWord]
  let colors: [ColorWord]
  let depths: [DepthWord]

  struct SizeWord: Codable {
    let slotCount: Int
    let ja: String
    let en: String
  }

  struct ColorWord: Codable {
    let color: String
    let ja: String
    let en: String
  }

  struct DepthWord: Codable {
    let depth: String
    let ja: String
    let en: String
    let enPrefix: String?
  }
}
