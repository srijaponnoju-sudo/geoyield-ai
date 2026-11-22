import { useLang } from "../i18n/LanguageContext.jsx";

export default function Footer() {
  const { t } = useLang();
  return (
    <footer className="footer">
      <div className="container">
        <div><b>GeoYield AI</b> - {t("app.tagline")}</div>
        <div className="muted">{t("footer.team")}</div>
        <div className="muted small">{t("footer.note")}</div>
      </div>
    </footer>
  );
}
