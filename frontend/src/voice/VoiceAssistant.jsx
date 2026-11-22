import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useLang } from "../i18n/LanguageContext.jsx";
import { LOCALE, speakAny, stopSpeaking } from "./speech.js";
import { parseCommand, NAV_KEY, FIELD_LABEL } from "./parser.js";
import { useVoice } from "./VoiceContext.jsx";

const SR = typeof window !== "undefined" ? window.SpeechRecognition || window.webkitSpeechRecognition : null;

export default function VoiceAssistant() {
  const { t, lang, setLang } = useLang();
  const { speechText } = useVoice();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [listening, setListening] = useState(false);
  const [heard, setHeard] = useState("");
  const [reply, setReply] = useState("");
  const [error, setError] = useState(false);
  const rec = useRef(null);
  const textRef = useRef(speechText);
  useEffect(() => { textRef.current = speechText; }, [speechText]);

  function say(msg, bad = false) { setReply(msg); setError(bad); }

  async function readResult() {
    if (!textRef.current) return say(t("voice.noresult"), true);
    say(t("voice.readBtn"));
    const r = await speakAny(textRef.current, lang);
    if (r === "failed") say(t("common.voiceFail"), true);
  }

  function handle(text) {
    const cmd = parseCommand(text);
    switch (cmd.intent) {
      case "lang": setLang(cmd.lang); say(t("voice.lang")); break;
      case "read": readResult(); break;
      case "reset": window.dispatchEvent(new CustomEvent("geoyield:reset")); say(t("voice.cleared")); break;
      case "submit": {
        const btn = document.querySelector("form button.btn.primary:not(:disabled)");
        if (btn) { btn.click(); say(t("voice.submitted")); } else say(t("voice.nofields"), true);
        break;
      }
      case "fill": {
        const detail = { fields: cmd.fields, applied: [] };
        window.dispatchEvent(new CustomEvent("geoyield:fill", { detail }));
        if (detail.applied.length)
          say(t("voice.filled", { n: detail.applied.length, list: detail.applied.map((k) => `${FIELD_LABEL[k]}=${cmd.fields[k]}`).join(", ") }));
        else say(t("voice.nofields"), true);
        break;
      }
      case "navigate": navigate(cmd.path); say(t("voice.opened", { page: t(NAV_KEY[cmd.path]) })); break;
      default: say(t("voice.unknown"), true);
    }
  }

  function start() {
    if (!SR) return say(t("voice.nosupport"), true);
    stopSpeaking();
    const r = new SR();
    r.lang = LOCALE[lang]; r.interimResults = false; r.maxAlternatives = 1; r.continuous = false;
    r.onstart = () => { setListening(true); setHeard(""); say(""); };
    r.onresult = (e) => { const text = e.results[0][0].transcript; setHeard(text); handle(text); };
    r.onerror = (e) => say(e.error === "not-allowed" || e.error === "service-not-allowed" ? t("voice.denied") : t("voice.nospeech"), true);
    r.onend = () => setListening(false);
    rec.current = r;
    try { r.start(); } catch { /* already running */ }
  }

  function stop() { try { rec.current?.stop(); } catch { /* ignore */ } setListening(false); }

  return (
    <>
      <button className={`voice-fab ${listening ? "live" : ""}`} onClick={() => setOpen(!open)} aria-label={t("voice.title")}>🎤</button>
      {open && (
        <div className="voice-panel card" role="dialog" aria-label={t("voice.title")}>
          <div className="result-head"><h3>🎤 {t("voice.title")}</h3><button className="link-btn" onClick={() => { stop(); setOpen(false); }}>✕</button></div>
          <button className={`btn primary lg voice-main ${listening ? "live" : ""}`} onClick={listening ? stop : start}>
            {listening ? t("voice.listening") : t("voice.tap")}
          </button>
          {heard && <p className="small"><b>{t("voice.heard")}</b> {heard}</p>}
          {reply && <p className={`small ${error ? "voice-err" : "voice-ok"}`}>{reply}</p>}
          <button className="btn outline" onClick={readResult}>{t("voice.readBtn")}</button>
          <h4>{t("voice.help")}</h4>
          <ul className="list small">{["c1", "c2", "c3", "c4", "c5"].map((k) => <li key={k}>{t("voice." + k)}</li>)}</ul>
          <p className="muted small">{t("voice.note")}</p>
        </div>
      )}
    </>
  );
}
