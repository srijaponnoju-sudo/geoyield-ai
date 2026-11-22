import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../services/api.js";
import { Badge, Alert } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";

const MODULES = [["🌾", "nav.crop", "dash.m1", "/crop-recommendation"], ["📈", "nav.yield", "dash.m2", "/yield-prediction"],
  ["🩺", "nav.health", "dash.m3", "/crop-health"], ["🧪", "nav.fertilizer", "dash.m4", "/fertilizer"]];
const tone = (s = "") => (s.startsWith("trained") ? "green" : s.startsWith("unavailable") ? "red" : "amber");
const statusKey = (s = "") => "status." + (s.startsWith("rule-based") ? "rule-based" : s.split(" ")[0]);

export default function Dashboard() {
  const { t } = useLang();
  const [recent, setRecent] = useState([]);
  const [models, setModels] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    api.history(null, 5).then((d) => setRecent(d.items)).catch((e) => setError(e.message));
    api.status().then((d) => setModels(d.models)).catch(() => {});
  }, []);

  return (
    <div className="container page">
      <div className="welcome card">
        <div><h1>{t("dash.welcome")}</h1><p>{t("dash.sub")}</p></div>
        <Link to="/crop-recommendation" className="btn primary">{t("dash.start")}</Link>
      </div>

      <div className="grid four mt">
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
          <h3 className="mt">{t("dash.insights")}</h3>
          <ul className="list">{["i1", "i2", "i3", "i4"].map((k) => <li key={k}>{t("dash." + k)}</li>)}</ul>
        </section>
      </div>
    </div>
  );
}
