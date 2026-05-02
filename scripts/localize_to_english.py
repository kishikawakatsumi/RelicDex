#!/usr/bin/env python3
"""
Swift ソース内の日本語 UI 文字列を英語に置換し、
Localizable.xcstrings に英語ベース + 日本語訳を出力する。

前提:
- 文字列は double-quoted literal として現れる
- `\\（...）` 補間部分は両言語で同じ位置に保持する
- 遺物名構築用の単語（壮大/端正/繊細/燃える/滴る/輝く/静まる/景色/昏景/な）
  は UI 文字列ではないので翻訳マップに含めず、ソース側で温存される
"""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DIR = ROOT / "RelicForge"
SWIFT_DIRS = ["Views", "Services", "Models"]
CATALOG = APP_DIR / "Localizable.xcstrings"

# --- 翻訳マップ（JA → EN） ---
# Swift の文字列リテラル（補間 `\（...）` を含む） と完全一致でマッチさせる。
TRANSLATIONS: dict[str, str] = {
    # ── タブ / ナビゲーション ──
    "コレクション": "Collection",
    "ビルド": "Builds",

    # ── 共通アクション ──
    "保存": "Save",
    "削除": "Delete",
    "閉じる": "Close",
    "キャンセル": "Cancel",
    "完了": "Done",
    "終了": "Exit",
    "クリア": "Clear",
    "破棄": "Discard",
    "破棄して閉じる": "Discard and Close",
    "選択を解除": "Clear Selection",
    "すべて選択": "Select All",
    "すべて解除": "Deselect All",
    "すべて選択解除": "Deselect All",

    # ── フィルタチップ ──
    # 「特色」はゲーム内表記の "Characteristics" に合わせる
    "特色": "Characteristics",
    "大きさ": "Size",
    "種別": "Type",
    "効果": "Effects",
    "お気に入り": "Favorites",

    # ── サイズラベル ──
    "小": "Small",
    "中": "Medium",
    "大": "Large",

    # ── 色ラベル（UI のみ。遺物名構築には使われない） ──
    "赤色": "Red",
    "青色": "Blue",
    "黄色": "Yellow",
    "緑色": "Green",
    "不明": "Unknown",

    # ── 種別ラベル ──
    "通常": "Normal",
    "深層": "Deep",
    "遺物": "Relic",
    "深層の遺物": "Depths Relic",

    # ── ミスマッチ理由 ──
    "色違い": "Color mismatch",
    "深層用": "Deep only",
    "通常用": "Normal only",
    "他スロット装備中": "Equipped elsewhere",

    # ── ビルドエディタ ──
    "メタ情報": "Meta",
    "通常スロット": "Normal Slots",
    "深層スロット": "Deep Slots",
    "効果サマリ": "Effect Summary",
    "ビルド名": "Build Name",
    "名称未設定": "Untitled",
    "名前": "Name",
    "献器": "Vessel",
    "献器を選択": "Select Vessel",
    "献器: 未選択": "Vessel: Not selected",
    "装備なし": "Empty",
    "装備を外す": "Unequip",
    "メイン効果": "Main Effect",
    "デメリット効果": "Demerit",
    "メイン効果を選択": "Select main effect",
    "デメリットを選択（任意）": "Select demerit（optional）",
    "デメリットなし": "No demerit",
    "メイン効果を選び直す": "Change main effect",
    "デメリット効果を選び直す": "Change demerit",
    "効果を選ぶ": "Choose effect",
    "効果を追加（\\（selected.count） 件選択中）": "Add effects（\\（selected.count） selected）",
    "カテゴリを選ぶ": "Choose category",
    "効果フィルタ": "Effect Filters",
    "効果フィルタ \\（idx + 1）": "Effect filter \\（idx + 1）",
    "このフィルタを解除": "Clear this filter",
    "効果テキストを検索": "Search effect text",
    "効果テキストを検索（例: 物理攻撃力）": "Search effect text（e.g., Physical Attack）",
    "選んだ効果は OR （どれかを持つ遺物が表示されます）。\\n+1 / +2 などの段階は区別されません。":
        "Selected effects use OR (relics with any are shown).\\n+1 / +2 stages are not distinguished.",
    "効果なし": "No effects",
    "（効果なし）": "（none）",
    "（タイトル未検出）": "（title not detected）",
    "（未選択）": "（not selected）",
    "効果（\\（total））": "Effects（\\（total））",

    # ── ビルド一覧 ──
    "通常 \\（n）/3 ・ 深層 \\（d）/3": "Normal \\（n）/3 ・ Deep \\（d）/3",
    "このビルドを削除しますか？": "Delete this build?",
    "このキャラのビルドはまだありません。\\n右上の + から作成できます。":
        "No builds for this character yet.\\nTap + at the top right to create one.",
    "装備された効果はまだありません。": "No effects equipped yet.",

    # ── 献器ピッカー ──
    "\\（characterDisplayName） 専用": "\\（characterDisplayName） only",
    "共通": "Common",

    # ── コレクション ──
    "まだ遺物が登録されていません。\\n右上の + から追加してください。":
        "No relics yet.\\nTap + at the top right to add one.",
    "条件に一致する遺物がありません。": "No relics match the filters.",
    "削除できません": "Cannot delete",
    "「\\（relic.name）」はビルドで使用中: \\（names）":
        "\"\\(relic.name)\" is used in builds: \\(names)",
    "この遺物はビルドで使用中です: \\（names）\\n\\n先にビルドから外してください。":
        "This relic is used in builds: \\(names)\\n\\nUnequip it from those builds first.",
    "「\\（relic.name）」はお気に入り登録されています":
        "\"\\(relic.name)\" is favorited",
    "この遺物はお気に入り登録されています。\\n先にお気に入りを解除してください。":
        "This relic is favorited.\\nRemove it from favorites first.",
    "\\n\\n先にお気に入り解除またはビルドから外してください。":
        "\\n\\nRemove from favorites or unequip from builds first.",
    "この遺物を削除しますか？": "Delete this relic?",
    "お気に入りに追加": "Add to Favorites",
    "お気に入りを解除": "Remove from Favorites",

    # ── 追加メニュー ──
    "カメラで追加": "Add with Camera",
    "手動で追加": "Add Manually",
    "データを書き出す": "Export Data",
    "URL で共有": "Share via URL",
    "URL から読み込む": "Import from URL",
    "ファイルから読み込む": "Import from File",

    # ── インポート画面 ──
    "URL を入力": "Enter URL",
    "受信した共有 URL を貼り付けるか、key 単体を入力してください。":
        "Paste a share URL, or enter a key.",
    "https://relicforge.pages.dev/s/{key} または key":
        "https://relicforge.pages.dev/s/{key} or key",
    "読み込む": "Load",
    "別の URL": "Another URL",
    "取得した内容": "Loaded content",
    "アプリ版": "App version",
    "エクスポート日時": "Exported at",
    "ゲストモードで開く": "Open in Guest Mode",
    "自分のデータに上書き保存": "Overwrite My Data",
    "ゲストモード: 自分のデータには影響しません。編集 / 再共有して試行錯誤できます。\\n上書き保存: 現在保存されている遺物・ビルドはすべて削除されて取り込んだ内容に置き換わります。":
        "Guest mode: doesn't touch your data. Edit and re-share freely.\\nOverwrite: replaces all your relics and builds with the imported data.",
    "上書きしますか？": "Replace existing data?",
    "上書きする": "Replace",
    "現在のデータはすべて削除されます。先に「データを書き出す」でバックアップしておくことをおすすめします。":
        "All current data will be deleted. We recommend backing up via Export Data first.",
    "取り込み完了": "Import complete",
    "データを上書き保存しました。": "Data was overwritten.",
    "上書き中…": "Overwriting…",
    "データを取得中…": "Loading data…",
    "上書き保存に失敗しました: \\（error.localizedDescription）":
        "Overwrite failed: \\(error.localizedDescription)",
    "ファイル読み込み失敗: \\（error.localizedDescription）":
        "File load failed: \\(error.localizedDescription)",
    "ファイル選択失敗: \\（error.localizedDescription）":
        "File selection failed: \\(error.localizedDescription)",
    "共有に失敗しました: \\（error.localizedDescription）":
        "Share failed: \\(error.localizedDescription)",
    "書き出しに失敗しました": "Export failed",
    "読み込み失敗: \\（loadError）": "Load failed: \\（loadError）",

    # ── ゲストモード ──
    "ゲストモード ・ 編集はこの端末に保存されません":
        "Guest Mode ・ Edits are not saved on this device",

    # ── スキャン候補 / 確定 ──
    "スキャン候補（\\（session.count））": "Scan Candidates（\\（session.count））",
    "候補がありません": "No candidates",
    "候補をすべて破棄": "Discard All",
    "候補をすべて破棄しますか？": "Discard all candidates?",
    "候補が \\（session.count） 件あります": "\\（session.count） candidates pending",
    "保存していない候補は破棄されます。続けますか?":
        "Unsaved candidates will be discarded. Continue?",
    "選択した\\（session.selectedCount）件を保存": "Save \\（session.selectedCount） selected",
    "\\（session.selectedCount） / \\（session.count） 件 選択中":
        "\\(session.selectedCount) / \\(session.count) selected",
    "認識完了（候補に追加）": "Recognized（added to candidates）",
    "認識中…": "Recognizing…",
    "効果テキストを読み取り中…": "Reading effect text…",
    "遺物の説明のタイトルを枠に収めてください": "Fit the relic description title in the frame",
    "黄色い枠に遺物の説明を合わせてください": "Align the relic description with the yellow frame",
    "カメラを遺物の説明に合わせる": "Aim the camera at the relic description",
    "一時停止中": "Paused",
    "コンパクトへ": "To Compact",
    "ワイドへ": "To Wide",

    # ── カメラ権限 / 失敗 ──
    "カメラへのアクセスが拒否されています": "Camera access is denied",
    "設定アプリから「カメラ」を許可してください。": "Please allow camera access from Settings.",
    "カメラを初期化できませんでした": "Failed to initialize camera",
    "ビデオ出力を追加できませんでした": "Failed to add video output",

    # ── 遺物詳細 ──
    "登録情報": "Registration Info",
    "登録日: \\（relic.capturedAt.formatted（date: .abbreviated, time: .shortened））":
        "Registered: \\(relic.capturedAt.formatted(date: .abbreviated, time: .shortened))",
    "OCR原文": "OCR Source",
    "OCR上位候補": "OCR Top Candidates",
    "固有": "Unique",
    "固有遺物": "Unique Relic",
    "固有遺物は効果固定（編集不可）": "Unique relic effects are fixed（not editable）",
    "スロット \\（index + 1）": "Slot \\（index + 1）",

    # ── 遺物ピッカー ──
    "遺物を選択": "Select Relic",
    "\\（kindName） ・ スロット色: \\（colorName）": "\\（kindName） ・ Slot color: \\（colorName）",
    "該当する遺物がありません。": "No relics match.",
    "全効果（\\（filtered.count））": "All Effects（\\（filtered.count））",
    "検索結果（\\（filtered.count））": "Results（\\（filtered.count））",

    # ── インポート/共有エラー ──
    "サーバーから不正な応答が返りました": "Invalid response from server",
    "データを解凍できませんでした": "Failed to decompress data",
    "データを解析できませんでした": "Failed to parse data",
    "応答を解析できませんでした": "Failed to parse response",
    "URL を解析できませんでした": "Failed to parse URL",
    "データ取得に失敗（HTTP \\（s））": "Fetch failed（HTTP \\（s））",
    "未対応のスキーマバージョンです（\\（v））": "Unsupported schema version（\\（v））",
}


