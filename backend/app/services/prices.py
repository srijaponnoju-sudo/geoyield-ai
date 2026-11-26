"""Mandi (market) prices from Agmarknet, through the free data.gov.in open API.

- Needs a free API key in backend/.env  ->  DATA_GOV_API_KEY=your_key
- If the key is missing, the feed is down, or the crop has no price today, we return None
  and the farmer types the price himself (the app always works this way).
- Prices are Rs per quintal (1 tonne = 10 quintals). Cached for 30 minutes.
"""
import json
import os
import time
import urllib.parse
import urllib.request
from datetime import datetime

RESOURCE_ID = "9ef84268-d588-465a-a308-a864a43d0070"  # Agmarknet daily mandi prices
API_URL = f"https://api.data.gov.in/resource/{RESOURCE_ID}"
TTL_SECONDS = 30 * 60
TIMEOUT = 6
_cache: dict = {}

# crop name used by the yield model -> commodity name(s) used by Agmarknet
# None = not sold through normal mandis (the farmer must type a price)
COMMODITY = {
    "Rice": ["Paddy(Dhan)(Common)", "Rice"], "Paddy": ["Paddy(Dhan)(Common)"], "Maize": ["Maize"],
    "Jowar": ["Jowar(Sorghum)"], "Bajra": ["Bajra(Pearl Millet/Cumbu)"], "Ragi": ["Ragi (Finger Millet)"],
    "Wheat": ["Wheat"], "Barley": ["Barley (Jau)"],
    "Arhar/Tur": ["Arhar (Tur/Red Gram)(Whole)"], "Gram": ["Bengal Gram(Gram)(Whole)"],
    "Moong(Green Gram)": ["Green Gram (Moong)(Whole)"], "Urad": ["Black Gram (Urd Beans)(Whole)"],
    "Masoor": ["Lentil (Masur)(Whole)"],
    "Groundnut": ["Groundnut"], "Soyabean": ["Soyabean"], "Sunflower": ["Sunflower"],
    "Sesamum": ["Sesamum(Sesame,Gingelly,Til)"], "Castor seed": ["Castor Seed"], "Rapeseed &Mustard": ["Mustard"],
    "Dry chillies": ["Dry Chillies"], "Turmeric": ["Turmeric"], "Onion": ["Onion"], "Potato": ["Potato"],
    "Tomato": ["Tomato"], "Brinjal": ["Brinjal"], "Bhindi": ["Bhindi(Ladies Finger)"], "Cabbage": ["Cabbage"],
    "Cauliflower": ["Cauliflower"], "Garlic": ["Garlic"], "Ginger": ["Ginger(Green)"], "Banana": ["Banana"],
    "Mango": ["Mango"], "Papaya": ["Papaya"], "Grapes": ["Grapes"], "Sweet potato": ["Sweet Potato"],
    "Tapioca": ["Tapioca"], "Sugarcane": None,
}


def has_key() -> bool:
    return bool(os.getenv("DATA_GOV_API_KEY", "").strip())


def priced_crops() -> list[str]:
    """Crops we know how to price (live or typed)."""
    return list(COMMODITY)


def _get(params: dict) -> dict:
    url = API_URL + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "GeoYieldAI/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8"))


def _records(commodity: str, state: str) -> list[dict]:
    base = {"api-key": os.getenv("DATA_GOV_API_KEY", "").strip(), "format": "json", "limit": "300",
            "filters[commodity]": commodity}
    for state_filter in ("filters[state.keyword]", "filters[state]"):
        try:
            data = _get({**base, state_filter: state})
        except Exception:
            continue
        recs = data.get("records") or []
        if recs:
            return recs
    return []


def _num(x):
    try:
        v = float(str(x).replace(",", "").strip())
        return v if v > 0 else None
    except Exception:
        return None


def _date(s: str):
    for fmt in ("%d/%m/%Y", "%Y-%m-%d", "%d-%m-%Y"):
        try:
            return datetime.strptime(str(s).strip(), fmt)
        except Exception:
            pass
    return None


def pick_price(records: list[dict], state: str, district: str | None) -> dict | None:
    """From raw Agmarknet rows, average the modal price of the newest day (district first, then state)."""
    st = (state or "").strip().lower()
    di = (district or "").strip().lower()
    rows = [r for r in records if str(r.get("state", "")).strip().lower() == st]
    scope = "state"
    if di:
        dd = [r for r in rows if str(r.get("district", "")).strip().lower() == di]
        if dd:
            rows, scope = dd, "district"
    rows = [r for r in rows if _num(r.get("modal_price")) and _date(r.get("arrival_date"))]
    if not rows:
        return None
    newest = max(_date(r["arrival_date"]) for r in rows)
    today = [r for r in rows if _date(r["arrival_date"]) == newest]
    prices = [_num(r["modal_price"]) for r in today]
    return {"price": round(sum(prices) / len(prices)), "unit": "Rs/quintal", "markets": len(today),
            "date": newest.strftime("%d-%m-%Y"), "scope": scope, "source": "Agmarknet (data.gov.in)",
            "age_days": (datetime.now() - newest).days}


def latest_price(crop: str, state: str, district: str | None = None) -> dict | None:
    """Live price for a crop, or None (no key / not available / feed down)."""
    names = COMMODITY.get(crop)
    if not names or not has_key() or not state:
        return None
    key = (crop, state.strip().lower(), (district or "").strip().lower())
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < TTL_SECONDS:
        return hit[1]
    result = None
    for name in names:
        result = pick_price(_records(name, state), state, district)
        if result:
            break
    if result:  # only cache real answers, so a temporary outage is retried
        _cache[key] = (time.time(), result)
    return result
