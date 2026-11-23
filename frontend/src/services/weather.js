// Live weather from Open-Meteo (free, no API key, needs internet). Only used to pre-fill the weather fields.
async function getJson(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error("HTTP " + r.status);
  return r.json();
}

async function locate(name, state) {
  const d = await getJson("https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(name) + "&count=10&language=en&format=json");
  const inIndia = (d.results || []).filter((x) => x.country_code === "IN");
  return inIndia.find((x) => state && x.admin1 === state) || inIndia[0] || null;
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

// Returns { temperature, humidity, rainfall, place }. rainfall = total of the last 30 days (mm).
export async function fetchWeather(district, state) {
  let hit = null;
  if (district) hit = await locate(district, state);
  if (!hit && state) hit = await locate(state, state);
  if (!hit) throw new Error("place not found");
  const w = await getJson(
    "https://api.open-meteo.com/v1/forecast?latitude=" + hit.latitude + "&longitude=" + hit.longitude +
    "&current=temperature_2m,relative_humidity_2m&daily=precipitation_sum&past_days=30&forecast_days=1&timezone=auto");
  const past = (w.daily?.precipitation_sum || []).slice(0, 30).reduce((a, b) => a + (b || 0), 0);
  return {
    temperature: clamp(Math.round(w.current.temperature_2m * 10) / 10, 0, 55),
    humidity: clamp(Math.round(w.current.relative_humidity_2m), 0, 100),
    rainfall: clamp(Math.round(past * 10) / 10, 0, 500),
    place: hit.name + (hit.admin1 ? ", " + hit.admin1 : ""),
  };
}