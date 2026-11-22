import { Link } from "react-router-dom";
import { useLang } from "../i18n/LanguageContext.jsx";

const FEATURES = [["🌾", "nav.crop", "landing.f1", "/crop-recommendation"], ["📈", "nav.yield", "landing.f2", "/yield-prediction"],
  ["🩺", "nav.health", "landing.f3", "/crop-health"], ["🧪", "nav.fertilizer", "landing.f4", "/fertilizer"]];
const STEPS = ["1", "2", "3", "4", "5"];
const BENEFITS = ["b1", "b2", "b3", "b4", "b5"];

export default function Landing() {
  const { t } = useLang();
  return (
    <>
      <section className="hero">
        <div className="container hero-inner">
          <div className="hero-text">
            <span className="pill">{t("landing.pill")}</span>
            <h1>GeoYield <span className="accent">AI</span></h1>
            <p className="tagline">{t("app.tagline")}</p>
            <p className="lead">{t("landing.lead")}</p>
            <div className="hero-cta">
              <Link to="/dashboard" className="btn primary lg">{t("landing.getStarted")}</Link>
              <Link to="/about" className="btn ghost lg">{t("landing.aboutBtn")}</Link>
            </div>
          </div>
          <div className="hero-card" aria-hidden="true">
            <div className="hc-row"><span>{t("landing.cardSoil")}</span><b>N · P · K · pH</b></div>
            <div className="hc-row"><span>{t("landing.cardWeather")}</span><b>°C · % · mm</b></div>
            <div className="hc-arrow">{t("landing.cardAI")}</div>
            <div className="hc-result">{t("landing.cardOut")}</div>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <h2 className="section-title">{t("landing.features")}</h2>
          <div className="grid four">
            {FEATURES.map(([icon, title, desc, to]) => (
              <Link to={to} key={to} className="card feature">
                <div className="icon">{icon}</div><h3>{t(title)}</h3><p>{t(desc)}</p>
              </Link>
            ))}
          </div>
        </div>
      </section>

      <section className="section alt">
        <div className="container">
          <h2 className="section-title">{t("landing.how")}</h2>
          <div className="steps">
            {STEPS.map((n) => (
              <div className="step" key={n}>
                <div className="step-n">{n}</div><h4>{t(`landing.s${n}`)}</h4><p>{t(`landing.s${n}d`)}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container two-col">
          <div>
            <h2 className="section-title left">{t("landing.benefits")}</h2>
            <ul className="check-list">{BENEFITS.map((b) => <li key={b}>{t(`landing.${b}`)}</li>)}</ul>
          </div>
          <div className="card callout">
            <h3>{t("landing.calloutT")}</h3>
            <p>{t("landing.calloutD")}</p>
            <Link to="/dashboard" className="btn primary">{t("landing.openDash")}</Link>
          </div>
        </div>
      </section>
    </>
  );
}
