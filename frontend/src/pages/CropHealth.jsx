import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Field, Alert, Bar, Spinner, List, Collapsible, Badge, SpeakButton } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";

// [value sent to the backend (English), label key]
const SYMPTOMS = [["yellow leaves", "sym.yellow"], ["brown spots", "sym.brown"], ["leaf curling", "sym.curl"], ["white patches", "sym.white"],
  ["stunted growth", "sym.stunt"], ["drying leaves", "sym.dry"], ["wilting", "sym.wilt"], ["purple leaves", "sym.purple"],
  ["brown edges", "sym.edges"], ["mosaic", "sym.mosaic"]];
const MAX_MB = 5;
const pretty = (s) => s.replace(/_+/g, " ");

function ImageTab() {
  const { t } = useLang();
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState("");
  const [crop, setCrop] = useState("");
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [unavailable, setUnavailable] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  useRelang(lastRun, setRes);

  useEffect(() => {
    return () => { if (preview) URL.revokeObjectURL(preview); };
  }, [preview]);

  const reset = useCallback(() => { setFile(null); setPreview(""); setCrop(""); setRes(null); setError(""); setUnavailable(""); lastRun.current = null; }, []);
  useVoiceEvents({ onFill: () => [], onReset: reset });

  function pick(e) {
    const f = e.target.files?.[0];
    setRes(null); setError(""); setUnavailable("");
    if (!f) return;
    if (!["image/jpeg", "image/png"].includes(f.type)) { setError(t("health.errType")); setFile(null); setPreview(""); return; }
    if (f.size > MAX_MB * 1024 * 1024) { setError(t("health.errSize", { mb: MAX_MB })); setFile(null); setPreview(""); return; }
    setFile(f); setPreview(URL.createObjectURL(f));
  }

  async function submit(e) {
    e.preventDefault();
    if (!file) { setError(t("health.errChoose")); return; }
    setBusy(true); setError(""); setRes(null); setUnavailable("");
    lastRun.current = (re) => api.healthImage(file, crop, !!re);
    try { setRes(await lastRun.current(false)); }
    catch (err) { err.status === 503 ? setUnavailable(err.message) : setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res ? t("health.speakImg", { label: pretty(res.predicted_label), p: Math.round(res.confidence * 100), warn: res.low_confidence ? res.warning : "" }) : "";
  useSpeechText(speech);

  return (
    <div className="two-col wide-left">
      <form className="card form" onSubmit={submit}>
        <h3>{t("health.upload")}</h3>
        <Field label={t("health.cropOpt")}><input value={crop} onChange={(e) => setCrop(e.target.value)} /></Field>
        <Field label={t("health.image", { mb: MAX_MB })}>
          <input key={preview ? "has" : "none"} type="file" accept="image/jpeg,image/png" onChange={pick} />
        </Field>
        {preview && <img className="preview" src={preview} alt={t("health.preview")} />}
        <p className="muted small">{t("health.tip")}</p>
        <div className="btn-row">
          <button className="btn primary lg" disabled={busy || !file}>{busy ? t("common.analysing") : t("health.btnImage")}</button>
          <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
        </div>
      </form>
      <div>
        {busy && <Spinner />}
        <Alert title={t("common.problem")}>{error}</Alert>
        {unavailable && <Alert kind="warn" title={t("health.imgNot")}>{unavailable}</Alert>}
        {!res && !busy && !error && !unavailable && <div className="card empty">{t("common.resultsHere")}</div>}
        {res && (
          <div className="results">
            {res.low_confidence && <Alert kind="warn" title={t("health.lowConf")}>{res.warning}</Alert>}
            <div className="card result">
              <div className="muted">{t("health.predicted")}</div>
              <h3>{pretty(res.predicted_label)}</h3>
              <Bar label={t("health.confidence")} value={res.confidence} tone={res.low_confidence ? "amber" : "green"} />
              <h4>{t("health.others")}</h4>
              {res.top_predictions.slice(1).map((p) => <Bar key={p.label} label={pretty(p.label)} value={p.confidence} tone="navy" />)}
              {res.guidance && (<><h4>{t("health.next")}</h4><List items={res.guidance.next_steps} /><h4>{t("health.prev")}</h4><List items={res.guidance.prevention} /></>)}
              <SpeakButton text={speech} />
              <Collapsible title={t("health.classes")}><p className="small">{res.supported_classes.map(pretty).join(" · ")}</p></Collapsible>
              <p className="muted small">{res.disclaimer}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function SymptomTab() {
  const { t } = useLang();
  const [picked, setPicked] = useState([]);
  const [crop, setCrop] = useState("");
  const [desc, setDesc] = useState("");
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  useRelang(lastRun, setRes);
  const toggle = (s) => setPicked((p) => (p.includes(s) ? p.filter((x) => x !== s) : [...p, s]));
  const reset = useCallback(() => { setPicked([]); setCrop(""); setDesc(""); setRes(null); setError(""); lastRun.current = null; }, []);
  useVoiceEvents({ onFill: () => [], onReset: reset });

  async function submit(e) {
    e.preventDefault();
    if (!picked.length && !desc.trim()) { setError(t("health.errPick")); return; }
    setBusy(true); setError(""); setRes(null);
    const payload = { crop: crop.trim() || undefined, symptoms: picked, description: desc.trim() || undefined };
    lastRun.current = (re) => api.healthSymptoms({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res && res.possible_conditions.length
    ? t("health.speakSym", { list: res.possible_conditions.slice(0, 2).map((c) => c.condition).join(", ") }) : "";
  useSpeechText(speech);

  return (
    <div className="two-col wide-left">
      <form className="card form" onSubmit={submit}>
        <h3>{t("health.describe")}</h3>
        <Field label={t("health.cropOpt")}><input value={crop} onChange={(e) => setCrop(e.target.value)} /></Field>
        <div className="label">{t("health.visible")}</div>
        <div className="chips">
          {SYMPTOMS.map(([val, key]) => (
            <button type="button" key={val} className={`chip ${picked.includes(val) ? "on" : ""}`} onClick={() => toggle(val)}>{t(key)}</button>
          ))}
        </div>
        <Field label={t("health.words")}>
          <textarea rows={4} value={desc} onChange={(e) => setDesc(e.target.value)} placeholder={t("health.ph")} />
        </Field>
        <div className="btn-row">
          <button className="btn primary lg" disabled={busy}>{busy ? t("common.analysing") : t("health.btnSym")}</button>
          <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
        </div>
      </form>
      <div>
        {busy && <Spinner />}
        <Alert title={t("common.problem")}>{error}</Alert>
        {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
        {res && (
          <div className="results">
            <Alert kind="info">{res.disclaimer}</Alert>
            <Alert kind="warn">{res.message}</Alert>
            <SpeakButton text={speech} />
            {res.possible_conditions.map((c) => (
              <div className="card result" key={c.id}>
                <div className="result-head"><h3>{c.condition}</h3><Badge tone="amber">{t("health.possible")}</Badge></div>
                <h4>{t("health.support")}</h4>
                <div className="chips">{c.supporting_symptoms.map((s) => <span className="chip on static" key={s}>{s}</span>)}</div>
                <h4>{t("health.next")}</h4><List items={c.recommended_next_steps} />
                <h4>{t("health.prev")}</h4><List items={c.preventive_measures} />
              </div>
            ))}
            <p className="muted small">{t("health.method")}: {res.method}</p>
          </div>
        )}
      </div>
    </div>
  );
}

export default function CropHealth() {
  const { t } = useLang();
  const [tab, setTab] = useState("image");
  return (
    <>
      <PageHeader icon="🩺" title={t("health.title")} subtitle={t("health.sub")} />
      <div className="container page">
        <div className="tabs">
          <button className={tab === "image" ? "on" : ""} onClick={() => setTab("image")}>{t("health.tabImage")}</button>
          <button className={tab === "symptoms" ? "on" : ""} onClick={() => setTab("symptoms")}>{t("health.tabSym")}</button>
        </div>
        {tab === "image" ? <ImageTab /> : <SymptomTab />}
      </div>
    </>
  );
}
