#!/usr/bin/env swift
//
// Nightreign Relics アプリアイコン生成スクリプト
// 斜め上から見た 2x2 の宝石ケース。各セルにシンプルなファセット宝石。
//
// 使い方:
//   swiftc scripts/generate_app_icon.swift -o /tmp/gen -framework AppKit
//   /tmp/gen <output-dir>
//
import Foundation
import AppKit
import CoreGraphics

let SIZE: CGFloat = 1024

// MARK: - 共通

func makeContext() -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: Int(SIZE), height: Int(SIZE),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
    guard let cg = ctx.makeImage() else { fatalError("image") }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! data.write(to: url)
    print("→ \(url.lastPathComponent)")
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

func bilinear(_ TL: CGPoint, _ TR: CGPoint,
              _ BR: CGPoint, _ BL: CGPoint,
              u: CGFloat, v: CGFloat) -> CGPoint
{
    let top = lerp(TL, TR, u)
    let bottom = lerp(BL, BR, u)
    return lerp(top, bottom, v)
}

func quadPath(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: p0); path.addLine(to: p1); path.addLine(to: p2); path.addLine(to: p3)
    path.closeSubpath()
    return path
}

// MARK: - 背景

func drawBackdrop(_ ctx: CGContext, inner: CGColor, outer: CGColor) {
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray,
                       locations: [0, 1])!
    let center = CGPoint(x: SIZE / 2, y: SIZE / 2)
    ctx.drawRadialGradient(g,
                           startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: SIZE * 0.78,
                           options: [.drawsAfterEndLocation])
}

// MARK: - 箱（斜めから見た透視）

/// 箱の上面の4頂点（Y上向き座標系で奥が上）
let boxTL = CGPoint（x: SIZE * 0.18, y: SIZE * 0.78）  // 奥-左
let boxTR = CGPoint（x: SIZE * 0.82, y: SIZE * 0.78）  // 奥-右
let boxBR = CGPoint（x: SIZE * 0.92, y: SIZE * 0.20）  // 手前-右
let boxBL = CGPoint（x: SIZE * 0.08, y: SIZE * 0.20）  // 手前-左

let depthDrop: CGFloat = SIZE * 0.05  // 厚み（側面の高さ）

