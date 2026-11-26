import { useCallback, useEffect, useRef, useState } from "react";
import { api, cleanPayload } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Spinner, List, SpeakButton } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";
import { SOIL_TYPES } from "../data/locations.js";
import FeedbackBox from "../components/FeedbackBox.jsx";

const SEASON_KEY = { Kharif: "season.kharif", Rabi: "season.rabi", Summer: "season.summer", "Whole Year": "season.whole", Autumn: "season.autumn", Winter: "season.winter" };
const INPUT_KEY = { state: "common.state", district: "common.district", crop: "common.crop", season: "common.season", area_hectares: "yield.area" };

const INIT = { state: "", district: "", crop: "", season: "", area_hectares: "1", soil_type: "", n_level: "", p_level: "", k_level: "" };
const pretty = (s) => s.charAt(0) + s.slice(1).toLowerCase();

export default function YieldPrediction() {
  const { t } = useLang();
  const [v, setV] = useState(INIT);
  const [opts, setOpts] = useState({ crops: [], seasons: [], states: [], districts: {} });
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [unavailable, setUnavailable] = useState("");
  const [busy, setBusy] = useState(false);

  const lastRun = useRef(null);
  const hid = useRef(null);
  if (res?.history_id) hid.current = res.history_id;
  useEffect(() => { api.yieldOptions().then(setOpts).catch((e) => setError(e.message)); }, []);
  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const sel = (k) => ({ value: v[k], onChange: (e) => set(k)(e.target.value) });
  const districts = opts.districts[v.state] || [];

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); setUnavailable(""); lastRun.current = null; hid.current = null; }, []);
  useRelang(lastRun, setRes);
  const onFill = useCallback((f) => {
    if (f.area_hectares === undefined) return [];
    setV((p) => ({ ...p, area_hectares: String(f.area_hectares) }));
    return ["area_hectares"];
  }, []);
  useVoiceEvents({ onFill, onReset: reset });

  function example() {
    const state = opts.states.includes("Telangana") ? "Telangana" : opts.states[0] || "";
    setV({ ...INIT, state, district: (opts.districts[state] || [])[0] || "", crop: opts.crops.includes("Rice") ? "Rice" : opts.crops[0] || "", season: "Kharif", area_hectares: "1" });
  }

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(""); setRes(null); setUnavailable(""); hid.current = null;
    const payload = cleanPayload(v, ["area_hectares"]);
    lastRun.current = (re) => api.predictYield({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { err.status === 503 ? setUnavailable(err.message) : setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res ? t("yield.speak", { crop: v.crop, y: res.predicted_yield, area: v.area_hectares, tot: res.expected_total_production }) : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon={"\u{1F4C8}"} title={t("yield.title")} subtitle={t("yield.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("yield.select")}</h3>
          <div className="form-grid">
            <Field label={t("common.state")}>
              <select required value={v.state} onChange={(e) => setV((p) => ({ ...p, state: e.target.value, district: "" }))}>
                <option value="">{t("common.selectState")}</option>{opts.states.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.district")}>
              <select required {...sel("district")} disabled={!v.state}>
                <option value="">{v.state ? t("common.selectDistrict") : t("common.selectStateFirst")}</option>
                {districts.map((d) => <option key={d} value={d}>{pretty(d)}</option>)}
              </select>
            </Field>
            <Field label={t("common.crop")}>
              <select required {...sel("crop")}><option value="">{t("common.select")}</option>{opts.crops.map((c) => <option key={c}>{c}</option>)}</select>
            </Field>
            <Field label={t("common.season")}>
              <select required {...sel("season")}><option value="">{t("common.select")}</option>{opts.seasons.map((s) => <option key={s} value={s}>{SEASON_KEY[s] ? t(SEASON_KEY[s]) : s}</option>)}</select>
            </Field>
            <Field label={t("yield.area")} hint={t("yield.areaHint")}>
              <NumberInput required min={0.01} value={v.area_hectares} onChange={set("area_hectares")} />
            </Field>
          </div>
          <h3>{t("yield.soilSection")}</h3>
          <div className="form-grid">
            <Field label={t("common.soilType")}>
              <select {...sel("soil_type")}><option value="">{t("common.select")}</option>{SOIL_TYPES.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
            {[["n_level", "crop.N"], ["p_level", "crop.P"], ["k_level", "crop.K"]].map(([k, lab]) => (
              <Field key={k} label={t(lab)}><select {...sel(k)}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
            ))}
          </div>
          <p className="muted small">{t("yield.soilNote")}</p>
          <p className="muted small">{t("yield.note")}</p>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy}>{busy ? t("yield.predicting") : t("yield.btn")}</button>
            <button type="button" className="btn outline" onClick={example}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner text={t("yield.predicting")} />}
          <Alert title={t("yield.couldNot")}>{error}</Alert>
          {unavailable && <Alert kind="warn" title={t("yield.notTrained")}>{unavailable}</Alert>}
          {!res && !busy && !error && !unavailable && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              <div className="card result big">
                <div className="muted">{t("yield.predicted")}</div>
                <div className="big-number">{res.predicted_yield} <small>{t("yield.unit")}</small></div>
                <p>{t("yield.total", { area: v.area_hectares })} <b>{res.expected_total_production} {t("yield.tonnes")}</b></p>
                <List items={res.warnings} tone="warn" />
                <SpeakButton text={speech} />
              </div>
              <div className="card">
                <h4>{t("yield.inputs")}</h4>
                {Object.entries(res.inputs_used).map(([k, val]) => (
                  <div className="hist-row" key={k}><span>{t(INPUT_KEY[k] || k)}</span><b>{k === "season" && SEASON_KEY[val] ? t(SEASON_KEY[val]) : k === "district" ? pretty(String(val)) : String(val)}</b></div>
                ))}
                {res.metrics && (
                  <>
                    <h4>{t("yield.acc")}</h4>
                    <div className="metric-grid">
                      <div><span>MAE</span><b>{res.metrics.MAE}</b></div><div><span>RMSE</span><b>{res.metrics.RMSE}</b></div><div><span>R{"\u00B2"}</span><b>{res.metrics.R2}</b></div>
                    </div>
                    <p className="muted small">{t("yield.base", { r2: res.metrics.baseline_crop_average_R2 })} {t("yield.testNote")}</p>
                  </>
                )}
                {res.soil_suitability && (
                  <>
                    <h4>{t("yield.soilTitle")}</h4>
                    {res.soil_suitability.available ? <List items={res.soil_suitability.lines} tone={res.soil_suitability.ok ? "ok" : "warn"} /> : <p className="muted small">{t("yield.soilNA")}</p>}
                    {res.soil_suitability.estimated && <p className="muted small">{t("crop.estNote")}</p>}
                  </>
                )}
                <Alert kind="warn">{res.disclaimer}</Alert>
              </div>
              {hid.current && <FeedbackBox key={hid.current} module="yield_prediction" historyId={hid.current} kind="yield" />}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
