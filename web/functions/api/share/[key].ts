// GET /api/share/{key} — R2 から `.relicforge` バイト列を取り出して返す。

interface Env {
  SHARES: R2Bucket;
}

export const onRequestGet: PagesFunction<Env> = async ({ params, env }) => {
  const key = String(params.key ?? "");
  if (!key || !/^[A-Za-z0-9_-]{1,64}$/.test(key)) {
    return new Response("invalid key", { status: 400 });
  }

  const obj = await env.SHARES.get(key);
  if (!obj) return new Response("not found", { status: 404 });

  return new Response(obj.body, {
    headers: {
      "Content-Type": "application/octet-stream",
      // 共有データは滅多に変わらない (再アップロード時は新 key になる) ので強めにキャッシュ
      "Cache-Control": "public, max-age=300",
    },
  });
};
