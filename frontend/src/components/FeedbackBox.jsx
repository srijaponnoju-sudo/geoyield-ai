import { useState } from "react";
import { api } from "../services/api.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { Alert } from "./ui.jsx";

/** "Was this right?" box. kind: "yield" | "crop" | "profit" decides which real value we ask for. */
export default function FeedbackBox({ module, historyId, kind }) {
  const { t } = useLang();
  const [choice, setChoice] = useState(null);
  const [actual, setActual] = useState("");
  const [comment, setComment] = useState("");
  const [state, setState] = useState("idle"); // idle | sending | done
  const [error, setError] = useState("");
  if (!historyId) return null;

  async function send() {
    setState("sending"); setError("");
    const body = { module, history_id: historyId, correct: choice };
    if (comment.trim()) body.comment = comment.trim();
    if (actual.trim() !== "") {
      if (kind === "yield") body.actual_yield = Number(actual);
      else if (kind === "profit") body.actual_price = Number(actual);
      else body.actual_crop = actual.trim();
    }
    try { await api.sendFeedback(body); setState("done"); }
    catch (e) { setError(e.message); setState("idle"); }
  }

  const label = kind === "yield" ? t("fb.actualYield") : kind === "profit" ? t("fb.actualPrice") : t("fb.actualCrop");
  return (
    <div className="card feedback">
      <h4>{t("fb.q")}</h4>
      <p className="muted small">{t("fb.sub")}</p>
      {state === "done" ? <Alert kind="info">{t("fb.thanks")}</Alert> : (
        <>
          <div className="btn-row">
            <button type="button" className={"btn " + (choice === true ? "primary" : "outline")} onClick={() => setChoice(true)}>{"\u{1F44D} "}{t("fb.yes")}</button>
            <button type="button" className={"btn " + (choice === false ? "primary" : "outline")} onClick={() => setChoice(false)}>{"\u{1F44E} "}{t("fb.no")}</button>
          </div>
          {choice !== null && (
            <div className="fb-more">
              <label className="field">
                <span className="label">{label}</span>
                <input type={kind === "crop" ? "text" : "number"} min="0" step="any" value={actual} onChange={(e) => setActual(e.target.value)} />
              </label>
              <label className="field">
                <span className="label">{t("fb.comment")}</span>
                <input type="text" maxLength={500} value={comment} onChange={(e) => setComment(e.target.value)} />
              </label>
              <button type="button" className="btn primary" disabled={state === "sending"} onClick={send}>{t("fb.send")}</button>
            </div>
          )}
          <Alert title={t("fb.err")}>{error}</Alert>
        </>
      )}
    </div>
  );
}
