import { useState } from "react";
import { NavLink, Link } from "react-router-dom";
import Logo from "./Logo.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { LANGS } from "../i18n/translations.js";

const LINKS = [
  ["/dashboard", "nav.dashboard"], ["/crop-recommendation", "nav.crop"], ["/yield-prediction", "nav.yield"],
  ["/crop-health", "nav.health"], ["/fertilizer", "nav.fertilizer"], ["/history", "nav.history"], ["/about", "nav.about"],
];

export default function Navbar() {
  const [open, setOpen] = useState(false);
  const { t, lang, setLang } = useLang();
  return (
    <header className="nav">
      <div className="container nav-inner">
        <Link to="/" className="brand" onClick={() => setOpen(false)}>
          <Logo /><span>GeoYield <b>AI</b></span>
        </Link>
        <nav className={`nav-links ${open ? "open" : ""}`}>
          {LINKS.map(([to, key]) => (
            <NavLink key={to} to={to} onClick={() => setOpen(false)} className={({ isActive }) => (isActive ? "active" : "")}>
              {t(key)}
            </NavLink>
          ))}
        </nav>
        <div className="lang-switch" role="group" aria-label="Language">
          {LANGS.map(([code, label]) => (
            <button key={code} className={lang === code ? "on" : ""} onClick={() => setLang(code)}>{label}</button>
          ))}
        </div>
        <button className="burger" aria-label="Menu" onClick={() => setOpen(!open)}><span /><span /><span /></button>
      </div>
    </header>
  );
}
