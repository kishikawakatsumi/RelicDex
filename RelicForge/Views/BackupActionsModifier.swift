import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Collection / BuildList 両画面のツールバーで使う「データの書き出し / 共有 / 取り込み」
/// メニュー（•••）。
///
/// View として直接使えるよう `View` で実装してある: 呼び出し側が自前の
/// `ToolbarItem（placement: .topBarTrailing） { BackupActionsButton（） }` の中に
/// 置けば他のツールバーアイテムと同じ枠組みで並ぶ。
///（ViewModifier 形式で `.toolbar { }` を入れ子にすると iOS 26 のツールバー
///  グルーピングと干渉して並び順が崩れることがあるため。）
struct BackupActionsButton: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \StoredRelic.capturedAt, order: .reverse)
  private var relics: [StoredRelic]
  @Query private var allBuilds: [StoredBuild]

  @State private var showingImportFromURL = false
  @State private var showingImportFromFile = false
  @State private var isUploadingShare = false
  @State private var sharePayload: SharePayload?
  @State private var exportErrorMessage: String?
  @State private var pendingReview: PendingReviewPayload?
  @State private var guestSession: GuestSessionPayload?

  var body: some View {
    Menu {
      Button {
        exportData()
      } label: {
        Label("Export Data", systemImage: "square.and.arrow.up")
      }
      Button {
        uploadShare()
      } label: {
        Label("Share via URL", systemImage: "link")
      }
      .disabled(isUploadingShare)
      Divider()
      Button {
        showingImportFromURL = true
      } label: {
        Label("Import from URL", systemImage: "square.and.arrow.down")
      }
      Button {
        showingImportFromFile = true
      } label: {
        Label("Import from File", systemImage: "doc")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .sheet(isPresented: $showingImportFromURL) {
      ImportFromURLView(onOpenGuest: { payload in
        guestSession = GuestSessionPayload(payload: payload)
      })
    }
    .sheet(item: $pendingReview) { review in
      ImportFromURLView(
        initialPayload: review.payload,
        initialSourceLabel: review.sourceLabel,
        onOpenGuest: { payload in
          guestSession = GuestSessionPayload(payload: payload)
        }
      )
    }
    .fullScreenCover(item: $guestSession) { session in
      GuestSessionShell(payload: session.payload)
    }
    .fileImporter(
      isPresented: $showingImportFromFile,
      allowedContentTypes: [.data],
      allowsMultipleSelection: false
    ) { result in
      handleFilePickResult(result)
    }
    .alert("Export failed",
           isPresented: Binding(get: { exportErrorMessage != nil },
                                set: { if !$0 { exportErrorMessage = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(exportErrorMessage ?? "")
    }
    .sheet(item: $sharePayload) { payload in
      ActivityView(items: [payload.url])
    }
  }

  private func exportData() {
    do {
      let url = try RelicExportService.writeExportFile(relics: relics, builds: allBuilds)
      sharePayload = SharePayload(url: url)
    } catch {
      exportErrorMessage = error.localizedDescription
    }
  }

  private func uploadShare() {
    guard !isUploadingShare else { return }
    isUploadingShare = true
    Task {
      defer { isUploadingShare = false }
      do {
        let result = try await RelicShareService.upload(relics: relics, builds: allBuilds)
        sharePayload = SharePayload(url: result.url)
      } catch {
        exportErrorMessage = String(localized: "Share failed: \(error.localizedDescription)")
      }
    }
  }

  private func handleFilePickResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }
      let didStart = url.startAccessingSecurityScopedResource()
      defer { if didStart { url.stopAccessingSecurityScopedResource() } }
      do {
        let payload = try RelicImportService.loadFile(at: url)
        pendingReview = PendingReviewPayload(payload: payload, sourceLabel: url.lastPathComponent)
      } catch {
        exportErrorMessage = String(localized: "File load failed: \(error.localizedDescription)")
      }
    case .failure(let error):
      let nsError = error as NSError
      if nsError.code != NSUserCancelledError {
        exportErrorMessage = String(localized: "File selection failed: \(error.localizedDescription)")
      }
    }
  }
}

struct GuestSessionPayload: Identifiable {
  let payload: ExportPayload
  let id = UUID()
}

struct PendingReviewPayload: Identifiable {
  let payload: ExportPayload
  let sourceLabel: String?
  let id = UUID()
}
