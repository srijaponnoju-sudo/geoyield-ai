import { useCallback, useEffect, useRef, useState } from "react";
import { api, cleanPayload } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Spinner, List, Badge, SpeakButton, cap } from "../components/ui.jsx";
import LocationFields from "../components/LocationFields.jsx";
import { SOIL_TYPES } from "../data/locations.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";

const NUM = ["ph", "N", "P", "K"];
const INIT = { crop: "", soil_type: "", ph: "", N: "", P: "", K: "", state: "", district: "", village: "", fertilizer: "" };
const OTHER = "__other__";
const VERDICT = { suitable: ["green", "fert.suitable"], potentially_suitable: ["amber", "fert.potential"], unsuitable: ["red", "fert.unsuitable"], cannot_evaluate: ["gray", "fert.cannot"] };
const NUT_KEY = { N: "fert.nitrogen", P: "fert.phosphorus", K: "fert.potassium" };

export default function FertilizerEvaluation() {
  const { t, lang } = useLang();
  const [v, setV] = useState(INIT);
  const [custom, setCustom] = useState(["", "", ""]);
  const [lists, setLists] = useState({ fertilizers: [], crops: [] });
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const sel = (k) => ({ value: v[k], onChange: (e) => set(k)(e.target.value) });

  useEffect(() => { api.fertilizers().then(setLists).catch((e) => setError(e.message)); }, [lang]);

  const reset = useCallback(() => { setV(INIT); setCustom(["", "", ""]); setRes(null); setError(""); lastRun.current = null; }, []);
  useRelang(lastRun, setRes);
  const onFill = useCallback((f) => {
    const keys = Object.keys(f).filter((k) => NUM.includes(k));
    setV((p) => { const n = { ...p }; keys.forEach((k) => { n[k] = String(f[k]); }); return n; });
    return keys;
  }, []);
  useVoiceEvents({ onFill, onReset: reset });

  function example() {
    setV((p) => ({ ...p, crop: "rice", ph: "6.5", N: "80", P: "20", K: "40", fertilizer: "MOP (Muriate of Potash)" }));
  }

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(""); setRes(null);
    const payload = cleanPayload({ ...v, fertilizer: v.fertilizer === OTHER ? "Custom fertilizer" : v.fertilizer }, NUM);
    if (v.fertilizer === OTHER) {
      if (custom.some((c) => c === "")) { setError(t("fert.errCustom")); setBusy(false); return; }
      payload.custom_npk = custom.map(Number);
    }
    lastRun.current = (re) => api.evaluateFertilizer({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); }
    finally { setBusy(false); }
  }

  const [tone, labelKey] = res ? VERDICT[res.verdict] || ["gray", "fert.cannot"] : [];
  const speech = res && res.verdict !== "cannot_evaluate"
    ? t("fert.speak", { f: res.fertilizer, c: res.crop_label, v: t(labelKey), r: res.reasons.slice(-1)[0] || "",
        alt: res.alternative ? t("fert.speakAlt", { a: res.alternative.fertilizer }) : "" }) : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon="🧪" title={t("fert.title")} subtitle={t("fert.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("fert.cropSoil")}</h3>
          <div className="form-grid">
            <Field label={t("common.crop")}>
              <select required {...sel("crop")}><option value="">{t("fert.selectCrop")}</option>{lists.crops.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select>
            </Field>
            <Field label={t("common.soilType")}>
              <select {...sel("soil_type")}><option value="">{t("common.select")}</option>{SOIL_TYPES.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
            <LocationFields value={v} onChange={(loc) => setV((p) => ({ ...p, ...loc }))} />
            <Field label={t("fert.ph")}><NumberInput min={3} max={10} value={v.ph} onChange={set("ph")} /></Field>
            <Field label={t("fert.N")} hint={t("fert.fromTest")}><NumberInput required min={0} max={300} value={v.N} onChange={set("N")} /></Field>
            <Field label={t("fert.P")}><NumberInput required min={0} max={300} value={v.P} onChange={set("P")} /></Field>
            <Field label={t("fert.K")}><NumberInput required min={0} max={400} value={v.K} onChange={set("K")} /></Field>
          </div>
          <h3>{t("fert.yours")}</h3>
          <Field label={t("fert.selected")}>
            <select required {...sel("fertilizer")}>
              <option value="">{t("fert.selectFert")}</option>
              {lists.fertilizers.map((f) => <option key={f.name} value={f.name}>{f.name} ({f.npk.join("-")})</option>)}
              <option value={OTHER}>{t("fert.other")}</option>
            </select>
          </Field>
          {v.fertilizer === OTHER && (
            <div className="form-grid">
              {["N %", "P₂O₅ %", "K₂O %"].map((l, i) => (
                <Field key={l} label={l}>
                  <NumberInput required min={0} max={100} value={custom[i]} onChange={(x) => setCustom((c) => c.map((y, j) => (j === i ? x : y)))} />
                </Field>
              ))}
            </div>
          )}
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy}>{busy ? t("fert.evaluating") : t("fert.btn")}</button>
            <button type="button" className="btn outline" onClick={example}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner text={t("fert.evaluating")} />}
          <Alert title={t("common.problem")}>{error}</Alert>
          {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && res.verdict === "cannot_evaluate" && <Alert kind="warn" title={t("fert.cannot")}>{res.explanation}</Alert>}
          {res && res.verdict !== "cannot_evaluate" && (
            <div className="results">
              <div className="card result">
                <div className="muted">{t("fert.for", { f: res.fertilizer, c: cap(res.crop_label) })}</div>
                <div className="verdict"><Badge tone={tone}>{t(labelKey)}</Badge></div>
                <SpeakButton text={speech} />
                <h4>{t("fert.soilStatus")}</h4>
                <div className="metric-grid">
                  {Object.entries(res.soil_status).map(([k, s]) => (
                    <div key={k}><span>{t(NUT_KEY[k])}</span><b className={`st-${s}`}>{t("fert." + s)}</b></div>
                  ))}
                </div>
                <h4>{t("fert.why")}</h4><List items={res.reasons} />
                {res.ph_note && <Alert kind="warn">{res.ph_note}</Alert>}
              </div>
              {res.alternative && (
                <div className="card result alt-card">
                  <h4>{t("fert.alt")}</h4>
                  <h3>{res.alternative.fertilizer} <small>({res.alternative.npk.join("-")})</small></h3>
                  <p>{res.alternative.why}</p>
                </div>
              )}
              <div className="card">
                <h4>{t("fert.use")}</h4><List items={res.guidance} />
                <p className="muted small">{t("fert.src", { s: res.npk_source, m: res.method })}</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
