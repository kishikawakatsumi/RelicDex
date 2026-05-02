// `/s/{key}` のレスポンスに OGP メタタグを注入する Pages Function。
//
// SNS のクローラ (X / Slack / Discord 等) は JS を実行しないので、SPA を初期表示
// しただけではプレビューに何も載らない。そこでこの関数で:
//   1. R2 から共有データ (.relicforge 圧縮 blob) を取り出して解凍・デコード
//   2. ビルド (= 最後に更新された 1 件) があれば「名前 + 集計効果」を表示
//      無ければ「ビルドを組んでみませんか?」と呼びかける文面に
//   3. SPA の static `index.html` の <head> に OGP / Twitter Card メタを挿入
//
// `next()` は `_redirects` を経由しないため `/s/*` では 404 になる。明示的に
// `/index.html` を fetch して書き換える必要がある。

interface Env {
  SHARES: R2Bucket;
}

interface ExportPayload {
  schemaVersion: number;
  exportedAt: string;
  relics: ExportRelic[];
  builds: ExportBuild[];
}
interface ExportRelic {
  id: string;
  color: string;
  slotCount: number;
  depth: string;
  uniqueId?: string;
  effects: { effectId: string; slotIndex: number; isDemerit?: boolean }[];
}
interface ExportBuild {
  id: string;
  name: string;
  characterId: string;
  vesselId?: string;
  normalSlotRelicIds: (string | null)[];
  deepSlotRelicIds: (string | null)[];
  updatedAt: string;
}

interface MasterEffect { id: string; textJa: string; textEn: string }
interface MasterVessel { id: string; baseSlots: string[]; deepSlots: string[] }

const SITE_NAME = "RelicForge";

export const onRequest: PagesFunction<Env> = async (context) => {
  const { params, env, request } = context;
  const key = String(params.key ?? "");

  const indexResp = await fetch(new URL("/index.html", request.url));
  if (!indexResp.ok) return indexResp;
  const baseHtml = await indexResp.text();

  const meta = key ? await buildOgpMeta(key, env, request).catch(() => null) : null;
  if (!meta) {
    // データが無い / 取得失敗時は素の SPA をそのまま返す (ロードに支障なし)
    return new Response(baseHtml, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "public, max-age=300",
      },
    });
  }

  const origin = new URL(request.url).origin;
  const html = baseHtml
    .replace(/<title>[\s\S]*?<\/title>/i, `<title>${escapeHtml(meta.title)}</title>`)
    .replace(/<\/head>/i, `${renderMetaBlock(meta, `${origin}/og-image.png`)}\n</head>`);

  return new Response(html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
};

interface OgpMeta { title: string; description: string }

