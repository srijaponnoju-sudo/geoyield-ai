"""Regional check: is a recommended crop recorded for the farmer's state / season?

Uses the bundled 'Crop Production in India' data (state, season, crop, area). It does NOT change the
ML model; it only adds a real-world check next to each recommendation. "not_recorded" means the
dataset has no entry for that state - it does not prove the crop cannot be grown there.
"""
from functools import lru_cache
import pandas as pd
from app.config import BASE_DIR

CSV = BASE_DIR / "ml" / "datasets" / "crop_production.csv"

# crop names of the recommendation dataset -> names in crop_production.csv (None = not in that file)
CROP_MAP = {
    "rice": ["Rice", "Paddy"], "maize": ["Maize"], "chickpea": ["Gram"], "kidneybeans": ["Rajmash Kholar", "Bean"],
    "pigeonpeas": ["Arhar/Tur"], "mothbeans": ["Moth"], "mungbean": ["Moong(Green Gram)"], "blackgram": ["Urad", "Blackgram"],
    "lentil": ["Masoor", "Lentil"], "pomegranate": ["Pome Granet"], "banana": ["Banana"], "mango": ["Mango"],
    "grapes": ["Grapes"], "watermelon": ["Water Melon"], "muskmelon": None, "apple": ["Apple"], "orange": ["Orange"],
    "papaya": ["Papaya"], "coconut": ["Coconut"], "cotton": ["Cotton(lint)", "Kapas"], "jute": ["Jute"], "coffee": ["Coffee"],
}

# message templates: index 0 = English, 1 = Hindi, 2 = Telugu
MSG = {
    "in_season": (
        "{crop} is recorded in {state} in the government crop-production data ({years} years), including the {season} season.",
        "{crop} {state} के सरकारी फसल-उत्पादन आंकड़ों में दर्ज है ({years} वर्ष), और {season} सीज़न में भी उगाई जाती है।",
        "{crop} {state}లోని ప్రభుత్వ పంట ఉత్పత్తి డేటాలో నమోదైంది ({years} సంవత్సరాలు), {season} సీజన్‌లో కూడా సాగు చేస్తారు.",
    ),
    "off_season": (
        "{crop} is recorded in {state}, but not for the {season} season (recorded seasons: {seasons}).",
        "{crop} {state} में दर्ज है, लेकिन {season} सीज़न में नहीं (दर्ज सीज़न: {seasons})।",
        "{crop} {state}లో నమోదైంది, కానీ {season} సీజన్‌లో కాదు (నమోదైన సీజన్లు: {seasons}).",
    ),
    "recorded": (
        "{crop} is recorded in {state} in the government crop-production data ({years} years).",
        "{crop} {state} के सरकारी फसल-उत्पादन आंकड़ों में दर्ज है ({years} वर्ष)।",
        "{crop} {state}లోని ప్రభుత్వ పంట ఉత్పత్తి డేటాలో నమోదైంది ({years} సంవత్సరాలు).",
    ),
    "not_recorded": (
        "{crop} has no record for {state} in the government crop-production data. Check with your local Agriculture Officer before choosing it.",
        "{crop} का {state} में सरकारी फसल-उत्पादन आंकड़ों में कोई रिकॉर्ड नहीं है। चुनने से पहले अपने स्थानीय कृषि अधिकारी से पूछें।",
        "{crop}కు {state}లోని ప్రభుత్వ పంట ఉత్పత్తి డేటాలో రికార్డు లేదు. ఎంచుకునే ముందు మీ స్థానిక వ్యవసాయ అధికారిని సంప్రదించండి.",
    ),
}
LANG_IDX = {"en": 0, "hi": 1, "te": 2}


@lru_cache(maxsize=1)
def _data() -> pd.DataFrame:
    if not CSV.exists():
        return pd.DataFrame()
    d = pd.read_csv(CSV, usecols=["State_Name", "Crop_Year", "Season", "Crop", "Area"])
    for c in ("State_Name", "Season", "Crop"):
        d[c] = d[c].astype(str).str.strip().str.lower()
    return d


def check(crop: str, state: str | None, season: str | None) -> dict:
    """Returns {"status": recorded | not_recorded | unknown, "years": n, "seasons": [...], "in_season": bool}."""
    d = _data()
    names = CROP_MAP.get(crop)
    if d.empty or not state or not names:
        return {"status": "unknown"}
    rows = d[(d.State_Name == state.strip().lower()) & (d.Crop.isin([n.lower() for n in names]))]
    if rows.empty:
        return {"status": "not_recorded"}
    seasons = sorted(rows.Season.unique())
    out = {"status": "recorded", "years": int(rows.Crop_Year.nunique()), "seasons": seasons}
    if season:
        s = season.strip().lower()
        out["in_season"] = "whole year" in seasons or any(s in x or x in s for x in seasons)
    return out


def message(crop: str, crop_label: str, state: str | None, season: str | None, lang: str = "en") -> dict | None:
    """Localized one-line regional note for a recommendation, or None when nothing can be said."""
    r = check(crop, state, season)
    if r["status"] == "unknown":
        return None
    if r["status"] == "not_recorded":
        key = "not_recorded"
    elif "in_season" in r:
        key = "in_season" if r["in_season"] else "off_season"
    else:
        key = "recorded"
    text = MSG[key][LANG_IDX.get(lang, 0)].format(
        crop=crop_label[:1].upper() + crop_label[1:], state=state, years=r.get("years", ""), season=(season or "").title(),
        seasons=", ".join(s.title() for s in r.get("seasons", [])))
    return {"status": r["status"], "ok": key in ("in_season", "recorded"), "text": text}
