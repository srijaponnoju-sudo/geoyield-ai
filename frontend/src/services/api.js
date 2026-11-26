export const BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";
let LANG = "en";
const NO_BACKEND = {
  en: "Cannot reach the GeoYield backend. Start it with .\\run-backend.ps1 and check it is running at ",
  hi: "GeoYield \u092C\u0948\u0915\u090F\u0902\u0921 \u0938\u0947 \u0938\u0902\u092A\u0930\u094D\u0915 \u0928\u0939\u0940\u0902 \u0939\u094B \u092A\u093E \u0930\u0939\u093E\u0964 \u0907\u0938\u0947 .\\run-backend.ps1 \u0938\u0947 \u0936\u0941\u0930\u0942 \u0915\u0930\u0947\u0902 \u0914\u0930 \u091C\u093E\u0901\u091A\u0947\u0902 \u0915\u093F \u092F\u0939 \u092F\u0939\u093E\u0901 \u091A\u0932 \u0930\u0939\u093E \u0939\u0948: ",
  te: "GeoYield \u0C2C\u0C4D\u0C2F\u0C3E\u0C15\u0C46\u0C02\u0C21\u0C4D\u200C\u0C28\u0C41 \u0C1A\u0C47\u0C30\u0C41\u0C15\u0C4B\u0C32\u0C47\u0C15\u0C2A\u0C4B\u0C24\u0C41\u0C28\u0C4D\u0C28\u0C3E\u0C02. \u0C26\u0C40\u0C28\u0C4D\u0C28\u0C3F .\\run-backend.ps1 \u0C24\u0C4B \u0C2A\u0C4D\u0C30\u0C3E\u0C30\u0C02\u0C2D\u0C3F\u0C02\u0C1A\u0C3F \u0C07\u0C15\u0C4D\u0C15\u0C21 \u0C28\u0C21\u0C41\u0C38\u0C4D\u0C24\u0C4B\u0C02\u0C26\u0C4B \u0C1A\u0C42\u0C21\u0C02\u0C21\u0C3F: ",
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
  problems: () => request(`/api/problems?lang=${LANG}`),
  areaCrops: (state, district, season) => request(`/api/area/crops?state=${encodeURIComponent(state)}`
    + (district ? `&district=${encodeURIComponent(district)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  evaluateFertilizer: (b) => request("/api/fertilizer/evaluate", json(b)),
  profitOptions: (state, district, season) => request(`/api/profit/options?state=${encodeURIComponent(state)}`
    + (district ? `&district=${encodeURIComponent(district)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  profitCompare: (b) => request("/api/profit/compare", json(b)),
  schemes: (state, crop, season) => request(`/api/schemes?lang=${LANG}` + (state ? `&state=${encodeURIComponent(state)}` : "")
    + (crop ? `&crop=${encodeURIComponent(crop)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  sendFeedback: (b) => request("/api/feedback", json(b)),
  feedbackSummary: () => request("/api/feedback/summary"),
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
