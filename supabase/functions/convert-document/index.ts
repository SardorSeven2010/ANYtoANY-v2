// =====================================================================
// ANYtoANY: PDF -> Word / PowerPoint / Excel (Adobe PDF Services orqali)
//
// Bu Supabase Edge Function. Adobe kaliti ilovada emas, shu yerda (serverda)
// saqlanadi. Ilova bu funksiyani uch bosqichda chaqiradi:
//   1) action "start"   -> PDF yuklash uchun manzil qaytaradi
//   2) action "convert" -> konvertatsiyani boshlaydi
//   3) action "status"  -> tayyor bo'lsa, yuklab olish manzilini qaytaradi
//
// Kerakli sirlar (Supabase -> Edge Functions -> Secrets):
//   ADOBE_CLIENT_ID, ADOBE_CLIENT_SECRET
// Ixtiyoriy:
//   DAILY_LIMIT  - bir foydalanuvchiga kuniga nechta konvertatsiya (standart 15)
//   PRO_ONLY     - "false" qilsangiz, bepul foydalanuvchilar ham ishlata oladi
//   ADOBE_API_BASE - Yevropa uchun https://pdf-services-ew1.adobe.io
// =====================================================================

const ADOBE_BASE = (Deno.env.get("ADOBE_API_BASE") ?? "https://pdf-services.adobe.io").replace(/\/+$/, "");
const ADOBE_CLIENT_ID = Deno.env.get("ADOBE_CLIENT_ID") ?? "";
const ADOBE_CLIENT_SECRET = Deno.env.get("ADOBE_CLIENT_SECRET") ?? "";
const SUPABASE_URL = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const DAILY_LIMIT = Number(Deno.env.get("DAILY_LIMIT") ?? "15");
const PRO_ONLY = (Deno.env.get("PRO_ONLY") ?? "true").toLowerCase() !== "false";

const TARGETS = new Set(["docx", "pptx", "xlsx"]);
const BASE_URL = new URL(ADOBE_BASE);
const ADOBE_HOST = /^pdf-services(-[a-z0-9]+)?\.adobe\.io$/;
const JOB_ID = /^[A-Za-z0-9_-]{6,128}$/;
const ASSET_ID = /^[A-Za-z0-9:_.-]{6,256}$/;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

class HttpError extends Error {
  constructor(public status: number, public code: string, message = "") {
    super(message);
  }
}

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

// ---------------------------------------------------------------- Supabase
type Caller = { id: string; jwt: string; apiKey: string };

