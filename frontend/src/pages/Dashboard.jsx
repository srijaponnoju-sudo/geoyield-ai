import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../services/api.js";
import { Badge, Alert } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";

const MODULES = [["\u{1F33E}", "nav.crop", "dash.m1", "/crop-recommendation"], ["\u{1F4C8}", "nav.yield", "dash.m2", "/yield-prediction"],
  ["\u{1FA7A}", "nav.health", "dash.m3", "/crop-health"], ["\u{1F9EA}", "nav.fertilizer", "dash.m4", "/fertilizer"],
  ["\u{1F4B0}", "nav.profit", "dash.m5", "/profit"], ["\u{1F3DB}\uFE0F", "nav.schemes", "dash.m6", "/schemes"]];
const tone = (s = "") => (s.startsWith("trained") ? "green" : s.startsWith("unavailable") ? "red" : "amber");
const statusKey = (s = "") => "status." + (s.startsWith("rule-based") ? "rule-based" : s.split(" ")[0]);

export default function Dashboard() {
  const { t } = useLang();
  const [recent, setRecent] = useState([]);
  const [models, setModels] = useState(null);
  const [error, setError] = useState("");
  const [real, setReal] = useState(null);

  useEffect(() => {
    api.history(null, 5).then((d) => setRecent(d.items)).catch((e) => setError(e.message));
    api.status().then((d) => setModels(d.models)).catch(() => {});
    api.feedbackSummary().then(setReal).catch(() => {});
  }, []);

  return (
    <div className="container page">
      <div className="welcome card">
        <div><h1>{t("dash.welcome")}</h1><p>{t("dash.sub")}</p></div>
        <Link to="/crop-recommendation" className="btn primary">{t("dash.start")}</Link>
      </div>

      <div className="grid six mt">
        {MODULES.map(([i, title, d, to]) => (
          <Link key={to} to={to} className="card feature">
            <div className="icon">{i}</div><h3>{t(title)}</h3><p>{t(d)}</p><span className="more">{t("common.open")}</span>
          </Link>
        ))}
      </div>

      <div className="grid two mt">
        <section className="card">
          <h3>{t("dash.recent")}</h3>
          <Alert>{error}</Alert>
          {!error && recent.length === 0 && <p className="muted">{t("dash.none")}</p>}
          {recent.map((r) => (
            <div className="hist-row" key={r.module + r.id}>
              <div><b>{t("mod." + r.module)}</b><div className="muted small">{r.summary}</div></div>
              <div className="muted small">{new Date(r.created_at).toLocaleString()}</div>
            </div>
          ))}
          <Link to="/history" className="more">{t("dash.viewAll")}</Link>
        </section>

        <section className="card">
          <h3>{t("dash.models")}</h3>
          {!models && <p className="muted">{t("dash.checking")}</p>}
          {models && Object.entries(models).map(([k, v]) => (
            <div className="hist-row" key={k}>
              <span>{t("mod." + k)}</span><Badge tone={tone(v.status)}>{t(statusKey(v.status))}</Badge>
            </div>
          ))}
          <h3 className="mt">{t("dash.real")}</h3>
          {(!real || real.total === 0) && <p className="muted small">{t("dash.realNone")}</p>}
          {real && Object.entries(real.by_module).filter(([, m]) => m.count > 0).map(([k, m]) => (
            <div className="hist-row" key={k}><span>{t("mod." + k)}</span><b>{t("dash.realRight", { n: m.count, p: m.percent_right })}</b></div>
          ))}
          {real && real.yield_error && <p className="muted small">{t("dash.realYield", { e: real.yield_error.mean_pct_error, n: real.yield_error.count, w: real.yield_error.within_20_percent })}</p>}
          <h3 className="mt">{t("dash.insights")}</h3>
          <ul className="list">{["i1", "i2", "i3", "i4"].map((k) => <li key={k}>{t("dash." + k)}</li>)}</ul>
        </section>
      </div>
    </div>
  );
}
