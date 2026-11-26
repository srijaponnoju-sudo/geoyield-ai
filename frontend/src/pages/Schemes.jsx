import { useEffect, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Field, Alert, Spinner, Badge } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { STATES } from "../data/locations.js";

export default function Schemes() {
  const { t, lang } = useLang();
  const [state, setState] = useState("");
  const [crop, setCrop] = useState("");
  const [season, setSeason] = useState("");
  const [opts, setOpts] = useState({ crops: [], seasons: [] });
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(true);

  useEffect(() => { api.yieldOptions().then(setOpts).catch(() => {}); }, []);
  useEffect(() => {
    setBusy(true); setError("");
    api.schemes(state, crop, season).then(setData).catch((e) => setError(e.message)).finally(() => setBusy(false));
  }, [state, crop, season, lang]);

  return (
    <>
      <PageHeader icon={"\u{1F3DB}\uFE0F"} title={t("sch.title")} subtitle={t("sch.sub")} />
      <div className="container page">
        <div className="card form">
          <p className="muted small">{t("sch.pick")}</p>
          <div className="form-grid three">
            <Field label={t("common.state")}>
              <select value={state} onChange={(e) => setState(e.target.value)}>
                <option value="">{t("common.selectState")}</option>
                {STATES.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.crop")}>
              <select value={crop} onChange={(e) => setCrop(e.target.value)}>
                <option value="">{t("common.select")}</option>
                {opts.crops.map((c) => <option key={c}>{c}</option>)}
              </select>
            </Field>
            <Field label={t("common.season")}>
              <select value={season} onChange={(e) => setSeason(e.target.value)}>
                <option value="">{t("common.select")}</option>
                {["Kharif", "Rabi"].map((s) => <option key={s} value={s}>{t("season." + s.toLowerCase())}</option>)}
              </select>
            </Field>
          </div>
        </div>

        {busy && <Spinner text={t("sch.loading")} />}
        <Alert title={t("common.problem")}>{error}</Alert>
        {data && <Alert kind="warn">{data.note}</Alert>}
        <div className="scheme-grid">
          {data && data.schemes.map((s) => (
            <div className="card scheme" key={s.id}>
              <div className="result-head">
                <h3>{s.name}</h3>
                {s.state_scheme && <Badge tone="green">{t("sch.stateTag")}</Badge>}
              </div>
              {s.relevance && <p className="scheme-rel"><b>{t("sch.forYou")}:</b> {s.relevance}</p>}
              <p>{s.benefit}</p>
              <h4>{t("sch.how")}</h4>
              <p>{s.how}</p>
              <p className="muted small">{t("sch.where")}: {s.link}</p>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}
