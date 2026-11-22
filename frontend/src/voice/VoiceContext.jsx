import { createContext, useContext, useEffect, useState } from "react";

const Ctx = createContext({ speechText: "", setSpeechText: () => {} });

export function VoiceProvider({ children }) {
  const [speechText, setSpeechText] = useState("");
  return <Ctx.Provider value={{ speechText, setSpeechText }}>{children}</Ctx.Provider>;
}

/** A page calls this with the sentence that should be read aloud for its current result ("" when none). */
export function useSpeechText(text) {
  const { setSpeechText } = useContext(Ctx);
  useEffect(() => {
    setSpeechText(text || "");
    return () => setSpeechText("");
  }, [text, setSpeechText]);
}

export const useVoice = () => useContext(Ctx);

/** Lets the voice assistant fill / reset a page's form. */
export function useVoiceEvents({ onFill, onReset }) {
  useEffect(() => {
    const fill = (e) => { const applied = onFill ? onFill(e.detail.fields) : []; e.detail.applied.push(...applied); };
    const reset = () => onReset && onReset();
    window.addEventListener("geoyield:fill", fill);
    window.addEventListener("geoyield:reset", reset);
    return () => {
      window.removeEventListener("geoyield:fill", fill);
      window.removeEventListener("geoyield:reset", reset);
    };
  }, [onFill, onReset]);
}
