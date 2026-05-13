import Foundation

/// 遺物のサイズ・色・深さの属性を「メイン (補足)」形式で整形する UI ヘルパー。
///
/// 補足には **in-game の用語** (壮大/燃える/景色 …) を入れて、ユーザーが画面で
/// 見ているタイトル文字との対応を取りやすくする。
///
/// `ja=true` を渡すと完全に日本語表示、`ja=false` で英語表示。スキャン取り込み
/// フローではスキャン元の言語 (`recognized.isJapaneseScan`) に合わせる。
enum AttributeLabel {
  static func size(slotCount n: Int, ja: Bool) -> String {
    guard (1...3).contains(n) else { return "—" }
    let mainJa = ["小", "中", "大"]
    let mainEn = ["Small", "Medium", "Large"]
    let supJa = ["繊細", "端正", "壮大"]
    let supEn = ["Delicate", "Polished", "Grand"]
    let i = n - 1
    return ja ? "\(mainJa[i])（\(supJa[i])）" : "\(mainEn[i]) (\(supEn[i]))"
  }

  static func color(_ c: RelicColor, ja: Bool) -> String {
    switch c {
    case .red:     return ja ? "赤（燃える）" : "Red (Burning)"
    case .blue:    return ja ? "青（滴る）" : "Blue (Drizzly)"
    case .yellow:  return ja ? "黄（輝く）" : "Yellow (Luminous)"
    case .green:   return ja ? "緑（静まる）" : "Green (Tranquil)"
    case .unknown: return "—"
    }
  }

  static func depth(_ d: RelicDepth, ja: Bool) -> String {
    switch d {
    case .normal:  return ja ? "通常（景色）" : "Normal (Scene)"
    case .deep:    return ja ? "深（昏景）" : "Deep (Deep Scene)"
    case .unknown: return "—"
    }
  }
}
