import Foundation

@MainActor
enum RelicShareService {
  static let baseURL = URL(string: "https://relicforge.pages.dev")!

  enum ShareError: LocalizedError {
    case invalidResponse
    case http(status: Int)
    case decode

    var errorDescription: String? {
      switch self {
      case .invalidResponse:
        String(localized: "Invalid response from server")
      case .http(let s):
        "HTTP \(s)"
      case .decode:
        String(localized: "Failed to parse response")
      }
    }
  }

  struct UploadResult {
    let key: String
    let url: URL
  }

  static func upload(relics: [StoredRelic], builds: [StoredBuild]) async throws -> UploadResult {
    let data = try RelicExportService.makeExportData(relics: relics, builds: builds)

    var req = URLRequest(url: baseURL.appendingPathComponent("api/share"))
    req.httpMethod = "POST"
    req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    
    let lang = Locale.current.language.languageCode?.identifier ?? "en"
    req.setValue(lang, forHTTPHeaderField: "Content-Language")
    req.httpBody = data
    req.timeoutInterval = 30

    let (respData, response) = try await URLSession.shared.data(for: req)
    guard let httpResp = response as? HTTPURLResponse else {
      throw ShareError.invalidResponse
    }
    guard (200...299).contains(httpResp.statusCode) else {
      throw ShareError.http(status: httpResp.statusCode)
    }
    struct Body: Decodable { let key: String }
    guard let body = try? JSONDecoder().decode(Body.self, from: respData) else {
      throw ShareError.decode
    }
    let url = baseURL.appendingPathComponent("s/\(body.key)")
    return UploadResult(key: body.key, url: url)
  }
}
