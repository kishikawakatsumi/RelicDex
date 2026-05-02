// ソート用 chip + ドロップダウン (iOS SortSheet 相当)。
// クリックで開閉、行をタップすると未選択 → そのオプション active / すでに active なら昇降反転。

import { useEffect, useRef, useState } from "react";
import { useI18n } from "../lib/i18n";
import {
  defaultSortConfig,
  sortLabel,
  type RelicSortConfig,
  type RelicSortOption,
} from "../lib/sort";

interface Props {
  config: RelicSortConfig;
  onChange: (next: RelicSortConfig) => void;
}

const OPTIONS: RelicSortOption[] = ["registered", "size", "color"];

export function SortControl({ config, onChange }: Props) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDetailsElement>(null);

  // 外側クリックで閉じる
  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (!ref.current) return;
      if (!ref.current.contains(e.target as Node)) setOpen(false);
    }
    if (open) {
      document.addEventListener("click", onDocClick);
      return () => document.removeEventListener("click", onDocClick);
    }
  }, [open]);

  function selectOption(option: RelicSortOption) {
    if (config.option === option) {
      onChange({ ...config, ascending: !config.ascending });
    } else {
      onChange({ option, ascending: defaultSortConfig.ascending });
    }
  }

  const arrow = config.ascending ? "↑" : "↓";

  return (
    <details
      ref={ref}
      className="effect-filter sort-control"
      open={open}
      onToggle={(e) => setOpen((e.target as HTMLDetailsElement).open)}
    >
      <summary>
        {t("ソート")}: {t(sortLabel(config.option))} {arrow}
      </summary>
      <div className="effect-options sort-options">
        {OPTIONS.map((opt) => {
          const active = opt === config.option;
          return (
            <button
              key={opt}
              type="button"
              className={`sort-row ${active ? "active" : ""}`}
              onClick={() => selectOption(opt)}
            >
              <span>{t(sortLabel(opt))}</span>
              {active && <span className="sort-arrow">{arrow}</span>}
            </button>
          );
        })}
      </div>
    </details>
  );
}
