import { PageHeader } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";

const MODULES = [["🌾", "nav.crop", "landing.f1"], ["📈", "nav.yield", "landing.f2"], ["🩺", "nav.health", "landing.f3"], ["🧪", "nav.fertilizer", "landing.f4"]];
const TEAM = [["K Shiva Mallesh", "about.leader"], ["Ponnoju Srija", "about.member"], ["M Pranav", "about.member"], ["R Rishitha Rao", "about.member"]];
const TECH = [["Frontend", "React.js"], ["Backend", "Python FastAPI"], ["Machine Learning", "Scikit-learn"], ["Deep Learning", "TensorFlow/Keras"], ["Database", "SQLite"], ["Dev tools", "VS Code, Git, GitHub"]];
const REFS = [
  "Professor Jayashankar Telangana Agricultural University (PJTSAU)",
  "ICAR – Indian Institute of Rice Research",
  "Soil Health Card Scheme, Government of India",
  "Food and Agriculture Organization (FAO)",
  "Scikit-learn and TensorFlow documentation",
];

export default function About() {
  const { t } = useLang();
  return (
    <>
      <PageHeader icon="ℹ️" title={t("about.title")} subtitle={t("app.tagline")} />
      <div className="container page">
        <section className="card"><h3>{t("about.intro")}</h3><p>{t("about.introText")}</p></section>
        <div className="grid two mt">
          <section className="card"><h3>{t("about.problem")}</h3><p><b>{t("about.problemT")}</b></p><p>{t("about.problemD")}</p></section>
          <section className="card"><h3>{t("about.obj")}</h3>
            <ul className="list">{["o1", "o2", "o3", "o4"].map((k) => <li key={k}>{t("about." + k)}</li>)}</ul>
          </section>
        </div>
        <h2 className="section-title mt">{t("about.modules")}</h2>
        <div className="grid four">
          {MODULES.map(([i, title, d]) => <div className="card feature" key={title}><div className="icon">{i}</div><h3>{t(title)}</h3><p>{t(d)}</p></div>)}
        </div>
        <div className="grid two mt">
          <section className="card"><h3>{t("about.tech")}</h3>
            {TECH.map(([k, val]) => <div className="hist-row" key={k}><span>{k}</span><b>{val}</b></div>)}
          </section>
          <section className="card"><h3>{t("about.team")}</h3>
            <p className="muted">{t("about.teamSub")}</p>
            {TEAM.map(([n, r]) => <div className="hist-row" key={n}><b>{n}</b><span className="muted">{t(r)}</span></div>)}
          </section>
        </div>
        <section className="card mt"><h3>{t("about.refs")}</h3><ul className="list">{REFS.map((r) => <li key={r}>{r}</li>)}</ul></section>
      </div>
    </>
  );
}
