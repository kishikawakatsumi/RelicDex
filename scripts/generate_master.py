#!/usr/bin/env python3
"""
公式に近いTSVデータから、アプリで扱う2つのマスターJSONを生成する。

入力:
  /Users/katsumi/Documents/Relics/遺物-遺物.tsv         JP一般遺物効果一覧
  /Users/katsumi/Documents/Relics/Relics-Relics.tsv     EN（グループ/カテゴリ翻訳のみ）
  /Users/katsumi/Documents/Relics/固有遺物-Table 1.tsv  JP固有遺物
  /Users/katsumi/Documents/Relics/Unique Relics-Table 1.tsv  EN固有遺物（未翻訳）

出力:
  RelicForge/Resources/effects.json
  RelicForge/Resources/unique_relics.json
"""
from __future__ import annotations
import csv
import hashlib
import json
import re
import unicodedata
from pathlib import Path

ROOT = Path("/Users/katsumi/Documents/Relics")
JP_FX = ROOT / "遺物-遺物.tsv"
EN_FX = ROOT / "Relics-Relics.tsv"
JP_UQ = ROOT / "固有遺物-Table 1.tsv"
EN_UQ = ROOT / "Unique Relics-Table 1.tsv"

OUT_DIR = Path(__file__).resolve().parent.parent / "RelicForge/Resources"
WEB_OUT_DIR = Path(__file__).resolve().parent.parent / "web/public/master"
OUT_DIR.mkdir(parents=True, exist_ok=True)
WEB_OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_FX = OUT_DIR / "effects.json"
OUT_UQ = OUT_DIR / "unique_relics.json"

# ── マッピング: 日本語カテゴリ → アプリの Category enum ─────────────────
# キーは Swift `RelicEffect.Category` の rawValue と必ず一致させる。
CATEGORY_MAP = {
    "能力値": "attributes",
    "攻撃力": "attackPower",
    "スキル／アーツ": "characterSkills",
    "魔術／祈祷": "spells",
    "カット率": "damageNegation",
    "状態異常耐性": "ailmentResistance",
    "回復": "restoration",
    "アクション": "actions",
    "出撃時の武器（戦技）": "startingArmamentSkill",
    # （付加）は属性付与か状態異常付与かでさらに分岐（determine_category 参照）
    "出撃時の武器（付加）": "startingArmamentImbue",
    "出撃時の武器（魔術／祈祷）": "startingArmamentSpell",
    "出撃時のアイテム": "startingItem",
    "出撃時のアイテム（結晶の雫）": "startingItemTear",
    "マップ環境": "environment",
    "チームメンバー": "teamMembers",
    # デメリット
    "デメリット（能力値）": "demerits",
    "デメリット（カット率）": "demerits",
    "デメリット（アクション）": "demerits",
    # キャラ別
    "追跡者": "characterSpecific",
    "守護者": "characterSpecific",
    "鉄の目": "characterSpecific",
    "レディ": "characterSpecific",
    "無頼漢": "characterSpecific",
    "復讐者": "characterSpecific",
    "隠者": "characterSpecific",
    "執行者": "characterSpecific",
    "学者": "characterSpecific",
    "葬儀屋": "characterSpecific",
    # 武器種別
    "短剣": "armamentSpecific", "直剣": "armamentSpecific", "大剣": "armamentSpecific", "特大剣": "armamentSpecific",
    "刺剣": "armamentSpecific", "重刺剣": "armamentSpecific", "曲剣": "armamentSpecific", "大曲剣": "armamentSpecific",
    "刀": "armamentSpecific", "両刃剣": "armamentSpecific", "斧": "armamentSpecific", "大斧": "armamentSpecific",
    "槌": "armamentSpecific", "フレイル": "armamentSpecific", "大槌": "armamentSpecific", "特大武器": "armamentSpecific",
    "槍": "armamentSpecific", "大槍": "armamentSpecific", "斧槍": "armamentSpecific", "鎌": "armamentSpecific",
    "鞭": "armamentSpecific", "拳": "armamentSpecific", "爪": "armamentSpecific",
    "弓": "armamentSpecific", "大弓": "armamentSpecific", "クロスボウ": "armamentSpecific", "バリスタ": "armamentSpecific",
    "小盾": "armamentSpecific", "中盾": "armamentSpecific", "大盾": "armamentSpecific",
    "杖": "armamentSpecific", "聖印": "armamentSpecific",
}

DEMERIT_GROUP = "デメリット"
LOADOUT_NEUTRAL_CATEGORIES = {
    "出撃時の武器（戦技）",
    "出撃時の武器（魔術／祈祷）",
    "出撃時のアイテム",
    "出撃時のアイテム（結晶の雫）",
}

UTILITY_NEUTRAL_PATTERNS = [
    "ガード中、敵に狙われやすくする",
    "ジェスチャー",
]

