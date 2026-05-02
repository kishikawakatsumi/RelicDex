import SwiftUI
import SwiftData

/// 共有 URL からデータを取り込み、自分のローカルデータに上書き保存する画面。
/// 復元用途と他人のビルド取り込みの両方を兼ねる。
///
/// UI フロー（4 段階）:
///   .idle      入力フィールド + 「読み込む」ボタン（右上）
///   .fetching  進捗インジケータのみ
///   .ready     取得内容のサマリ + アクションボタン（ゲストモード / 上書き） — 入力フィールドは引っ込める
///   .importing 上書き処理中の進捗
struct ImportFromURLView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  /// Universal Link 等から呼び出された場合に最初に投入する URL/key。
  /// 起動直後に自動で fetch するので、ユーザーは右上ボタンを押す必要がない。
  var initialInput: String? = nil

  /// ファイル読み込みなど、すでに payload が手元にあるケース。
  /// 与えられた場合は URL fetch をスキップして直接 .ready 状態で表示する。
  var initialPayload: ExportPayload? = nil

  /// `initialPayload` の出処表示（例: "my-export.relicforge"）。
  var initialSourceLabel: String? = nil

  /// 「ゲストモードで開く」を選んだときに、取得した payload を親に渡す。
  /// 親は fullScreenCover で GuestSessionShell を表示する想定。
  var onOpenGuest: ((ExportPayload) -> Void)? = nil

  @State private var input: String = ""
  @State private var phase: Phase = .idle
  @State private var fetched: ExportPayload?
  @State private var errorMessage: String?
  @State private var showingConfirm = false
  @State private var didImport = false

  enum Phase { case idle, fetching, ready, importing }

  var body: some View {
    NavigationStack {
      Form {
        // ── 入力 ────────────────────────────────────────────
        // .idle のときだけ入力フィールドを出す。
        // 取得が終わったらアクションに集中させるため引っ込める。
        if phase == .idle {
          Section {
            // iOS の URL 自動検出で placeholder が青リンク色になるのを避けるため、
            // `prompt:` で Text を明示し、明示的に secondary 色を当てる。
            TextField(
              "URL or key",
              text: $input,
              prompt: Text(verbatim: "https://relicforge.pages.dev/s/{key}")
                .foregroundStyle(.secondary)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.primary)
            .onSubmit { Task { await fetch() } }
          } header: {
            Text("URL or key")
          }
        }

        // ── 進捗 ────────────────────────────────────────────
        if phase == .fetching {
          Section {
            HStack { ProgressView(); Text("Loading data…") }
          }
        }
        if phase == .importing {
          Section {
            HStack { ProgressView(); Text("Overwriting…") }
          }
        }

        // ── 取得結果 ────────────────────────────────────────
        if let fetched, phase == .ready {
          if let label = sourceLabel {
            Section {
              HStack(spacing: 6) {
                Image(systemName: label.icon).foregroundStyle(.secondary)
                Text(label.text)
                  .font(.footnote.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer()
                if !input.isEmpty {
                  // URL 流入のときだけリセット可。ファイル流入は閉じて選び直し。
                  Button {
                    reset()
                  } label: {
                    Text("Edit")
                      .font(.footnote)
                  }
                }
              }
            }
          }
          Section("Loaded content") {
            LabeledContent("Relic") { Text("\(fetched.relics.count) 件") }
            LabeledContent("Builds") { Text("\(fetched.builds.count) 件") }
            LabeledContent("Exported at") {
              Text(fetched.exportedAt.formatted(date: .numeric, time: .shortened))
            }
            if !fetched.appVersion.isEmpty {
              LabeledContent("App version") { Text(fetched.appVersion) }
            }
          }
          Section {
            if onOpenGuest != nil {
              Button {
                onOpenGuest?(fetched)
                dismiss()
              } label: {
                Label("Open in Guest Mode", systemImage: "person.2")
              }
            }
            Button(role: .destructive) {
              showingConfirm = true
            } label: {
              Label("Overwrite My Data", systemImage: "square.and.arrow.down")
            }
          } footer: {
            Text("Guest mode: doesn't touch your data. Edit and re-share freely.\nOverwrite: replaces all your relics and builds with the imported data.")
          }
        }

        // ── エラー ────────────────────────────────────────
        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(initialPayload != nil ? "Import from File" : "Import from URL")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        // 「読み込む」は idle のときだけ表示。fetch 後はアクションが下にあるので不要。
        if phase == .idle {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Continue") { Task { await fetch() } }
              .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }
      .alert("Replace existing data?", isPresented: $showingConfirm) {
        Button("Replace", role: .destructive) { Task { await applyOverwrite() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("All current data will be deleted. We recommend backing up via Export Data first.")
      }
      .alert("Import complete", isPresented: $didImport) {
        Button("OK") { dismiss() }
      } message: {
        Text("Data was overwritten.")
      }
      .task {
        // ファイル等で payload が事前に渡されていれば直接 .ready
        if let initialPayload, fetched == nil {
          fetched = initialPayload
          phase = .ready
        }
        // Universal Link 等で URL/key が事前投入されていれば自動 fetch
        if let initialInput, input.isEmpty {
          input = initialInput
          await fetch()
        }
      }
    }
  }

  /// .ready 表示の上部に出す出処ラベル（URL key / ファイル名 / 無し）
  private var sourceLabel: (icon: String, text: String)? {
    if let key = try? RelicImportService.extractKey(from: input) {
      return ("link", key)
    }
    if let label = initialSourceLabel {
      return ("doc.fill", label)
    }
    return nil
  }

  private func fetch() async {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    phase = .fetching
    errorMessage = nil
    fetched = nil
    do {
      let payload = try await RelicImportService.fetch(from: trimmed)
      fetched = payload
      phase = .ready
    } catch {
      errorMessage = error.localizedDescription
      phase = .idle
    }
  }

  private func applyOverwrite() async {
    guard let payload = fetched else { return }
    phase = .importing
    errorMessage = nil
    do {
      try RelicImportService.replaceAll(with: payload, in: modelContext)
      didImport = true
    } catch {
      errorMessage = String(localized: "Overwrite failed: \(error.localizedDescription)")
      phase = .ready
    }
  }

  /// idle 状態に戻す。「変更」リンクから呼ばれる。`input` はそのまま残して
  /// ユーザが既に貼った URL を編集できるようにする（タイポ修正等）。
  private func reset() {
    fetched = nil
    errorMessage = nil
    phase = .idle
  }
}
