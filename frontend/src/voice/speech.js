// Text-to-speech helpers: browser voice (Web Speech API) with a backend voice (gTTS) as fallback.
import { ttsBlob } from "../services/api.js";
export const LOCALE = { en: "en-IN", hi: "hi-IN", te: "te-IN" };

export const ttsSupported = () => typeof window !== "undefined" && "speechSynthesis" in window;

function pickVoice(lang) {
  const voices = window.speechSynthesis.getVoices();
  const want = LOCALE[lang].toLowerCase();
  const v = voices.find((x) => x.lang.toLowerCase().replace("_", "-") === want)
    || voices.find((x) => x.lang.toLowerCase().startsWith(lang));
  return { voice: v, loaded: voices.length > 0 };
}

/** returns "ok" | "novoice" | "unsupported" */
export function speak(text, lang, onEnd) {
  if (!ttsSupported()) return "unsupported";
  const synth = window.speechSynthesis;
  synth.cancel();
  const { voice, loaded } = pickVoice(lang);
  if (!voice && loaded && lang !== "en") return "novoice";
  const u = new SpeechSynthesisUtterance(text);
  if (voice) u.voice = voice;
  u.lang = LOCALE[lang];
  u.onend = () => onEnd && onEnd();
  u.onerror = () => onEnd && onEnd();
  synth.speak(u);
  return "ok";
}

let audio = null;
export const stopSpeaking = () => {
  if (ttsSupported()) window.speechSynthesis.cancel();
  if (audio) { audio.pause(); audio = null; }
};

/** Browser voice first; if this PC has no voice for the language, use the backend voice. Returns "ok" | "remote" | "failed" */
export async function speakAny(text, lang, onEnd) {
  const r = speak(text, lang, onEnd);
  if (r === "ok") return "ok";
  try {
    const blob = await ttsBlob(text, lang);
    stopSpeaking();
    audio = new Audio(URL.createObjectURL(blob));
    audio.onended = () => onEnd && onEnd();
    await audio.play();
    return "remote";
  } catch {
    return "failed";
  }
}
