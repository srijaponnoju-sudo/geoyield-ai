import { useState } from "react";
import { useLang } from "../i18n/LanguageContext.jsx";
import { speakAny, stopSpeaking } from "../voice/speech.js";

export const cap = (s = "") => s.charAt(0).toUpperCase() + s.slice(1);

export function PageHeader({ icon, title, subtitle }) {
  return (
    <section className="page-head">
      <div className="container">
        <div className="eyebrow">{icon}</div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
    </section>
  );
}

export function Field({ label, hint, children }) {
  return (
    <label className="field">
      <span className="label">{label}</span>
      {children}
      {hint && <span className="hint">{hint}</span>}
    </label>
  );
}

export function NumberInput({ value, onChange, min, max, step = "any", required, placeholder }) {
  return (
    <input type="number" inputMode="decimal" value={value} min={min} max={max} step={step} required={required}
      placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
  );
}

export function Alert({ kind = "error", title, children }) {
  if (!children) return null;
  return (
    <div className={`alert ${kind}`} role="alert">
      {title && <b>{title}</b>}
      <div>{children}</div>
    </div>
  );
}

export function Bar({ label, value, max = 1, text, tone = "green" }) {
  const pct = Math.max(0, Math.min(100, (value / max) * 100));
  return (
    <div className="bar-row">
      <div className="bar-label"><span>{label}</span><b>{text ?? `${pct.toFixed(1)}%`}</b></div>
      <div className="bar-track"><div className={`bar-fill ${tone}`} style={{ width: `${pct}%` }} /></div>
    </div>
  );
}

export function Badge({ tone = "gray", children }) {
  return <span className={`badge ${tone}`}>{children}</span>;
}

export function Spinner({ text }) {
  const { t } = useLang();
  return <div className="spinner-row"><span className="spinner" />{text || t("common.analysing")}</div>;
}

export function List({ items, tone }) {
  if (!items?.length) return null;
  return <ul className={`list ${tone || ""}`}>{items.map((x, i) => <li key={i}>{x}</li>)}</ul>;
}

export function Collapsible({ title, children }) {
  const { t } = useLang();
  const [open, setOpen] = useState(false);
  return (
    <div className="collapsible">
      <button type="button" className="link-btn" onClick={() => setOpen(!open)}>
        {open ? t("hist.hide") : t("hist.showWord")} {title}
      </button>
      {open && <div className="collapsible-body">{children}</div>}
    </div>
  );
}

/** Reads a sentence aloud in the current language. */
export function SpeakButton({ text }) {
  const { t, lang } = useLang();
  const [on, setOn] = useState(false);
  const [msg, setMsg] = useState("");
  if (!text) return null;
  async function toggle() {
    if (on) { stopSpeaking(); setOn(false); return; }
    setMsg(""); setOn(true);
    const r = await speakAny(text, lang, () => setOn(false));
    if (r === "failed") { setOn(false); setMsg(t("common.voiceFail")); }
  }
  return (
    <div>
      <button type="button" className="btn outline" onClick={toggle}>{on ? t("common.stopListen") : t("common.listen")}</button>
      {msg && <p className="muted small">{msg}</p>}
    </div>
  );
}
