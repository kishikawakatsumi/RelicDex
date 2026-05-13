import Foundation
import UIKit

/// 動画取り込みの結果を Documents 配下に書き出すユーティリティ。
/// ユーザーは Files.app の「マイiPhone」→「RelicForge」配下から取り出せる。
enum VideoIngestExporter {

  struct Input {
    let diagnostics: VideoIngestService.Diagnostics?
    let panelROI: CGRect?
    let samplingFPS: Double
    let expectedSegments: Int?
    let candidates: [Candidate]

    struct Candidate {
      let recognized: RecognizedRelic
      let frameImage: UIImage
      let invalidReason: String?  // nil ならば valid
    }
  }

  /// 取り込み結果を Documents/ingest_<timestamp>/ 以下に書き出し、ルート URL を返す。
  static func export(_ input: Input) -> URL? {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let stamp = formatter.string(from: Date())
    let runDir = docs.appendingPathComponent("ingest_\(stamp)", isDirectory: true)
    let invalidDir = runDir.appendingPathComponent("needs_review", isDirectory: true)
    do {
      try fm.createDirectory(at: invalidDir, withIntermediateDirectories: true)
    } catch {
      print("[Exporter] failed to create dir: \(error)")
      return nil
    }

    writeSummary(input, to: runDir)
    writeNeedsReview(input.candidates, to: invalidDir)
    print("[Exporter] wrote run to \(runDir.path)")
    return runDir
  }

  // MARK: - Summary

  private static func writeSummary(_ input: Input, to dir: URL) {
    var dict: [String: Any] = [
      "samplingFPS": input.samplingFPS,
      "expectedSegments": input.expectedSegments as Any,
      "validCount": input.candidates.filter { $0.invalidReason == nil }.count,
      "invalidCount": input.candidates.filter { $0.invalidReason != nil }.count,
      "totalCandidates": input.candidates.count,
    ]
    if let roi = input.panelROI {
      dict["panelROI"] = [
        "x": roi.minX, "y": roi.minY,
        "width": roi.width, "height": roi.height,
      ]
    }
    if let d = input.diagnostics {
      dict["diagnostics"] = [
        "sampledFrames": d.sampledFrames,
        "totalRuns": d.totalRuns,
        "keptRuns": d.keptRuns,
        "ocrSucceeded": d.ocrSucceeded,
        "ocrFailed": d.ocrFailed,
        "frameExtractFailed": d.frameExtractFailed,
        "diffMedian": d.diffMedian,
        "diffP90": d.diffP90,
        "diffMax": d.diffMax,
        "firstFrameWidth": d.firstFrameSize.width,
        "firstFrameHeight": d.firstFrameSize.height,
      ]
    }
    if let data = try? JSONSerialization.data(withJSONObject: dict,
                                              options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: dir.appendingPathComponent("summary.json"))
    }
  }

  // MARK: - Needs review

  private static func writeNeedsReview(_ candidates: [Input.Candidate], to dir: URL) {
    let invalid = candidates.enumerated().filter { $1.invalidReason != nil }
    for (index, c) in invalid {
      let prefix = String(format: "%04d", index + 1)
      // image
      if let jpeg = c.frameImage.jpegData(compressionQuality: 0.85) {
        try? jpeg.write(to: dir.appendingPathComponent("\(prefix)_frame.jpg"))
      }
      // metadata
      let meta: [String: Any] = [
        "candidateIndex": index,
        "reason": c.invalidReason ?? "",
        "title": c.recognized.title ?? "",
        "displayName": c.recognized.displayName,
        "isUnique": c.recognized.isUnique,
        "color": String(describing: c.recognized.color),
        "depth": String(describing: c.recognized.depth),
        "slotCount": c.recognized.slotCount,
        "parsedSlotCount": c.recognized.parsedTitle?.slotCount as Any,
        "parsedColor": c.recognized.parsedTitle.map { String(describing: $0.color) } as Any,
        "parsedDepth": c.recognized.parsedTitle.map { String(describing: $0.depth) } as Any,
        "ocrLines": c.recognized.ocrLines.map { line -> [String: Any] in
          [
            "text": line.text,
            "alternatives": line.alternativeTexts,
            "x": line.boundingBox.minX,
            "y": line.boundingBox.minY,
            "w": line.boundingBox.width,
            "h": line.boundingBox.height,
            "confidence": line.confidence,
          ]
        },
        "slotsRecognized": c.recognized.slots.map { slot -> [String: Any] in
          [
            "main": slot.main.candidates.first.map { $0.effect.textJa } ?? "",
            "demerit": slot.demerit?.candidates.first.map { $0.effect.textJa } ?? "",
          ]
        },
      ]
      if let data = try? JSONSerialization.data(withJSONObject: meta,
                                                options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: dir.appendingPathComponent("\(prefix)_meta.json"))
      }
    }
  }
}
