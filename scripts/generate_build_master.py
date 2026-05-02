#!/usr/bin/env python3
"""
ビルド機能用のマスターデータ（キャラクター + 器） を生成する叩き台スクリプト。

入力データの出典:
  https://github.com/sterance/nightreign-build-calculator (MIT License)
  client/src/data/nightfarers.json と vessels.json から派生。

出力:
  RelicForge/Resources/characters.json
  RelicForge/Resources/vessels.json

注: 日本語名（nameJa, descriptionJa） は叩き台として埋めているが、
    ユーザー側で公式表記に揃える前提。
"""
from __future__ import annotations
import json
import urllib.request
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "RelicForge/Resources"

NIGHTFARERS_URL = "https://raw.githubusercontent.com/sterance/nightreign-build-calculator/main/client/src/data/nightfarers.json"
VESSELS_URL = "https://raw.githubusercontent.com/sterance/nightreign-build-calculator/main/client/src/data/vessels.json"

# 英→日 キャラ名マッピング（公式翻訳）
CHAR_NAME_JA = {
    "wylder":     "追跡者",
    "guardian":   "守護者",
    "ironeye":    "鉄の目",
    "duchess":    "レディ",
    "raider":     "無頼漢",
    "revenant":   "復讐者",
    "recluse":    "隠者",
    "executor":   "執行者",
    "scholar":    "学者",
    "undertaker": "葬儀屋",
}

# キャラのカテゴリキー（英） → キャラID
CATEGORY_TO_CHAR = {
    "wylderChalices":     "wylder",
    "guardianChalices":   "guardian",
    "ironeyeChalices":    "ironeye",
    "duchessChalices":    "duchess",
    "raiderChalices":     "raider",
    "revenantChalices":   "revenant",
    "recluseChalices":    "recluse",
    "executorChalices":   "executor",
    "scholarChalices":    "scholar",
    "undertakerChalices": "undertaker",
}


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read())


def build_characters(nightfarers_data: dict) -> list[dict]:
    forsaken = set(nightfarers_data.get("forsakenNightfarers", []))
    return [
        {
            "id": name,
            "nameJa": CHAR_NAME_JA.get(name, name),
            "nameEn": name.capitalize(),
            "isForsaken": name in forsaken,
        }
        for name in nightfarers_data["nightfarers"]
    ]


def build_vessels(vessels_data: dict) -> list[dict]:
    out: list[dict] = []
    seq = 1

    def vessel_record(item: dict, character_id: str | None) -> dict:
        nonlocal seq
        rec = {
            "id": f"v_{seq:03d}",
            "nameJa": "",  # ユーザー側で公式名を入れる
            "nameEn": item["name"],
            "characterId": character_id,  # null = 共通（generic）
            "baseSlots": item["baseSlots"],   # 通常スロット 3色
            "deepSlots": item["deepSlots"],   # 深層スロット 3色
            "isForsaken": item.get("forsaken", False),
            "descriptionEn": item.get("description", ""),
        }
        seq += 1
        return rec

    # 共通器
    for item in vessels_data.get("genericChalices", []):
        out.append(vessel_record(item, None))

    # キャラ別器
    for category, items in vessels_data.items():
        if category == "genericChalices":
            continue
        char_id = CATEGORY_TO_CHAR.get(category)
        if char_id is None:
            print(f"WARN: unknown category {category}")
            continue
        for item in items:
            out.append(vessel_record(item, char_id))
    return out


def main():
    nightfarers = fetch_json(NIGHTFARERS_URL)
    vessels = fetch_json(VESSELS_URL)

    characters = build_characters(nightfarers)
    vessel_records = build_vessels(vessels)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    chars_out = OUT_DIR / "characters.json"
    vessels_out = OUT_DIR / "vessels.json"

    with chars_out.open("w", encoding="utf-8") as f:
        json.dump({"version": 1, "characters": characters}, f, ensure_ascii=False, indent=2)
    with vessels_out.open("w", encoding="utf-8") as f:
        json.dump({"version": 1, "vessels": vessel_records}, f, ensure_ascii=False, indent=2)

    print(f"characters: {len(characters)} → {chars_out}")
    print(f"vessels:    {len(vessel_records)} → {vessels_out}")


if __name__ == "__main__":
    main()
