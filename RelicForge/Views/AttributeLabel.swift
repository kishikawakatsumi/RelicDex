import Foundation

/// 遺物のサイズ・色・深さの属性を表示用に整形する UI ヘルパー。
///
/// 2 種類のフォーマットを提供する:
/// - **メニュー選択肢用** (`...WithHint`): "大（壮大な）" / "Red (Burning)"
///   — in-game 用語を補足表示してユーザーが画面で見ている文字との対応を取れる
/// - **トリガー表示用** (補足なし): "大" / "Red" / "通常" — 選択後の Menu ボタン
///   ラベルに使う。短いのでセル幅で折り返さない
///
/// `ja=true` で日本語、`ja=false` で英語。スキャン取り込みフローではスキャン元
/// の言語 (`recognized.isJapaneseScan`) に合わせる。
enum AttributeLabel {
  // MARK: - 短い形 (トリガー / ボタンラベル)

  static func size(slotCount n: Int, ja: Bool) -> String {
    guard (1...3).contains(n) else { return "—" }
    let mainJa = ["小", "中", "大"]
    let mainEn = ["Small", "Medium", "Large"]
    return ja ? mainJa[n - 1] : mainEn[n - 1]
  }

  static func color(_ c: RelicColor, ja: Bool) -> String {
    switch c {
    case .red:     return ja ? "赤" : "Red"
    case .blue:    return ja ? "青" : "Blue"
    case .yellow:  return ja ? "黄" : "Yellow"
    case .green:   return ja ? "緑" : "Green"
    case .unknown: return "—"
    }
  }

  static func depth(_ d: RelicDepth, ja: Bool) -> String {
    switch d {
    case .normal:  return ja ? "通常" : "Normal"
    case .deep:    return ja ? "深層" : "Deep"
    case .unknown: return "—"
    }
  }

  // MARK: - 長い形 (メニュー選択肢: 主ラベル + in-game 用語の補足)

  static func sizeWithHint(slotCount n: Int, ja: Bool) -> String {
    guard (1...3).contains(n) else { return "—" }
    // 補足の日本語は in-game の連体形 (壮大な 燃える 景色) に合わせる。
    let supJa = ["繊細な", "端正な", "壮大な"]
    let supEn = ["Delicate", "Polished", "Grand"]
    let main = size(slotCount: n, ja: ja)
    let sup = ja ? supJa[n - 1] : supEn[n - 1]
    return ja ? "\(main)（\(sup)）" : "\(main) (\(sup))"
  }

  static func colorWithHint(_ c: RelicColor, ja: Bool) -> String {
    let main = color(c, ja: ja)
    let supJa: String
    let supEn: String
    switch c {
    case .red:     supJa = "燃える"; supEn = "Burning"
    case .blue:    supJa = "滴る";  supEn = "Drizzly"
    case .yellow:  supJa = "輝く";  supEn = "Luminous"
    case .green:   supJa = "静まる"; supEn = "Tranquil"
    case .unknown: return "—"
    }
    return ja ? "\(main)（\(supJa)）" : "\(main) (\(supEn))"
  }

  static func depthWithHint(_ d: RelicDepth, ja: Bool) -> String {
    let main = depth(d, ja: ja)
    switch d {
    case .normal:  return ja ? "\(main)（景色）" : "\(main) (Scene)"
    case .deep:    return ja ? "\(main)（昏景）" : "\(main) (Deep Scene)"
    case .unknown: return "—"
    }
  }
}
