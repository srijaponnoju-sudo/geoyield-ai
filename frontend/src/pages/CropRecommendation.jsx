import { useCallback, useRef, useState } from "react";
import { api, cleanPayload } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Bar, Spinner, List, SpeakButton, cap } from "../components/ui.jsx";
import LocationFields from "../components/LocationFields.jsx";
import { SOIL_TYPES, SEASONS } from "../data/locations.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";
import { fetchWeather } from "../services/weather.js";

const FEAT_KEY = { N: "crop.N", P: "crop.P", K: "crop.K", ph: "crop.ph", temperature: "crop.temp", humidity: "crop.hum", rainfall: "crop.rain" };

const NUM = ["N", "P", "K", "ph", "temperature", "humidity", "rainfall"];
const INIT = { state: "", district: "", village: "", soil_type: "", season: "", N: "", P: "", K: "", ph: "", temperature: "", humidity: "", rainfall: "", n_level: "", p_level: "", k_level: "", water: "" };
const EXAMPLE = { N: "90", P: "42", K: "43", ph: "6.5", temperature: "21", humidity: "82", rainfall: "203" };

export default function CropRecommendation() {
  const { t } = useLang();
  const [v, setV] = useState(INIT);
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  const [wxBusy, setWxBusy] = useState(false);
  const [wxMsg, setWxMsg] = useState("");
  async function liveWeather() {
    setWxBusy(true); setWxMsg("");
    try {
      const w = await fetchWeather(v.district, v.state);
      setV((p) => ({ ...p, temperature: String(w.temperature), humidity: String(w.humidity), rainfall: String(w.rainfall) }));
      setWxMsg(t("crop.wxOk", { place: w.place }));
    } catch (err) { setWxMsg(t("crop.wxFail")); }
    finally { setWxBusy(false); }
  }
  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const [mode, setMode] = useState("dont");
  const [area, setArea] = useState(null);
  const [areaBusy, setAreaBusy] = useState(false);
  async function loadArea() {
    if (!v.state) { setArea({ error: t("crop.areaFail") }); return; }
    setAreaBusy(true);
    try { const r = await api.areaCrops(v.state, v.district, v.season); setArea(r.crops.length ? { crops: r.crops } : { error: t("crop.areaFail") }); }
    catch (err) { setArea({ error: err.message }); }
    finally { setAreaBusy(false); }
  }
  const sel = (k) => ({ value: v[k], onChange: (e) => set(k)(e.target.value) });

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); lastRun.current = null; }, []);
  useRelang(lastRun, setRes);
  const onFill = useCallback((f) => {
    const keys = Object.keys(f).filter((k) => NUM.includes(k));
    setV((p) => { const n = { ...p }; keys.forEach((k) => { n[k] = String(f[k]); }); return n; });
    return keys;
  }, []);
  useVoiceEvents({ onFill, onReset: reset });

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(""); setRes(null);
    const payload = { ...cleanPayload(v, NUM), top_k: 3 };
    if (mode === "dont") { delete payload.N; delete payload.P; delete payload.K; } else { delete payload.n_level; delete payload.p_level; delete payload.k_level; }
    if (mode === "dont" && !payload.soil_type && !payload.n_level && !payload.p_level && !payload.k_level) { setError(t("crop.needSoil")); setBusy(false); return; }
    lastRun.current = (re) => api.recommendCrop({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res ? t("crop.speak", {
    crop: res.recommendations[0].crop_label, p: Math.round(res.recommendations[0].model_probability * 100),
    others: res.recommendations.length > 1 ? t("crop.speakOthers", { list: res.recommendations.slice(1).map((r) => r.crop_label).join(", ") }) : "",
  }) + " " + res.notes[res.notes.length - 1] : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon="🌾" title={t("crop.title")} subtitle={t("crop.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("crop.farm")}</h3>
          <div className="form-grid">
            <LocationFields value={v} onChange={(loc) => setV((p) => ({ ...p, ...loc }))} />
            <Field label={t("common.soilType")} hint={t("crop.soilHint")}>
              <select {...sel("soil_type")}><option value="">{t("common.select")}</option>{SOIL_TYPES.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
            <Field label={t("common.season")} hint={t("crop.seasonHint")}>
              <select {...sel("season")}><option value="">{t("common.select")}</option>{SEASONS.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
          </div>
          <h3>{t("crop.soilTitle")}</h3>
          <div className="btn-row">
            <button type="button" className={"btn " + (mode === "dont" ? "primary" : "outline")} onClick={() => setMode("dont")}>{t("crop.modeDont")}</button>
            <button type="button" className={"btn " + (mode === "know" ? "primary" : "outline")} onClick={() => setMode("know")}>{t("crop.modeKnow")}</button>
          </div>
          {mode === "dont" && (
            <>
              <p className="muted small">{t("crop.dontHelp")}</p>
              <div className="form-grid">
                {[["n_level", "crop.N"], ["p_level", "crop.P"], ["k_level", "crop.K"]].map(([k, lab]) => (
                  <Field key={k} label={t(lab)}><select {...sel(k)}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
                ))}
              </div>
            </>
          )}
          <div className="btn-row">
            <button type="button" className="btn outline" disabled={areaBusy} onClick={loadArea}>{t("crop.areaBtn")}</button>
          </div>
          {area && <><p className="muted small">{area.error || t("crop.areaNote")}</p>{area.crops && <List items={area.crops} tone="ok" />}</>}
          <p className="muted small">{t("soil.tip")}</p>
          <h3>{t("crop.values")}</h3>
          <div className="btn-row">
            <button type="button" className="btn outline" disabled={wxBusy || !v.state} onClick={liveWeather}>{wxBusy ? t("common.analysing") : t("crop.wxBtn")}</button>
            {wxMsg && <span className="muted small">{wxMsg}</span>}
          </div>
          <div className="form-grid">
            {mode === "know" && <Field label={t("crop.N")}><NumberInput min={0} max={300} value={v.N} onChange={set("N")} /></Field>}
            {mode === "know" && <Field label={t("crop.P")}><NumberInput min={0} max={300} value={v.P} onChange={set("P")} /></Field>}
            {mode === "know" && <Field label={t("crop.K")}><NumberInput min={0} max={400} value={v.K} onChange={set("K")} /></Field>}
            <Field label={t("crop.ph")} hint={t("crop.phHint")}><NumberInput min={3} max={10} value={v.ph} onChange={set("ph")} /></Field>
            <Field label={t("crop.temp")}><NumberInput required min={0} max={55} value={v.temperature} onChange={set("temperature")} /></Field>
            <Field label={t("crop.hum")}><NumberInput required min={0} max={100} value={v.humidity} onChange={set("humidity")} /></Field>
            <Field label={t("crop.rain")}><NumberInput min={0} max={500} value={v.rainfall} onChange={set("rainfall")} /></Field>
            <Field label={t("crop.water")} hint={t("crop.waterHint")}><select {...sel("water")}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
          </div>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy}>{busy ? t("common.analysing") : t("crop.btn")}</button>
            <button type="button" className="btn outline" onClick={() => { setMode("know"); setV((p) => ({ ...p, ...EXAMPLE })); }}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner />}
          <Alert title={t("crop.couldNot")}>{error}</Alert>
          {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              {res.estimated && res.estimated.length > 0 && <Alert kind="warn">{t("crop.estNote")}</Alert>}
              {res.low_confidence && <Alert kind="warn" title={t("crop.warnTitle")}>{res.notes.slice(0, 2).filter((n) => n).join(" ")}</Alert>}
              <SpeakButton text={speech} />
              {res.recommendations.map((r, i) => (
                <div className="card result" key={r.crop}>
                  <div className="result-head">
                    <h3>{i + 1}. {cap(r.crop_label)}</h3>
                    {i === 0 && <span className="badge green">{t("crop.best")}</span>}
                  </div>
                  <Bar label={t("crop.prob")} value={r.model_probability} />
                  {r.regional && <List items={[r.regional.text]} tone={r.regional.ok ? "ok" : "warn"} />}
                  <h4>{t("crop.why")}</h4><List items={r.reasons} tone="ok" />
                  {r.warnings.length > 0 && <><h4>{t("crop.check")}</h4><List items={r.warnings} tone="warn" /></>}
                </div>
              ))}
              <div className="card">
                <h4>{t("crop.perf")}</h4>
                <Bar label={t("crop.acc")} value={res.model_metrics.test_accuracy} />
                <Bar label={t("crop.f1")} value={res.model_metrics.test_macro_f1} />
                <p className="muted small">{t("crop.metricsNote")}</p>
                <h4>{t("crop.importance")}</h4>
                {Object.entries(res.model_metrics.feature_importance).sort((a, b) => b[1] - a[1]).map(([k, val]) => (
                  <Bar key={k} label={t(FEAT_KEY[k])} value={val} max={0.25} text={val.toFixed(3)} tone="navy" />
                ))}
                <h4>{t("crop.notes")}</h4><List items={res.notes} />
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