/** So'rov yuborgan foydalanuvchini uning kirish tokeni orqali aniqlaydi. */
async function authenticate(req: Request): Promise<Caller> {
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const apiKey = req.headers.get("apikey") || SUPABASE_ANON_KEY;
  if (!jwt || !SUPABASE_URL) throw new HttpError(401, "unauthorized");
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${jwt}`, apikey: apiKey },
  });
  if (!res.ok) throw new HttpError(401, "unauthorized");
  const user = await res.json();
  if (typeof user?.id !== "string" || !user.id) throw new HttpError(401, "unauthorized");
  return { id: user.id, jwt, apiKey };
}

/** Bazaga foydalanuvchining o'z nomidan murojaat qiladi (RLS qoidalari amal qiladi). */
function db(caller: Caller, path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${caller.jwt}`,
      apikey: caller.apiKey,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

async function requirePro(caller: Caller): Promise<void> {
  if (!PRO_ONLY) return;
  const res = await db(caller, `user_profiles?select=is_pro,pro_until&id=eq.${caller.id}`);
  if (!res.ok) throw new HttpError(503, "not_configured", "user_profiles jadvali topilmadi");
  const row = (await res.json())[0];
  const active = row?.is_pro === true &&
    (!row.pro_until || new Date(row.pro_until).getTime() > Date.now());
  if (!active) throw new HttpError(403, "pro_required");
}

async function requireQuota(caller: Caller): Promise<void> {
  if (!(DAILY_LIMIT > 0)) return;
  const since = new Date();
  since.setUTCHours(0, 0, 0, 0);
  const query = `select=id&user_id=eq.${caller.id}` +
    `&created_at=gte.${encodeURIComponent(since.toISOString())}&limit=${DAILY_LIMIT + 1}`;
  const res = await db(caller, `conversion_log?${query}`);
  if (!res.ok) throw new HttpError(503, "not_configured", "conversion_log jadvali topilmadi");
  if ((await res.json()).length >= DAILY_LIMIT) throw new HttpError(429, "daily_limit");
}

// ------------------------------------------------------------------- Adobe
let cachedToken: { value: string; expires: number } | null = null;

async function adobeError(res: Response): Promise<HttpError> {
  let code = "";
  let message = `Adobe: HTTP ${res.status}`;
  try {
    const body = await res.json();
    const err = body?.error ?? body;
    code = String(err?.code ?? "");
    if (err?.message) message = String(err.message);
  } catch (_) {
    // javob JSON emas
  }
  if (res.status === 429 || /quota/i.test(code) || /quota/i.test(message)) {
    return new HttpError(429, "provider_quota", message);
  }
  if (res.status === 401 || res.status === 403) {
    return new HttpError(503, "not_configured", "Adobe kalitlari noto'g'ri yoki muddati o'tgan");
  }
  return new HttpError(502, "provider_error", message);
}

async function adobeToken(): Promise<string> {
  if (cachedToken && cachedToken.expires > Date.now()) return cachedToken.value;
  const res = await fetch(`${ADOBE_BASE}/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: ADOBE_CLIENT_ID, client_secret: ADOBE_CLIENT_SECRET }),
  });
  if (!res.ok) throw await adobeError(res);
  const data = await res.json();
  if (!data?.access_token) throw new HttpError(502, "provider_error", "Adobe token bermadi");
  const lifetime = Math.max(60, Number(data.expires_in ?? 3600) - 120);
  cachedToken = { value: String(data.access_token), expires: Date.now() + lifetime * 1000 };
  return cachedToken.value;
}

async function adobe(url: string, init: RequestInit = {}): Promise<Response> {
  return fetch(url, {
    ...init,
    headers: {
      "X-API-Key": ADOBE_CLIENT_ID,
      Authorization: `Bearer ${await adobeToken()}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

function allowedHost(host: string): boolean {
  return host === BASE_URL.host || ADOBE_HOST.test(host);
}

// --------------------------------------------------------------- Amallar
type Body = Record<string, unknown>;

function targetOf(body: Body): string {
  const target = String(body.targetFormat ?? "");
  if (!TARGETS.has(target)) throw new HttpError(400, "bad_request", "targetFormat noto'g'ri");
  return target;
}

/** 1-bosqich: PDF yuklanadigan vaqtinchalik manzilni ochadi. */
async function start(caller: Caller, body: Body) {
  targetOf(body);
  await requirePro(caller);
  await requireQuota(caller);
  const res = await adobe(`${ADOBE_BASE}/assets`, {
    method: "POST",
    body: JSON.stringify({ mediaType: "application/pdf" }),
  });
  if (!res.ok) throw await adobeError(res);
  const data = await res.json();
  if (!data?.uploadUri || !data?.assetID) {
    throw new HttpError(502, "provider_error", "Adobe javobi kutilmagan ko'rinishda");
  }
  return { uploadUri: data.uploadUri, assetID: data.assetID, mediaType: "application/pdf" };
}

/** 2-bosqich: yuklangan PDF ni tanlangan formatga aylantirishni boshlaydi. */
async function convert(caller: Caller, body: Body) {
  const target = targetOf(body);
  const assetID = String(body.assetID ?? "");
  if (!ASSET_ID.test(assetID)) throw new HttpError(400, "bad_request", "assetID noto'g'ri");
  await requirePro(caller);
  await requireQuota(caller);

  const res = await adobe(`${ADOBE_BASE}/operation/exportpdf`, {
    method: "POST",
    body: JSON.stringify({ assetID, targetFormat: target }),
  });
  if (!res.ok) throw await adobeError(res);
  await res.body?.cancel();

  // Javob sarlavhasidagi manzil: https://<host>/operation/exportpdf/<jobId>/status
  const location = res.headers.get("location") ?? "";
  const match = location.match(/^https?:\/\/([^/]+)\/operation\/exportpdf\/([^/]+)\/status/);
  if (!match || !allowedHost(match[1]) || !JOB_ID.test(match[2])) {
    throw new HttpError(502, "provider_error", "Adobe javobi kutilmagan ko'rinishda");
  }

  // Kunlik limit hisobi uchun yozib qo'yiladi
  const logged = await db(caller, "conversion_log", {
    method: "POST",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ user_id: caller.id, target_format: target }),
  });
  await logged.body?.cancel();

  return { jobId: match[2], host: match[1] };
}

/** 3-bosqich: konvertatsiya holatini tekshiradi. */
async function status(body: Body) {
  const jobId = String(body.jobId ?? "");
  const host = String(body.host ?? BASE_URL.host);
  if (!JOB_ID.test(jobId) || !allowedHost(host)) {
    throw new HttpError(400, "bad_request", "jobId noto'g'ri");
  }
  const protocol = host === BASE_URL.host ? BASE_URL.protocol : "https:";
  const res = await adobe(`${protocol}//${host}/operation/exportpdf/${jobId}/status`);
  if (!res.ok) throw await adobeError(res);
  const data = await res.json();
  const state = String(data?.status ?? "").toLowerCase();
  if (state === "done") {
    const downloadUri = data?.asset?.downloadUri ?? data?.downloadUri;
    if (!downloadUri) throw new HttpError(502, "provider_error", "Tayyor fayl manzili kelmadi");
    return { status: "done", downloadUri };
  }
  if (state === "failed") {
    return {
      status: "failed",
      message: String(data?.error?.message ?? "Bu PDF ni aylantirib bo'lmadi"),
    };
  }
  return { status: "in progress" };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    if (req.method !== "POST") throw new HttpError(405, "bad_request", "Faqat POST");
    const caller = await authenticate(req);
    if (!ADOBE_CLIENT_ID || !ADOBE_CLIENT_SECRET) {
      throw new HttpError(503, "not_configured", "ADOBE_CLIENT_ID va ADOBE_CLIENT_SECRET kiritilmagan");
    }
    const body: Body = await req.json().catch(() => ({}));
    switch (body.action) {
      case "start":
        return reply(200, await start(caller, body));
      case "convert":
        return reply(200, await convert(caller, body));
      case "status":
        return reply(200, await status(body));
      default:
        throw new HttpError(400, "bad_request", "action noto'g'ri");
    }
  } catch (e) {
    if (e instanceof HttpError) return reply(e.status, { error: e.code, message: e.message });
    console.error(e);
    return reply(500, { error: "provider_error", message: "Serverda ichki xatolik" });
  }
});
