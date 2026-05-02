import Foundation
import Vision
import UIKit

struct OCRLine: Identifiable {
  let id = UUID()
  /// Vision が最も信頼度の高いと判断したテキスト
  let text: String
  /// Vision が返した代替候補テキスト（text の他に最大2件）。
  /// 「鞭」が「刀」と読まれる等の漢字誤認識を救うため、後段の照合で全候補を試す。
  let alternativeTexts: [String]
  let boundingBox: CGRect
  let confidence: Float

  /// 主候補 + 代替候補をまとめたリスト
  var allCandidates: [String] { [text] + alternativeTexts }
}

enum OCRError: Error {
  case invalidImage
  case recognitionFailed(Error)
}

enum OCRMode {
  /// ライブスキャン向け。フレームレート優先で精度はやや落とす（.fast）。
  /// 安定検出で複数フレームを確認するので、最終的な品質は実用上問題ない。
  case live
  /// 写真ピッカー / 確定処理向け。1 枚のみを最大精度で読む（.accurate）。
  case accurate
}

final class OCRService {
  /// 各 OCR 行で取得する Vision 上位候補数
  private let candidatesPerLine = 3

  /// `languages` で認識言語を絞り込める。Vision はリストごとにモデルを走らせるので、
  /// 1 言語に絞ると 2 言語並列より大幅に高速化する（ja/en で ~2 倍差が出る）。
  /// デフォルトは ["ja-JP", "en-US"] を残し、呼び出し側で必要に応じて短く渡す。
  func recognizeLines(
    in image: UIImage,
    mode: OCRMode = .accurate,
    languages: [String] = ["ja-JP", "en-US"]
  ) async throws -> [OCRLine] {
    guard let cgImage = image.cgImage else {
      throw OCRError.invalidImage
    }

    return try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: OCRError.recognitionFailed(error))
          return
        }
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let lines: [OCRLine] = observations.compactMap { obs in
          let cands = obs.topCandidates(self.candidatesPerLine)
          guard let primary = cands.first else { return nil }
          let alts = cands.dropFirst().map { $0.string }
          return OCRLine(
            text: primary.string,
            alternativeTexts: Array(alts),
            boundingBox: obs.boundingBox,
            confidence: primary.confidence
          )
        }
        continuation.resume(returning: lines)
      }
      // 日本語は .fast だと数字や記号の誤読で全く使い物にならないので、
      // ライブ/正確モードどちらも .accurate を使う。mode は将来の最適化用に残す。
      _ = mode
      request.recognitionLevel = .accurate
      // 言語コレクションは「対応する 1 言語に絞り込まれている時だけ」有効にする。
      // 多言語（例: ja/en 両方指定） の状態で usesLanguageCorrection = true にすると、
      // Vision が先頭言語のコンテキストで補正をかけてしまい、別言語のテキストが
      // 崩れる（英語ロケールで日本語ゲーム画面を読むと日本語が誤認識される問題）。
      // ロック後の単一言語フェーズでは補正のメリット（品詞・連語の整合） が大きいので
      // ON にする。複数言語フェーズでは生の文字認識を優先する。
      request.usesLanguageCorrection = languages.count == 1
      request.recognitionLanguages = languages

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try handler.perform([request])
        } catch {
          continuation.resume(throwing: OCRError.recognitionFailed(error))
        }
      }
    }
  }
}
