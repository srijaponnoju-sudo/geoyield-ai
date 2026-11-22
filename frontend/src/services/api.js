export const BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";
let LANG = "en";
const NO_BACKEND = {
  en: "Cannot reach the GeoYield backend. Start it with .\\run-backend.ps1 and check it is running at ",
  hi: "GeoYield बैकएंड से संपर्क नहीं हो पा रहा। इसे .\\run-backend.ps1 से शुरू करें और जाँचें कि यह यहाँ चल रहा है: ",
  te: "GeoYield బ్యాకెండ్‌ను చేరుకోలేకపోతున్నాం. దీన్ని .\\run-backend.ps1 తో ప్రారంభించి ఇక్కడ నడుస్తోందో చూడండి: ",
};
export const setApiLang = (l) => { LANG = l; };

async function request(path, options = {}) {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, options);
  } catch {
    throw new Error((NO_BACKEND[LANG] || NO_BACKEND.en) + BASE);
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* empty body */
  }
  if (!res.ok) {
    const d = data?.detail;
    let msg = "Request failed (" + res.status + ")";
    if (typeof d === "string") msg = d;
    else if (Array.isArray(d))
      msg = d.map((e) => `${(e.loc || []).slice(1).join(".")}: ${e.msg}`).join("; ");
    const err = new Error(msg);
    err.status = res.status;
    throw err;
  }
  return data;
}

const json = (body) => ({
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ ...body, lang: LANG }),
});

export const api = {
  status: () => request("/api/status"),
  recommendCrop: (b) => request("/api/crop/recommend", json(b)),
  yieldOptions: () => request("/api/yield/options"),
  predictYield: (b) => request("/api/yield/predict", json(b)),
  healthSymptoms: (b) => request("/api/health/symptoms", json(b)),
  healthImage: (file, crop, relocalize = false) => {
    const fd = new FormData();
    fd.append("file", file);
    const q = `?lang=${LANG}` + (crop ? `&crop=${encodeURIComponent(crop)}` : "") + (relocalize ? "&relocalize=true" : "");
    return request(`/api/health/image${q}`, { method: "POST", body: fd });
  },
  fertilizers: () => request(`/api/fertilizers?lang=${LANG}`),
  evaluateFertilizer: (b) => request("/api/fertilizer/evaluate", json(b)),
  history: (module, limit = 50) =>
    request(`/api/history?limit=${limit}${module ? `&module=${module}` : ""}`),
};

/** Convert form strings into a clean payload: numbers parsed, empty values dropped. */
export function cleanPayload(values, numericKeys) {
  const out = {};
  for (const [k, v] of Object.entries(values)) {
    if (v === "" || v === null || v === undefined) continue;
    out[k] = numericKeys.includes(k) ? Number(v) : typeof v === "string" ? v.trim() : v;
  }
  return out;
}

/** Fallback voice from the backend (gTTS). Returns an audio Blob. */
export async function ttsBlob(text, lang) {
  let res;
  try {
    res = await fetch(`${BASE}/api/tts`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text, lang }) });
  } catch {
    throw new Error(NO_BACKEND[LANG] || NO_BACKEND.en);
  }
  if (!res.ok) { let d = ""; try { d = (await res.json()).detail; } catch { /* ignore */ } throw new Error(d || "TTS failed"); }
  return res.blob();
}
