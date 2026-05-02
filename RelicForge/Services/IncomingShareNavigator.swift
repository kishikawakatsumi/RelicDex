import Foundation
import SwiftUI
internal import Combine

@MainActor
final class IncomingShareNavigator: ObservableObject {
  @Published var pendingShareKey: String?

  func handle(url: URL) {
    if let key = try? RelicImportService.extractKey(from: url.absoluteString) {
      pendingShareKey = key
    }
  }
}
