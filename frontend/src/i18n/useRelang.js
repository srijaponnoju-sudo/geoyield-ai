import { useEffect, useRef } from "react";
import { useLang } from "./LanguageContext.jsx";

/**
 * When the language changes, re-run the last analysis (without saving it again) so the explanations
 * written by the backend are translated too - not only the page headings.
 * lastRun.current must be a function (relocalize) => Promise<result>, or null when there is no result.
 */
export function useRelang(lastRun, apply) {
  const { lang } = useLang();
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return undefined; }
    if (!lastRun.current) return undefined;
    let alive = true;
    lastRun.current(true).then((r) => { if (alive) apply(r); }).catch(() => {});
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lang]);
}
