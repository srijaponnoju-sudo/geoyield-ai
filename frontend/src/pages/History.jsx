import { useEffect, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Alert, Badge, Spinner, Collapsible } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";

const TABS = [[null, "hist.all"], ["crop_recommendation", "hist.crop"], ["yield_prediction", "hist.yield"], ["crop_health", "hist.health"], ["fertilizer_evaluation", "hist.fert"]];

export default function History() {
  const { t } = useLang();
  const [mod, setMod] = useState(null);
  const [items, setItems] = useState([]);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    setBusy(true); setError("");
    api.history(mod).then((d) => setItems(d.items)).catch((e) => setError(e.message)).finally(() => setBusy(false));
  }, [mod]);

  return (
    <>
      <PageHeader icon="🗂️" title={t("hist.title")} subtitle={t("hist.sub")} />
      <div className="container page">
        <div className="tabs">
          {TABS.map(([k, key]) => <button key={key} className={mod === k ? "on" : ""} onClick={() => setMod(k)}>{t(key)}</button>)}
        </div>
        {busy && <Spinner text={t("common.loading")} />}
        <Alert title={t("common.problem")}>{error}</Alert>
        {!busy && !error && items.length === 0 && <div className="card empty">{t("hist.none")}</div>}
        {items.map((r) => (
          <div className="card hist" key={r.module + r.id}>
            <div className="result-head">
              <div><h3>{t("mod." + r.module)}</h3><p>{r.summary}</p></div>
              <div className="right">
                <div className="muted small">{new Date(r.created_at).toLocaleString()}</div>
                <Badge tone={r.model_info.status === "trained" ? "green" : "amber"}>{r.model_info.status || "n/a"}</Badge>
              </div>
            </div>
            <Collapsible title={t("hist.show")}>
              <h4>{t("hist.inputs")}</h4><pre>{JSON.stringify(r.inputs, null, 2)}</pre>
              <h4>{t("hist.result")}</h4><pre>{JSON.stringify(r.result, null, 2)}</pre>
            </Collapsible>
          </div>
        ))}
      </div>
    </>
  );
}