async function buildOgpMeta(key: string, env: Env, request: Request): Promise<OgpMeta | null> {
  const obj = await env.SHARES.get(key);
  if (!obj || !obj.body) return null;

  const payload = await new Response(
    obj.body.pipeThrough(new DecompressionStream("deflate-raw")),
  ).json<ExportPayload>();

  // 言語選択の優先順位:
  //  1. アップロード時に保存した `customMetadata.lang` (= 共有作成者のロケール)
  //  2. リクエストの Accept-Language (古い共有データへのフォールバック)
  // SNS クローラは Accept-Language を送らないので 1 が無いと常に英語になる。
  const storedLang = obj.customMetadata?.lang ?? "";
  const acceptLang = request.headers.get("accept-language") ?? "";
  const isJa = (storedLang || acceptLang).toLowerCase().startsWith("ja");

  const builds = [...(payload.builds ?? [])].sort((a, b) =>
    a.updatedAt < b.updatedAt ? 1 : -1,
  );

  // ビルド未作成: SNS で見た人に「あなたが組んでみませんか?」と促す文面に
  if (builds.length === 0) {
    const count = payload.relics.length;
    return {
      title: isJa
        ? `ビルドを組んでみませんか? | ${SITE_NAME}`
        : `Want to build a loadout? | ${SITE_NAME}`,
      description: isJa
        ? `${count} 個の遺物が共有されました。あなたなら、どんなビルドを組みますか?`
        : `${count} relics shared. What loadout would you build with these?`,
    };
  }

  // ビルド有り: 最新更新の 1 件を OGP の対象とし、名前 + 集計効果を表示
  const origin = new URL(request.url).origin;
  const [effectsFile, vesselsFile] = await Promise.all([
    fetch(`${origin}/master/effects.json`).then((r) => r.json<{ effects: MasterEffect[] }>()),
    fetch(`${origin}/master/vessels.json`).then((r) => r.json<{ vessels: MasterVessel[] }>()),
  ]);
  const effectsById = new Map(effectsFile.effects.map((e) => [e.id, e] as const));
  const vesselsById = new Map(vesselsFile.vessels.map((v) => [v.id, v] as const));
  const relicsById = new Map(payload.relics.map((r) => [r.id, r] as const));

  const build = builds[0];
  const lines = aggregateEffects(build, relicsById, vesselsById, effectsById, isJa);
  const desc = lines
    .map((l) => (l.isDemerit ? `(${l.text})` : l.text))
    .join(" ・ ");
  const name = build.name?.trim() || (isJa ? "名称未設定" : "Untitled");

  return {
    title: `${name} | ${SITE_NAME}`,
    description: truncate(desc, 200),
  };
}

function aggregateEffects(
  build: ExportBuild,
  relicsById: Map<string, ExportRelic>,
  vesselsById: Map<string, MasterVessel>,
  effectsById: Map<string, MasterEffect>,
  isJa: boolean,
): { text: string; isDemerit: boolean }[] {
  const vessel = build.vesselId ? vesselsById.get(build.vesselId) : null;
  const normalColors = vessel?.baseSlots ?? ["white", "white", "white"];
  const deepColors = vessel?.deepSlots ?? ["white", "white", "white"];
  const out: { text: string; isDemerit: boolean }[] = [];

  const collect = (rid: string | null, slotColor: string, kind: "normal" | "deep") => {
    if (!rid) return;
    const relic = relicsById.get(rid);
    if (!relic) return;
    if (slotColor !== "white" && slotColor !== relic.color) return;
    if (kind === "normal" && relic.depth === "deep") return;
    if (kind === "deep" && relic.depth !== "deep") return;
    for (const e of relic.effects) {
      const eff = effectsById.get(e.effectId);
      if (!eff) continue;
      out.push({
        text: isJa ? eff.textJa : eff.textEn,
        isDemerit: !!e.isDemerit,
      });
    }
  };

  build.normalSlotRelicIds.forEach((rid, i) => collect(rid, normalColors[i] ?? "white", "normal"));
  build.deepSlotRelicIds.forEach((rid, i) => collect(rid, deepColors[i] ?? "white", "deep"));
  return out;
}

function truncate(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function renderMetaBlock(meta: OgpMeta, imageUrl: string): string {
  const t = escapeHtml(meta.title);
  const d = escapeHtml(meta.description);
  const s = escapeHtml(SITE_NAME);
  const img = escapeHtml(imageUrl);
  return [
    `<meta property="og:title" content="${t}">`,
    `<meta property="og:description" content="${d}">`,
    `<meta property="og:site_name" content="${s}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:image" content="${img}">`,
    `<meta property="og:image:width" content="1024">`,
    `<meta property="og:image:height" content="1024">`,
    `<meta property="og:image:type" content="image/png">`,
    `<meta name="twitter:card" content="summary">`,
    `<meta name="twitter:title" content="${t}">`,
    `<meta name="twitter:description" content="${d}">`,
    `<meta name="twitter:image" content="${img}">`,
    `<meta name="description" content="${d}">`,
  ].join("\n    ");
}