func drawBox(_ ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()

    // 影（箱の下にぼんやりと）
    ctx.saveGState()
    let shadow = CGGradient(colorsSpace: space,
                            colors: [rgb(0, 0, 0, 0.45),
                                     rgb(0, 0, 0, 0)] as CFArray,
                            locations: [0, 1])!
    let shadowCenter = CGPoint(x: SIZE / 2, y: SIZE * 0.18)
    ctx.drawRadialGradient(shadow,
                           startCenter: shadowCenter, startRadius: 0,
                           endCenter: shadowCenter, endRadius: SIZE * 0.45,
                           options: [])
    ctx.restoreGState()

    // 側面（右側） — 厚みを表現
    let sideRPath = quadPath(
        CGPoint(x: boxBR.x, y: boxBR.y),
        CGPoint(x: boxTR.x, y: boxTR.y),
        CGPoint(x: boxTR.x + depthDrop * 0.5, y: boxTR.y - depthDrop * 0.3),
        CGPoint(x: boxBR.x + depthDrop * 0.5, y: boxBR.y - depthDrop * 0.3)
    )
    // 実際には簡素化: 下面（手前のフチ） のみ厚みとして描く
    let frontFacePath = quadPath(
        CGPoint(x: boxBL.x, y: boxBL.y),
        CGPoint(x: boxBR.x, y: boxBR.y),
        CGPoint(x: boxBR.x, y: boxBR.y - depthDrop),
        CGPoint(x: boxBL.x, y: boxBL.y - depthDrop)
    )
    ctx.addPath(frontFacePath)
    let frontGrad = CGGradient(colorsSpace: space,
                               colors: [rgb(0.10, 0.12, 0.18),
                                        rgb(0.04, 0.05, 0.09)] as CFArray,
                               locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(frontFacePath)
    ctx.clip()
    ctx.drawLinearGradient(frontGrad,
                           start: CGPoint(x: 0, y: boxBL.y),
                           end: CGPoint(x: 0, y: boxBL.y - depthDrop),
                           options: [])
    ctx.restoreGState()
    ctx.addPath(frontFacePath)
    ctx.setStrokeColor(rgb(0.55, 0.62, 0.78, 0.7))
    ctx.setLineWidth(2)
    ctx.strokePath()
    _ = sideRPath  // 未使用（シンプル化のため右側面は省略）

    // 上面（透視台形）
    let top = quadPath(boxTL, boxTR, boxBR, boxBL)
    ctx.saveGState()
    ctx.addPath(top)
    ctx.clip()
    let topGrad = CGGradient(colorsSpace: space,
                             colors: [rgb(0.14, 0.16, 0.24),
                                      rgb(0.06, 0.07, 0.12)] as CFArray,
                             locations: [0, 1])!
    ctx.drawLinearGradient(topGrad,
                           start: CGPoint(x: 0, y: boxTL.y),
                           end: CGPoint(x: 0, y: boxBL.y),
                           options: [])
    ctx.restoreGState()
    ctx.addPath(top)
    ctx.setStrokeColor(rgb(0.65, 0.72, 0.88, 0.85))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

// MARK: - セル + 宝石

struct GemPalette {
    let topFacet: CGColor
    let mid: CGColor
    let bottomFacet: CGColor
    let outline: CGColor
}

let redGem = GemPalette(
    topFacet:    rgb(1.00, 0.85, 0.55),
    mid:         rgb(0.95, 0.30, 0.15),
    bottomFacet: rgb(0.55, 0.05, 0.05),
    outline:     rgb(0.30, 0.00, 0.00)
)
let blueGem = GemPalette(
    topFacet:    rgb(0.78, 0.92, 1.00),
    mid:         rgb(0.30, 0.58, 0.98),
    bottomFacet: rgb(0.08, 0.22, 0.55),
    outline:     rgb(0.04, 0.10, 0.30)
)
let yellowGem = GemPalette(
    topFacet:    rgb(1.00, 0.97, 0.75),
    mid:         rgb(1.00, 0.82, 0.20),
    bottomFacet: rgb(0.65, 0.42, 0.05),
    outline:     rgb(0.35, 0.22, 0.00)
)
let greenGem = GemPalette(
    topFacet:    rgb(0.80, 1.00, 0.85),
    mid:         rgb(0.30, 0.80, 0.45),
    bottomFacet: rgb(0.05, 0.40, 0.20),
    outline:     rgb(0.00, 0.20, 0.10)
)

/// セル = 透視台形のくぼみ（箱の中の仕切り）
func drawCell(_ ctx: CGContext, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) {
    let path = quadPath(p0, p1, p2, p3)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: space,
                       colors: [rgb(0.04, 0.05, 0.10),
                                rgb(0.10, 0.11, 0.18)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g,
                           start: p3, end: p0,  // 手前→奥
                           options: [])
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0.40, 0.48, 0.65, 0.7))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

/// 六角形（point-up） の宝石。中心からのラジアルグラデと、上下のファセット線で立体感。
func drawGem(_ ctx: CGContext, center: CGPoint, radius: CGFloat, palette: GemPalette) {
    // 六角頂点（point-up）
    let dx = radius * sqrt(3) / 2
    let r2 = radius / 2
    let pts = [
        CGPoint(x: center.x,        y: center.y + radius),  // top
        CGPoint(x: center.x + dx,   y: center.y + r2),       // upper-right
        CGPoint(x: center.x + dx,   y: center.y - r2),       // lower-right
        CGPoint(x: center.x,        y: center.y - radius),   // bottom
        CGPoint(x: center.x - dx,   y: center.y - r2),       // lower-left
        CGPoint(x: center.x - dx,   y: center.y + r2),       // upper-left
    ]
    let outline = CGMutablePath()
    outline.move(to: pts[0])
    for i in 1..<pts.count { outline.addLine(to: pts[i]) }
    outline.closeSubpath()

    let space = CGColorSpaceCreateDeviceRGB()

    // 外周のグロー
    let glowColors = [palette.mid.copy(alpha: 0.55)!,
                      palette.mid.copy(alpha: 0)!] as CFArray
    let glow = CGGradient(colorsSpace: space, colors: glowColors,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: center, startRadius: radius * 0.95,
                           endCenter: center, endRadius: radius * 1.7,
                           options: [])

    // ボディ
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    let body = CGGradient(colorsSpace: space,
                          colors: [palette.topFacet, palette.mid, palette.bottomFacet] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(body,
                           start: pts[0], end: pts[3],
                           options: [])

    // 上半分のファセット（上端の三角形を白く重ねて反射感）
    let topFacet = CGMutablePath()
    topFacet.move(to: pts[0])
    topFacet.addLine(to: pts[1])
    topFacet.addLine(to: pts[5])
    topFacet.closeSubpath()
    ctx.addPath(topFacet)
    ctx.setFillColor(rgb(1, 1, 1, 0.18))
    ctx.fillPath()

    ctx.restoreGState()

    // 内側のファセット線（中央から各頂点へ細い線）
    ctx.setStrokeColor(palette.outline.copy(alpha: 0.4)!)
    ctx.setLineWidth(1.5)
    let lines = CGMutablePath()
    for p in pts {
        lines.move(to: center)
        lines.addLine(to: p)
    }
    ctx.addPath(lines)
    ctx.strokePath()

    // 外周
    ctx.addPath(outline)
    ctx.setStrokeColor(palette.outline)
    ctx.setLineWidth(3)
    ctx.strokePath()
}

// MARK: - グリッド配置

func drawGrid(_ ctx: CGContext, palettes: [GemPalette]) {
    drawBox(ctx)

    let gap: CGFloat = 0.04
    // 各セルの（col, row） — col: 左0/右1、row: 0=奥/1=手前
    let cells: [(col: Int, row: Int)] = [
       （0, 0）,（1, 0）,   // 奥側（赤・青）
       （0, 1）,（1, 1）,   // 手前側（黄・緑）
    ]

    for (idx, c) in cells.enumerated() {
        // 透視座標系での u,v
        let u0 = CGFloat(c.col) * 0.5 + gap
        let u1 = CGFloat(c.col + 1) * 0.5 - gap
        // ※ Y上向き座標系で boxTL の v=0 が "奥" なので row=0 （奥） → v低い側
        let v0 = CGFloat（1 - c.row） * 0.5 + gap     // 上（奥） 側の頂点
        let v1 = CGFloat（2 - c.row） * 0.5 - gap     // 下（手前） 側の頂点

        let pTL = bilinear(boxTL, boxTR, boxBR, boxBL, u: u0, v: v0)
        let pTR = bilinear(boxTL, boxTR, boxBR, boxBL, u: u1, v: v0)
        let pBR = bilinear(boxTL, boxTR, boxBR, boxBL, u: u1, v: v1)
        let pBL = bilinear(boxTL, boxTR, boxBR, boxBL, u: u0, v: v1)
        drawCell(ctx, p0: pTL, p1: pTR, p2: pBR, p3: pBL)

        // 宝石の中心 = セルの幾何中心、半径はセル幅の~38%
        let cx = (pTL.x + pTR.x + pBR.x + pBL.x) / 4
        let cy = (pTL.y + pTR.y + pBR.y + pBL.y) / 4
        let cellW = max(distance(pTL, pTR), distance(pBL, pBR))
        drawGem(ctx, center: CGPoint(x: cx, y: cy), radius: cellW * 0.32,
                palette: palettes[idx])
    }
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

// MARK: - バリアント

func drawLight(into ctx: CGContext) {
    drawBackdrop(ctx, inner: rgb(0.10, 0.12, 0.22),
                      outer: rgb(0.02, 0.02, 0.05))
    drawGrid(ctx, palettes: [redGem, blueGem, yellowGem, greenGem])
}

func drawDark(into ctx: CGContext) {
    drawBackdrop(ctx, inner: rgb(0.05, 0.06, 0.13),
                      outer: rgb(0.00, 0.00, 0.02))
    drawGrid(ctx, palettes: [redGem, blueGem, yellowGem, greenGem])
}

func drawTinted(into ctx: CGContext) {
    ctx.setFillColor(rgb(0, 0, 0, 1))
    ctx.fill(CGRect(x: 0, y: 0, width: SIZE, height: SIZE))
    let monoA = GemPalette(
        topFacet: rgb(1, 1, 1), mid: rgb(0.8, 0.8, 0.8),
        bottomFacet: rgb(0.35, 0.35, 0.35), outline: rgb(0.15, 0.15, 0.15)
    )
    let monoB = GemPalette(
        topFacet: rgb(0.95, 0.95, 0.95), mid: rgb(0.65, 0.65, 0.65),
        bottomFacet: rgb(0.25, 0.25, 0.25), outline: rgb(0.10, 0.10, 0.10)
    )
    drawGrid(ctx, palettes: [monoA, monoB, monoB, monoA])
}

// MARK: - main

guard CommandLine.arguments.count == 2 else {
    print("usage: gen_app_icon <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

for (name, drawer) in [
    ("AppIcon-Light.png", drawLight),
    ("AppIcon-Dark.png", drawDark),
    ("AppIcon-Tinted.png", drawTinted),
] {
    let ctx = makeContext()
    drawer(ctx)
    writePNG(ctx, to: outDir.appendingPathComponent(name))
}
print("done")