def replace_swift_files() -> int:
    updated = 0
    # 長いキーから先に置換（短いキーが部分一致してしまうのを避ける）
    keys = sorted(TRANSLATIONS.keys(), key=lambda s: -len(s))
    for d in SWIFT_DIRS:
        for path in (APP_DIR / d).rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            new_text = text
            for ja in keys:
                en = TRANSLATIONS[ja]
                new_text = new_text.replace(f'"{ja}"', f'"{en}"')
            if new_text != text:
                path.write_text(new_text, encoding="utf-8")
                updated += 1
                print(f"updated: {path.relative_to(ROOT)}")
    return updated


# ── Catalog 流し込み（auto-extraction フレンドリー） ────────────────────────
#
# Xcode が `Localizable.xcstrings` を Swift ソースから自動抽出した状態を前提に、
# このスクリプトは TRANSLATIONS マップ（JA → EN） を見て JA 翻訳だけを差し込む。
#
# 利点:
# - format 文字列（`%lld` / `%@` / `%1$lld` 等） の生成は Xcode に任せる
#   （型推定・位置指定の有無も Xcode が自動判定するので確実）
# - 予約語に近いキー（例: "Type"） も Xcode の auto-extracted エントリは
#   通るので、`extractionState: "manual"` を付けない限り問題にならない
# - 他言語（将来追加） や comment は触らないので、Xcode UI と共存できる

