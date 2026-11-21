// Come Home to Each Other - tells the other phone that new words are on the bridge.
// Called by the app straight after an entry is saved. Needs the pair's secret token.
// The notification never contains the words themselves.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

// New-key migration: prefer the sb_secret_ key (SUPABASE_SECRET_KEYS JSON, name "default"),
// fall back to the legacy service_role JWT so this works before and after the switch.
const SB_SECRET: string = (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default; } catch { return undefined; } })()
  ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

webpush.setVapidDetails(
  Deno.env.get("CHTE_VAPID_SUBJECT") ?? "mailto:hello@example.com",
  Deno.env.get("CHTE_VAPID_PUBLIC")!,
  Deno.env.get("CHTE_VAPID_PRIVATE")!,
);
const db = createClient(Deno.env.get("SUPABASE_URL")!, SB_SECRET);

// verify_jwt is OFF for this function (the platform check only understands legacy JWTs).
// Real auth = the pair's secret token below. This gate just keeps parity with the old
// "must carry the project's public key" behaviour. Publishable/anon keys are public by design.
function publicKeys(): string[] {
  let keys: string[] = [];
  try { keys = Object.values(JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}")) as string[]; } catch { /* not provisioned */ }
  const anon = Deno.env.get("SUPABASE_ANON_KEY"); if (anon) keys.push(anon);
  return keys.filter(Boolean);
}
function fromOurApp(req: Request): boolean {
  const k = req.headers.get("apikey") ?? (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  return !!k && publicKeys().includes(k);
}

// Notifications are only ever sent to the real browser notification services.
const PUSH_HOSTS = [
  /^fcm\.googleapis\.com$/, /^android\.googleapis\.com$/, /\.google\.com$/,
  /(^|\.)push\.services\.mozilla\.com$/, /(^|\.)notify\.windows\.com$/, /(^|\.)push\.apple\.com$/,
];
function isPushEndpoint(endpoint: unknown): boolean {
  if (typeof endpoint !== "string" || endpoint.length > 1000) return false;
  try {
    const u = new URL(endpoint);
    return u.protocol === "https:" && !u.port && !u.username && !u.password && PUSH_HOSTS.some((r) => r.test(u.hostname));
  } catch { return false; }
}
// The link a notification opens must stay inside the app: "./..." or "?..." only.
function safeUrl(v: unknown): string {
  if (typeof v !== "string" || v.length > 300) return "./";
  if (!/^(\.\/|\?)/.test(v) || v.includes("//") || v.includes("\\") || v.includes("..") || /[\u0000-\u001f]/.test(v)) return "./";
  return v;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!fromOurApp(req)) return json({ error: "unauthorised" }, 401);

  let body: { token?: string; role?: string; part?: string; url?: string };
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const { token, role, part } = body;
  if (!token || (role !== "mum" && role !== "daughter") || (part !== "morning" && part !== "evening")) {
    return json({ error: "token, role and part required" }, 400);
  }

  const { data: pair } = await db.from("chte_pairs").select("id, mum_name, daughter_name").eq("token", token).maybeSingle();
  if (!pair) return json({ error: "unknown pair" }, 404);

  const other = role === "mum" ? "daughter" : "mum";
  const fromName = role === "mum" ? pair.mum_name : pair.daughter_name;
  const { data: subs } = await db.from("chte_push_subs").select("endpoint, p256dh, auth").eq("pair_id", pair.id).eq("role", other);

  const payload = JSON.stringify({
    title: "Come Home to Each Other",
    body: `${fromName} has placed ${part === "morning" ? "this morning's" : "tonight's"} words on the bridge`,
    url: safeUrl(body.url),
  });

  let sent = 0;
  for (const s of subs ?? []) {
    if (!isPushEndpoint(s.endpoint)) continue; // never call an address that is not a notification service
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 60 * 60 * 12 });
      sent++;
    } catch (err) {
      const code = (err as { statusCode?: number }).statusCode ?? 0;
      if (code === 404 || code === 410) await db.from("chte_push_subs").delete().eq("endpoint", s.endpoint); // phone unsubscribed
    }
  }
  return json({ subscribers: subs?.length ?? 0, sent });
});