JP_COLOR_TO_EN = {
    "赤": "red", "赤色": "red",
    "青": "blue", "青色": "blue",
    "黄": "yellow", "黄色": "yellow",
    "緑": "green", "緑色": "green",
}


def normalize_text(s: str) -> str:
    """効果テキストの正規化。
    - 改行は **保持** する（ゲーム画面通りの折り返し位置を表現する）
    - 行頭/末尾の空白を整えた上で、空行は除去
    - 注釈行（※...） はゲーム表示にも出るので **保持** する
    """
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.strip() for line in s.split("\n")]
    lines = [line for line in lines if line]
    return "\n".join(lines)


def slugify_id(s: str, prefix: str, idx: int) -> str:
    """text-stable な ID を生成する。
    SHA-256（s） の先頭 8 hex を採用。同じ JA テキスト → 必ず同じ ID なので、
    TSV の順序や件数が変わっても ID が動かない（= ストア済み effectId が
    無効化されない）。`idx` 引数は signature 互換のために残してあるが未使用。
    """
    del idx  # unused; kept for backward-compat callers
    h = hashlib.sha256(s.encode("utf-8")).hexdigest()[:8]
    return f"{prefix}_{h}"


def determine_category(group: str, category_ja: str, text: str) -> str:
    if "出撃時の武器（付加）" == category_ja:
        # 「武器に状態異常を付加する」効果と「属性（火・雷など） を付加する」効果は
        # ゲームメカニクス上区別したいので別カテゴリにする。
        if "の状態異常を付加" in text:
            return "startingArmamentAilment"
        return "startingArmamentImbue"
    return CATEGORY_MAP.get(category_ja, "actions")


