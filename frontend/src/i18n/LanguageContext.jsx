import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { translations } from "./translations.js";
import { setApiLang } from "../services/api.js";

const Ctx = createContext(null);

export function LanguageProvider({ children }) {
  const [lang, setLang] = useState(() => {
    try {
      const saved = localStorage.getItem("geoyield_lang");
      return translations[saved] ? saved : "en";
    } catch {
      return "en";
    }
  });
  setApiLang(lang); // keep API requests in the same language as the screen

  useEffect(() => {
    document.documentElement.lang = lang;
    try { localStorage.setItem("geoyield_lang", lang); } catch { /* ignore */ }
  }, [lang]);

  const t = useCallback((key, vars) => {
    let s = translations[lang][key] ?? translations.en[key] ?? key;
    if (vars) for (const [a, b] of Object.entries(vars)) s = s.split("{" + a + "}").join(String(b));
    return s;
  }, [lang]);

  return <Ctx.Provider value={{ lang, setLang, t }}>{children}</Ctx.Provider>;
}

export const useLang = () => useContext(Ctx);