PH_MARKER = "\x00PH\x00"

# 抽出済み Catalog のプレースホルダ（例: %lld, %@, %1$lld） 全形式
CATALOG_PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:lld|@|f|d)")
# Swift 文字列リテラル中の補間 \（expr）
SWIFT_PLACEHOLDER_RE = re.compile(r"\\\([^)]*\)")


def swift_unescape(s: str) -> str:
    """Swift ソースの文字列リテラル中エスケープを実際の文字に変換する。
    Catalog のキーは生の改行/タブ/引用符を持つので、Python dict 内の `\\n` 等を
    実文字へ変換した上で shape を比較する。"""
    # 順序重要: 先に backslash 自体を退避してから他を処理
    return (s
            .replace("\\\\", "\x00")
            .replace("\\n", "\n")
            .replace("\\t", "\t")
            .replace("\\\"", "\"")
            .replace("\x00", "\\"))


def shape(s: str, *, swift_source: bool = False) -> str:
    """補間 / format 指定子を共通マーカーに置き換えた骨格を返す。
    Swift の '\\（...）' と Catalog の '%lld' / '%@' / '%1$lld' を同一視できる。
    `swift_source=True` のときはエスケープシーケンス（`\\n` 等） を実文字に展開する。
    """
    if swift_source:
        s = swift_unescape(s)
    s = SWIFT_PLACEHOLDER_RE.sub(PH_MARKER, s)
    s = CATALOG_PLACEHOLDER_RE.sub(PH_MARKER, s)
    return s


