import SwiftUI

/// 遺物の色 / サイズ / 深度を示すバッジ。
/// 元のゲームと同じく **「同じソケット、中の石の色とサイズ」** で表現する:
/// 外枠（ソケット） のサイズは固定、中央の石サイズが slot 数に比例する。
/// 形は通常 / 深層ともに球。**深層は色合い（暗い夜色 + 強いビネット + 暗いソケット）** で
/// 区別する — 形を変えずに視覚的にはっきり別物に見えるよう、調整パラメータは大胆に振る。
struct ColorBadge: View {
  let color: RelicColor
  let slotCount: Int
  let depth: RelicDepth

  /// slot 数 → 中央の石が外枠を占める比率。1 （小） / 2 （中） / 3 （大）。
  private var stoneRatio: CGFloat {
    switch slotCount {
    case 1:  0.50
    case 2:  0.70
    case 3:  0.90
    default: 0.70
    }
  }

  private var isDeep: Bool { depth == .deep }

  // ソケット（背景） は通常 / 深層で共通。深度の違いは石の側（ビネット / 陰影 /
  // ハイライト等） だけで表現する。
  private let socketFill: Color = .gray.opacity(0.18)
  private let socketStroke: Color = .gray.opacity(0.35)

  // 石の質感: 深層は全体的にハイライト弱・陰影強・縁黒・影濃で「夜の宝石」感
  private var domeTopOpacity:    Double { isDeep ? 0.45 : 0.95 }
  private var domeMidOpacity:    Double { isDeep ? 0.18 : 0.55 }
  private var bottomShadow:      Double { isDeep ? 0.45 : 0.12 }
  private var underlightOpacity: Double { isDeep ? 0.04 : 0.18 }
  private var specularOpacity:   Double { isDeep ? 0.55 : 1.00 }
  private var outlineOpacity:    Double { isDeep ? 0.70 : 0.15 }
  private var dropShadowOpacity: Double { isDeep ? 0.70 : 0.35 }
  private var vignetteOpacity:   Double { isDeep ? 0.65 : 0.00 }

  /// 深層の "夜色" フィルム。RGB 微妙に青寄りの暗色を multiply で重ねて、色相を保ったまま
  /// くすませる。普通遺物では透明（= 効果なし）。
  private var nightFilm: Color {
    isDeep
      ? Color(red: 0.18, green: 0.18, blue: 0.32).opacity(0.55)
      : .clear
  }

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let stone = side * stoneRatio
      ZStack {
        // ソケット（背景の枠）。深層は暗黒の台座。
        RoundedRectangle(cornerRadius: side * 0.18)
          .fill(socketFill)
          .overlay(
            RoundedRectangle(cornerRadius: side * 0.18)
              .strokeBorder(socketStroke, lineWidth: 0.5)
          )
        // 石（色 = 遺物の色、サイズ = slot 数、深度 = 色合い）。
        // Aqua スタイルのガラス球: ベース swatch → 陰影 → ビネット → 夜色フィルム →
        // ドーム光沢 → 鏡面ピンスポット の順に重ねる。
        ZStack {
          // ① ベースは完全に swatch で塗りつぶす
          Circle().fill(color.swatch)

          // ② 下半分の陰影 + 最下部 underlight （深層は陰影を強く・反射光を弱く）
          Circle()
            .fill(
              LinearGradient(
                stops: [
                  .init(color: .clear,                            location: 0.55),
                  .init(color: .black.opacity(bottomShadow),      location: 0.95),
                  .init(color: .white.opacity(underlightOpacity), location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )

          // ③ 縁を暗く落とすラジアルビネット（深層のみ強く効かせる）
          Circle()
            .fill(
              RadialGradient(
                stops: [
                  .init(color: .clear,                          location: 0.45),
                  .init(color: .black.opacity(vignetteOpacity), location: 1.00),
                ],
                center: .center,
                startRadius: 0,
                endRadius: stone * 0.55
              )
            )

          // ④ 深層: 夜色フィルムを multiply で重ねてくすませる
          //    （色相は保ちつつ、明度と彩度を一段落とす）
          Circle()
            .fill(nightFilm)
            .blendMode(.multiply)

          // ⑤ 上半分のドーム状光沢。深層は強度を大きく落とす
          Ellipse()
            .fill(
              LinearGradient(
                stops: [
                  .init(color: .white.opacity(domeTopOpacity),    location: 0.00),
                  .init(color: .white.opacity(domeMidOpacity),    location: 0.45),
                  .init(color: .white.opacity(0.06),              location: 0.90),
                  .init(color: .clear,                            location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .frame(width: stone * 0.82, height: stone * 0.52)
            .offset(y: -stone * 0.18)
            .blur(radius: 0.5)

          // ⑥ 鏡面ハイライト: 左上の小さな強い光点（深層は弱め・少し小さめ）
          Circle()
            .fill(.white.opacity(specularOpacity))
            .frame(width: stone * (isDeep ? 0.09 : 0.11),
                   height: stone * (isDeep ? 0.09 : 0.11))
            .offset(x: -stone * 0.18, y: -stone * 0.22)
            .blur(radius: 0.4)
        }
        .compositingGroup()
        .clipShape(Circle())
        .overlay {
          // ⑦ 全体の輪郭（深層は黒く太めに）
          Circle()
            .strokeBorder(.black.opacity(outlineOpacity),
                          lineWidth: isDeep ? 0.7 : 0.4)
        }
        .frame(width: stone, height: stone)
        .shadow(color: .black.opacity(dropShadowOpacity), radius: 2, y: 1.5)
      }
      .frame(width: side, height: side)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

/// 小さなラベル（色/スロット/深度などのメタ情報をカプセルで表示）。
struct Tag: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.caption.weight(.medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(.gray.opacity(0.15), in: Capsule())
  }
}
