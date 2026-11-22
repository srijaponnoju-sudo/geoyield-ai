// Turns a spoken sentence (English / Hindi / Telugu) into an intent. No AI guessing: only known keywords and numbers.
const DIGITS = { "०": "0", "१": "1", "२": "2", "३": "3", "४": "4", "५": "5", "६": "6", "७": "7", "८": "8", "९": "9",
  "౦": "0", "౧": "1", "౨": "2", "౩": "3", "౪": "4", "౫": "5", "౬": "6", "౭": "7", "౮": "8", "౯": "9" };

export function normalise(text) {
  let s = text.toLowerCase().replace(/[०-९౦-౯]/g, (d) => DIGITS[d]);
  s = s.replace(/\s*(point|दशमलव|पॉइंट|పాయింట్)\s*/g, ".").replace(/(\d)\s*[.,]\s*(\d)/g, "$1.$2");
  return s;
}

// field -> spoken names (Latin names need word boundaries, so "ph" is not found inside "phosphorus")
const FIELDS = {
  N: ["nitrogen", "नाइट्रोजन", "नत्रजन", "నత్రజని", "నైట్రోజన్"],
  P: ["phosphorus", "phosphorous", "फास्फोरस", "फॉस्फोरस", "भास्वरम", "భాస్వరం", "ఫాస్ఫరస్"],
  K: ["potassium", "potash", "पोटैशियम", "पोटाश", "పొటాషియం"],
  ph: ["ph", "p h", "पीएच", "पी एच", "పిహెచ్", "పీహెచ్", "పి హెచ్"],
  temperature: ["temperature", "temp", "तापमान", "ఉష్ణోగ్రత"],
  humidity: ["humidity", "नमी", "आर्द्रता", "తేమ"],
  rainfall: ["rainfall", "rain", "बारिश", "वर्षा", "వర్షపాతం", "వర్షం"],
  area_hectares: ["hectares", "hectare", "area", "हेक्टेयर", "क्षेत्रफल", "హెక్టార్", "విస్తీర్ణం"],
};
const FIELD_LABEL = { N: "N", P: "P", K: "K", ph: "pH", temperature: "temperature", humidity: "humidity", rainfall: "rainfall", area_hectares: "area" };

const esc = (a) => a.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const isLatin = (a) => /^[a-z ]+$/.test(a);

export function extractFields(text) {
  const s = normalise(text);
  const out = {};
  for (const [field, aliases] of Object.entries(FIELDS)) {
    for (const a of aliases) {
      const pre = isLatin(a) ? "\\b" : "";
      const re = new RegExp(pre + esc(a) + "(?![a-z])\\D{0,14}?(\\d+(?:\\.\\d+)?)");
      const m = s.match(re);
      if (m) { out[field] = Number(m[1]); break; }
    }
  }
  return out;
}

const NAV = [
  ["/fertilizer", ["fertilizer", "fertiliser", "उर्वरक", "खाद", "ఎరువు"]],
  ["/yield-prediction", ["yield", "उपज", "దిగుబడి"]],
  ["/crop-health", ["health", "disease", "symptom", "स्वास्थ्य", "रोग", "लक्षण", "ఆరోగ్యం", "వ్యాధి", "లక్షణ"]],
  ["/history", ["history", "इतिहास", "చరిత్ర"]],
  ["/about", ["about", "बारे", "परिचय", "గురించి"]],
  ["/dashboard", ["dashboard", "home", "डैशबोर्ड", "होम", "డాష్‌బోర్డ్", "డాష్ బోర్డ్", "హోమ్"]],
  ["/crop-recommendation", ["crop", "recommend", "फसल", "सुझाव", "పంట", "సిఫార్సు"]],
];
const NAV_KEY = { "/fertilizer": "nav.fertilizer", "/yield-prediction": "nav.yield", "/crop-health": "nav.health", "/history": "nav.history",
  "/about": "nav.about", "/dashboard": "nav.dashboard", "/crop-recommendation": "nav.crop" };
export { NAV_KEY, FIELD_LABEL };

const has = (s, words) => words.some((w) => s.includes(w));
const LANG_WORDS = [["hi", ["hindi", "हिंदी", "हिन्दी", "హిందీ"]], ["te", ["telugu", "तेलुगु", "तेलुगू", "తెలుగు"]], ["en", ["english", "अंग्रेज", "इंग्लिश", "ఇంగ్లీష్", "ఆంగ్ల"]]];

export function parseCommand(text) {
  const s = normalise(text);
  if (has(s, ["switch", "change", "बदल", "మార్చు", "మార్చండి", "language", "भाषा", "భాష"])) {
    for (const [l, w] of LANG_WORDS) if (has(s, w)) return { intent: "lang", lang: l };
  }
  if (has(s, ["read", "listen", "speak", "पढ़", "पढ", "सुना", "చదువు", "వినిపించు"])) return { intent: "read" };
  if (has(s, ["reset", "clear", "रीसेट", "साफ", "రీసెట్", "క్లియర్"])) return { intent: "reset" };
  if (has(s, ["submit", "analyse", "analyze", "evaluate", "सबमिट", "जमा", "सब्मिट", "సబ్మిట్", "సమర్పించు", "విశ్లేషించు"])) return { intent: "submit" };
  const fields = extractFields(text);
  if (Object.keys(fields).length) return { intent: "fill", fields };
  for (const [path, words] of NAV) if (has(s, words)) return { intent: "navigate", path };
  return { intent: "unknown" };
}