def transcode_to_catalog_value(swift_literal: str, catalog_key: str) -> str:
    """Swift 側のリテラル（'\\（...）' 入り） の補間箇所を、catalog_key に
    含まれる format 指定子（%lld / %@ / %1$lld） で 1 対 1 に置換する。
    `\\n` 等のエスケープも実文字に展開する。
    """
    placeholders = CATALOG_PLACEHOLDER_RE.findall(catalog_key)
    # まず補間部分を抽出してから、残りをエスケープ展開する
    parts = re.split(r"(\\\([^)]*\))", swift_literal)
    out: list[str] = []
    idx = 0
    for part in parts:
        if SWIFT_PLACEHOLDER_RE.fullmatch(part):
            if idx < len(placeholders):
                out.append(placeholders[idx])
                idx += 1
            else:
                out.append（"%@"）  # フォールバック（理屈上は来ない）
        else:
            out.append(swift_unescape(part))
    return "".join(out)


def apply_translations() -> None:
    """既存の Localizable.xcstrings を読み込み、TRANSLATIONS に対応する
    JA 翻訳を `localizations.ja` に追加する。
    既存の他言語訳・extractionState・comment は触らない。"""
    if not CATALOG.exists():
        print(f"NOT FOUND: {CATALOG.relative_to(ROOT)}\n"
              "  → 先に Xcode でビルドして Catalog を生成してください。"）
        return

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.setdefault("strings", {})

    # JA Swift literal を shape で索引可能にする（Swift エスケープを展開して比較）
    ja_by_shape: dict[str, str] = {}
    duplicates: list[str] = []
    for ja_swift, en_swift in TRANSLATIONS.items():
        sh = shape(en_swift, swift_source=True)
        if sh in ja_by_shape and ja_by_shape[sh] != ja_swift:
            duplicates.append(sh)
        ja_by_shape[sh] = ja_swift

    updated = 0
    unchanged = 0
    not_in_dict: list[str] = []

    for catalog_key, entry in strings.items():
        sh = shape(catalog_key)
        ja_swift = ja_by_shape.get(sh)
        if ja_swift is None:
            not_in_dict.append(catalog_key)
            continue
        ja_value = transcode_to_catalog_value(ja_swift, catalog_key)
        loc = entry.setdefault("localizations", {})
        existing = loc.get("ja", {}).get("stringUnit", {}).get("value")
        if existing == ja_value:
            unchanged += 1
            continue
        loc["ja"] = {
            "stringUnit": {
                "state": "translated",
                "value": ja_value,
            }
        }
        updated += 1

    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"applied JA translations: {updated} updated, {unchanged} already up-to-date")
    if not_in_dict:
        print(f"\n--- {len(not_in_dict)} keys without JA in TRANSLATIONS ---")
        for k in not_in_dict[:30]:
            print(f"  {k}")
        if len(not_in_dict) > 30:
            print(f"  ... and {len(not_in_dict) - 30} more")
    if duplicates:
        print(f"\n--- {len(duplicates)} shape collisions in TRANSLATIONS ---")


def main():
    """通常運用: Swift ソース置換 + Catalog 翻訳流し込み。
    初回 EN 化が済んでいるので、置換対象が無くても害はない。"""
    n = replace_swift_files()
    if n > 0:
        print(f"\n--- swift files updated: {n} ---\n")
    apply_translations()


if __name__ == "__main__":
    main()