# ── TSV パース ─────────────────────────────────────────────────────────
def read_tsv_rows(path: Path) -> list[list[str]]:
    """CSV風の引用付きTSVをパース。multi-line quoted fields を正しく扱う。"""
    with path.open(encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t", quotechar='"')
        return [row for row in reader]


def parse_effects(jp_path: Path, en_path: Path) -> list[dict]:
    jp_rows = read_tsv_rows(jp_path)
    en_rows = read_tsv_rows(en_path)

    # 行数が一致しているはず
    if len(jp_rows) != len(en_rows):
        print(f"WARN: row count mismatch JP={len(jp_rows)} EN={len(en_rows)}")

    effects: list[dict] = []
    last_group_ja = ""
    last_group_en = ""
    last_category_ja = ""
    last_category_en = ""

    for i, jp in enumerate(jp_rows):
        if i == 0:
            continue  # header
        if len(jp) < 3:
            continue
        group_ja = jp[0].strip() or last_group_ja
        category_ja = jp[1].strip() or last_category_ja
        text_ja = normalize_text(jp[2].strip())
        if not text_ja:
            continue
        last_group_ja = group_ja
        last_category_ja = category_ja

        # English columns (group / category / effect text)
        group_en = ""
        category_en = ""
        text_en: str | None = None
        if i < len(en_rows) and len(en_rows[i]) >= 3:
            en = en_rows[i]
            ge = en[0].strip()
            ce = en[1].strip()
            te = normalize_text(en[2].strip())
            if ge:
                group_en = ge
                last_group_en = ge
            else:
                group_en = last_group_en
            if ce:
                category_en = ce
                last_category_en = ce
            else:
                category_en = last_category_en
            if te:
                text_en = te

        category = determine_category(group_ja, category_ja, text_ja)

        effect = {
            "id": "",  # set after dedupe
            "textJa": text_ja,
            "textEn": text_en,
            "groupJa": group_ja,
            "groupEn": group_en or None,
            "categoryJa": category_ja,
            "categoryEn": category_en or None,
            "category": category,
        }
        effects.append(effect)

    # 重複排除（textJa基準）+ 連番ID
    seen: dict[str, dict] = {}
    for e in effects:
        if e["textJa"] in seen:
            # 既存の方が優先（最初の出現）。グループ情報の更新は不要
            continue
        seen[e["textJa"]] = e

    # TSV の出現順を保持（フィルタピッカーや一覧の並び順は元データの順番に従う）
    ordered = list(seen.values())
    for idx, e in enumerate(ordered, 1):
        e["id"] = slugify_id(e["textJa"], "e", idx)
    return ordered


def parse_unique_relics(jp_path: Path, en_path: Path | None = None) -> list[dict]:
    jp_rows = read_tsv_rows(jp_path)
    en_rows = read_tsv_rows(en_path) if en_path else []
    en_names = _extract_unique_names(en_rows)

    relics: list[dict] = []
    current: dict | None = None
    for i, row in enumerate(jp_rows):
        if i == 0:
            continue
        if len(row) < 2:
            continue
        name = row[0].strip()
        effect_text = normalize_text(row[1].strip())
        color_ja = row[2].strip() if len(row) > 2 else ""

        if name:
            # 新しい固有遺物
            if current is not None:
                relics.append(current)
            current = {
                "id": "",
                "nameJa": name,
                "nameEn": None,
                "color": JP_COLOR_TO_EN.get(color_ja, "unknown"),
                "effectsJa": [],
            }
        if current is None:
            continue
        if effect_text:
            current["effectsJa"].append(effect_text)

    if current is not None:
        relics.append(current)

    # 連番ID + EN 名のペアリング（TSV の出現順で 1:1 対応する前提）
    for idx, r in enumerate(relics, 1):
        r["id"] = f"u_{idx:03d}"
        if idx - 1 < len(en_names):
            r["nameEn"] = en_names[idx - 1]
    return relics


def _extract_unique_names(rows: list[list[str]]) -> list[str]:
    """name 列が非空の行から名前だけを抽出する（固有遺物 1 件 = 1 名前）。"""
    names: list[str] = []
    for i, row in enumerate(rows):
        if i == 0:
            continue
        if not row:
            continue
        name = row[0].strip()
        if name:
            names.append(name)
    return names


def link_unique_effects(uniques: list[dict], effects: list[dict]) -> list[dict]:
    """固有遺物の効果テキストを effects マスターのIDに変換する。
    マスターに無い場合は textJa をそのまま保持する（ロードアウト系で表記揺れがあり得る）。"""
    by_text: dict[str, str] = {e["textJa"]: e["id"] for e in effects}
    for u in uniques:
        u["effects"] = []
        for text in u["effectsJa"]:
            ref = {"textJa": text, "effectId": by_text.get(text)}
            u["effects"].append(ref)
        del u["effectsJa"]
    return uniques


def write_title_words():
    """遺物タイトルを構成する単語マスタ（size / color / depth）。
    iOS / Web の両方で同じファイルを使い、ロケールに応じて遺物名を組み立てる。

    JP の文法: `{size}な{color}{depth}` （例: 端正な燃える昏景）
    EN の文法: `[Deep ]{size} {color} {depth}` （例: Deep Polished Burning Scene）
    """
    payload = {
        "version": 1,
        "sizes": [
            {"slotCount": 1, "ja": "繊細", "en": "Delicate"},
            {"slotCount": 2, "ja": "端正", "en": "Polished"},
            {"slotCount": 3, "ja": "壮大", "en": "Grand"},
        ],
        "colors": [
            {"color": "red",    "ja": "燃える", "en": "Burning"},
            {"color": "blue",   "ja": "滴る",   "en": "Drizzly"},
            {"color": "yellow", "ja": "輝く",   "en": "Luminous"},
            {"color": "green",  "ja": "静まる", "en": "Tranquil"},
        ],
        "depths": [
            {"depth": "normal", "ja": "景色", "en": "Scene"},
            {"depth": "deep",   "ja": "昏景", "en": "Scene", "enPrefix": "Deep"},
        ],
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    (OUT_DIR / "title_words.json").write_text(text, encoding="utf-8")
    (WEB_OUT_DIR / "title_words.json").write_text(text, encoding="utf-8")
    print(f"wrote: title_words.json")


def main():
    effects = parse_effects(JP_FX, EN_FX)
    uniques = parse_unique_relics(JP_UQ, EN_UQ)
    uniques = link_unique_effects(uniques, effects)

    # 統計
    print(f"effects:  {len(effects)}")
    print(f"unique relics: {len(uniques)}")
    unmatched = sum(1 for u in uniques for e in u["effects"] if e["effectId"] is None)
    print(f"unmatched unique effect text references: {unmatched}")

    fx_payload = json.dumps({"version": 1, "effects": effects}, ensure_ascii=False, indent=2)
    uq_payload = json.dumps({"version": 1, "uniqueRelics": uniques}, ensure_ascii=False, indent=2)

    OUT_FX.write_text(fx_payload, encoding="utf-8")
    OUT_UQ.write_text(uq_payload, encoding="utf-8")
    # Web 版にも同じ内容を配置（両プラットフォームで同期）
    (WEB_OUT_DIR / "effects.json").write_text(fx_payload, encoding="utf-8")
    (WEB_OUT_DIR / "unique_relics.json").write_text(uq_payload, encoding="utf-8")

    # characters.json と vessels.json は generate_build_master.py が
    # iOS リソース側に書き出しているので、Web 用にコピーだけする（生成しない）。
    for name in ("characters.json", "vessels.json"):
        src = OUT_DIR / name
        if src.exists():
            (WEB_OUT_DIR / name).write_text(src.read_text(encoding="utf-8"), encoding="utf-8")

    write_title_words()

    print(f"wrote: {OUT_FX}")
    print(f"wrote: {OUT_UQ}")
    print(f"wrote: {WEB_OUT_DIR}/*.json")


if __name__ == "__main__":
    main()
