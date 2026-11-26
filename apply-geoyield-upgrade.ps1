# ============================================================================
# GeoYield AI - upgrade script (run ONCE from the project root folder)
#   1) Profit mode (yield x price, live mandi price or typed price)
#   2) Government schemes (PM-KISAN, crop insurance, state schemes)
#   3) "Was this right?" feedback button (saves real results)
#   4) WhatsApp / SMS bot in Telugu, Hindi, English (Twilio webhook)
#   5) Live mandi prices from Agmarknet (data.gov.in) with typed-price fallback
# It backs up every file it replaces into a _backup_before_upgrade_* folder,
# writes the new files, then runs the backend tests and the frontend build.
# ============================================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
if (-not (Test-Path (Join-Path $root "backend\app\main.py")) -or -not (Test-Path (Join-Path $root "frontend\src\App.jsx"))) {
    throw "Run this script from the GeoYield project root (the folder that contains 'backend' and 'frontend')."
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backup = Join-Path $root ("_backup_before_upgrade_" + $stamp)

function Save-File([string]$rel, [string]$text) {
    $full = Join-Path $root $rel
    $dir = Split-Path $full -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path $full) {
        $b = Join-Path $backup $rel
        $bd = Split-Path $b -Parent
        if (-not (Test-Path $bd)) { New-Item -ItemType Directory -Path $bd -Force | Out-Null }
        Copy-Item $full $b -Force
    }
    $clean = $text.Replace("`r`n", "`n").TrimEnd() + "`n"
    [System.IO.File]::WriteAllText($full, $clean, $utf8)
    Write-Host ("  wrote " + $rel)
}

Write-Host "== Writing files ==" -ForegroundColor Green
$c = @'
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
'@
Save-File "backend\app\services\prices.py" $c

$c = @'
"""Profit mode: expected income = predicted yield x price, for several crops side by side.

Uses the trained yield model already in the project. Price comes from (1) the farmer, or
(2) live Agmarknet price when a DATA_GOV_API_KEY is set. Costs are optional; without costs
the result is only an INCOME estimate, never called profit.
"""
from app.i18n import M, _ as tr3, norm, t
from app.services import prices, registry, soil_service, yield_service

ACRE_PER_HA = 2.471
LONG_CROPS = {"Sugarcane", "Banana", "Turmeric", "Ginger", "Tapioca", "Papaya", "Mango", "Grapes"}
DATA_LAST_YEAR = 2015

M["profit_estimate"] = tr3(
    "This is an estimate of INCOME (yield x price). Your costs are not included, so it is not profit. Type your cost per {unit} to see net profit.",
    "\u092F\u0939 \u0906\u092F \u0915\u093E \u0905\u0928\u0941\u092E\u093E\u0928 \u0939\u0948 (\u0909\u092A\u091C x \u092D\u093E\u0935)\u0964 \u0906\u092A\u0915\u0940 \u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u092F\u0939 \u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0928\u0939\u0940\u0902 \u0939\u0948\u0964 \u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0926\u0947\u0916\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u092A\u094D\u0930\u0924\u093F {unit} \u0905\u092A\u0928\u0940 \u0932\u093E\u0917\u0924 \u0932\u093F\u0916\u0947\u0902\u0964",
    "\u0C07\u0C26\u0C3F \u0C06\u0C26\u0C3E\u0C2F \u0C05\u0C02\u0C1A\u0C28\u0C3E (\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F x \u0C27\u0C30). \u0C2E\u0C40 \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C07\u0C26\u0C3F \u0C32\u0C3E\u0C2D\u0C02 \u0C15\u0C3E\u0C26\u0C41. \u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 \u0C1A\u0C42\u0C21\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F {unit}\u0C15\u0C41 \u0C2E\u0C40 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F.")
M["profit_net"] = tr3(
    "Net profit = expected income minus the cost you typed. Prices change every day, so check your local mandi before you decide.",
    "\u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E = \u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0906\u092F - \u0906\u092A\u0915\u0940 \u0932\u093F\u0916\u0940 \u0932\u093E\u0917\u0924\u0964 \u092D\u093E\u0935 \u0930\u094B\u091C\u093C \u092C\u0926\u0932\u0924\u0947 \u0939\u0948\u0902, \u0907\u0938\u0932\u093F\u090F \u0928\u093F\u0930\u094D\u0923\u092F \u0938\u0947 \u092A\u0939\u0932\u0947 \u0905\u092A\u0928\u0940 \u0938\u094D\u0925\u093E\u0928\u0940\u092F \u092E\u0902\u0921\u0940 \u092E\u0947\u0902 \u091C\u093E\u0901\u091A\u0947\u0902\u0964",
    "\u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 = \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C06\u0C26\u0C3E\u0C2F\u0C02 - \u0C2E\u0C40\u0C30\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C3F\u0C28 \u0C16\u0C30\u0C4D\u0C1A\u0C41. \u0C27\u0C30\u0C32\u0C41 \u0C30\u0C4B\u0C1C\u0C42 \u0C2E\u0C3E\u0C30\u0C24\u0C3E\u0C2F\u0C3F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C28\u0C3F\u0C30\u0C4D\u0C23\u0C2F\u0C3F\u0C02\u0C1A\u0C47 \u0C2E\u0C41\u0C02\u0C26\u0C41 \u0C2E\u0C40 \u0C38\u0C4D\u0C25\u0C3E\u0C28\u0C3F\u0C15 \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B \u0C1A\u0C42\u0C21\u0C02\u0C21\u0C3F.")
M["profit_costmix"] = tr3(
    "Costs were typed for only some crops, so the list is ranked by income, not by net profit.",
    "\u0932\u093E\u0917\u0924 \u0915\u0947\u0935\u0932 \u0915\u0941\u091B \u092B\u0938\u0932\u094B\u0902 \u0915\u0947 \u0932\u093F\u090F \u0932\u093F\u0916\u0940 \u0917\u0908 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0938\u0942\u091A\u0940 \u0906\u092F \u0915\u0947 \u0905\u0928\u0941\u0938\u093E\u0930 \u0939\u0948, \u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u0947 \u0915\u0947 \u0905\u0928\u0941\u0938\u093E\u0930 \u0928\u0939\u0940\u0902\u0964",
    "\u0C15\u0C4A\u0C28\u0C4D\u0C28\u0C3F \u0C2A\u0C02\u0C1F\u0C32\u0C15\u0C41 \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C36\u0C3E\u0C30\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C1C\u0C3E\u0C2C\u0C3F\u0C24\u0C3E \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C09\u0C02\u0C26\u0C3F, \u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C15\u0C3E\u0C26\u0C41.")
M["profit_long"] = tr3(
    "{crop} takes much longer than one season, so it cannot be compared directly with seasonal crops.",
    "{crop} \u090F\u0915 \u0938\u0940\u091C\u093C\u0928 \u0938\u0947 \u092C\u0939\u0941\u0924 \u0932\u0902\u092C\u0940 \u0905\u0935\u0927\u093F \u0915\u0940 \u092B\u0938\u0932 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0907\u0938\u0915\u0940 \u0938\u0940\u0927\u0940 \u0924\u0941\u0932\u0928\u093E \u092E\u094C\u0938\u092E\u0940 \u092B\u0938\u0932\u094B\u0902 \u0938\u0947 \u0928\u0939\u0940\u0902 \u0939\u094B \u0938\u0915\u0924\u0940\u0964",
    "{crop} \u0C12\u0C15 \u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C15\u0C02\u0C1F\u0C47 \u0C1A\u0C3E\u0C32\u0C3E \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C15\u0C3E\u0C32\u0C02 \u0C2A\u0C02\u0C1F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C2A\u0C02\u0C1F\u0C32\u0C24\u0C4B \u0C28\u0C47\u0C30\u0C41\u0C17\u0C3E \u0C2A\u0C4B\u0C32\u0C4D\u0C1A\u0C32\u0C47\u0C2E\u0C41.")
M["profit_noprice"] = tr3(
    "No price found for {crop}. Type today's mandi price (Rs per quintal) to include it in the ranking.",
    "{crop} \u0915\u093E \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u092E\u093F\u0932\u093E\u0964 \u0907\u0938\u0947 \u0938\u0942\u091A\u0940 \u092E\u0947\u0902 \u091C\u094B\u0921\u093C\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u0906\u091C \u0915\u093E \u092E\u0902\u0921\u0940 \u092D\u093E\u0935 (\u20B9 \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932) \u0932\u093F\u0916\u0947\u0902\u0964",
    "{crop} \u0C27\u0C30 \u0C26\u0C4A\u0C30\u0C15\u0C32\u0C47\u0C26\u0C41. \u0C30\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C3F\u0C02\u0C17\u0C4D\u200C\u0C32\u0C4B \u0C1A\u0C47\u0C30\u0C4D\u0C1A\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C08 \u0C30\u0C4B\u0C1C\u0C41 \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30 (\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9) \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F.")
M["profit_cotton"] = tr3(
    "Cotton is not included: government records give cotton in bales, which the yield model cannot use.",
    "\u0915\u092A\u093E\u0938 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902 \u0939\u0948: \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u092E\u0947\u0902 \u0915\u092A\u093E\u0938 \u0917\u093E\u0901\u0920\u094B\u0902 \u092E\u0947\u0902 \u0939\u0948, \u091C\u093F\u0938\u0947 \u0909\u092A\u091C \u092E\u0949\u0921\u0932 \u0907\u0938\u094D\u0924\u0947\u092E\u093E\u0932 \u0928\u0939\u0940\u0902 \u0915\u0930 \u0938\u0915\u0924\u093E\u0964",
    "\u0C2A\u0C24\u0C4D\u0C24\u0C3F \u0C1A\u0C47\u0C30\u0C4D\u0C1A\u0C32\u0C47\u0C26\u0C41: \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32\u0C4D\u0C32\u0C4B \u0C2A\u0C24\u0C4D\u0C24\u0C3F \u0C2C\u0C47\u0C33\u0C4D\u0C32\u0C32\u0C4B \u0C09\u0C02\u0C26\u0C3F, \u0C26\u0C40\u0C28\u0C4D\u0C28\u0C3F \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C2E\u0C4B\u0C21\u0C32\u0C4D \u0C35\u0C3E\u0C21\u0C32\u0C47\u0C26\u0C41.")
M["profit_olddata"] = tr3(
    "Yields come from government records up to {year}. Newer varieties and better farming can give more, so real yields may be higher.",
    "\u0909\u092A\u091C {year} \u0924\u0915 \u0915\u0947 \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u0938\u0947 \u0939\u0948\u0964 \u0928\u0908 \u0915\u093F\u0938\u094D\u092E\u0947\u0902 \u0914\u0930 \u092C\u0947\u0939\u0924\u0930 \u0916\u0947\u0924\u0940 \u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0909\u092A\u091C \u092E\u093F\u0932 \u0938\u0915\u0924\u0940 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u0905\u0938\u0932\u0940 \u0909\u092A\u091C \u0905\u0927\u093F\u0915 \u0939\u094B \u0938\u0915\u0924\u0940 \u0939\u0948\u0964",
    "\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C41\u0C32\u0C41 {year} \u0C35\u0C30\u0C15\u0C41 \u0C09\u0C28\u0C4D\u0C28 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32 \u0C28\u0C41\u0C02\u0C21\u0C3F. \u0C15\u0C4A\u0C24\u0C4D\u0C24 \u0C30\u0C15\u0C3E\u0C32\u0C41, \u0C2E\u0C46\u0C30\u0C41\u0C17\u0C48\u0C28 \u0C38\u0C3E\u0C17\u0C41\u0C24\u0C4B \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C30\u0C3E\u0C35\u0C1A\u0C4D\u0C1A\u0C41, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C09\u0C02\u0C21\u0C35\u0C1A\u0C4D\u0C1A\u0C41.")
M["unit_acre"] = tr3("acre", "\u090F\u0915\u0921\u093C", "\u0C0E\u0C15\u0C30\u0C3E")
M["unit_hectare"] = tr3("hectare", "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C41")
M["sum_profit"] = tr3("Profit comparison: best income {crop}", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0924\u0941\u0932\u0928\u093E: \u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0906\u092F {crop}", "\u0C32\u0C3E\u0C2D\u0C02 \u0C2A\u0C4B\u0C32\u0C3F\u0C15: \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 {crop}")


def _known_crops() -> set[str]:
    b = registry.yield_model()
    return set((b or {}).get("known_values", {}).get("crop", []))


def addable_crops() -> list[str]:
    known = _known_crops()
    return sorted(c for c in prices.priced_crops() if c in known)


def candidates(state: str, district: str | None, season: str | None, limit: int = 8) -> list[str]:
    """Priced crops that the government data shows are really grown in this district/state and season."""
    rows = soil_service._prod()
    rows = rows[rows.State_Name.str.lower() == state.strip().lower()]
    if district:
        dd = rows[rows.District_Name.str.lower() == district.strip().lower()]
        if not dd.empty:
            rows = dd
    if season:
        ss = rows[rows.Season.str.lower().isin([season.strip().lower(), "whole year"])]
        if not ss.empty:
            rows = ss
    top = rows.groupby("Crop").Area.sum().sort_values(ascending=False)
    ok = set(addable_crops()) - {"Sugarcane"}
    out = [c for c in top.index if c in ok]
    return out[:limit]


def compare(inp: dict) -> dict:
    lang = norm(inp.get("lang"))
    unit = "hectare" if inp.get("area_unit") == "hectare" else "acre"
    area = float(inp["area"])
    area_ha = area if unit == "hectare" else area / ACRE_PER_HA
    state, district, season = inp["state"], inp.get("district"), inp["season"]
    typed = {k: float(v) for k, v in (inp.get("prices") or {}).items() if v not in (None, "") and float(v) > 0}
    crops = inp.get("crops")
    if not crops:  # auto list + any crop the farmer typed a price for
        crops = list(dict.fromkeys(candidates(state, district, season) + [c for c in typed if c in _known_crops()]))
    costs = {k: float(v) for k, v in (inp.get("costs") or {}).items() if v not in (None, "") and float(v) >= 0}
    if not crops:
        return {"model_status": "trained", "rows": [], "notes": [], "error": "no_crops"}
    rows, notes = [], []
    for crop in crops:
        r = yield_service.predict({"state": state, "district": district, "season": season, "crop": crop,
                                   "area_hectares": area_ha, "lang": lang})
        if r.get("model_status") == "unavailable":
            return r
        row = {"crop": crop, "long_duration": crop in LONG_CROPS}
        if "error" in r:
            row["error"] = r["error"]
            rows.append(row)
            continue
        y = r["predicted_yield"]
        row.update(yield_t_per_ha=y, production_tonnes=round(y * area_ha, 2),
                   production_quintals=round(y * area_ha * 10, 1), warnings=r.get("warnings", []))
        price, src, live = None, None, None
        if crop in typed:
            price, src = typed[crop], "typed"
        else:
            live = prices.latest_price(crop, state, district)
            if live:
                price, src = live["price"], "live"
        row.update(price=price, price_source=src, live=live)
        if price:
            row["income"] = round(row["production_quintals"] * price)
            row["income_per_unit"] = round(row["income"] / area)
        if crop in costs:  # cost is typed per acre/hectare, as the farmer chose
            row["cost"] = round(costs[crop] * area)
            if price:
                row["net"] = row["income"] - row["cost"]
        rows.append(row)

    priced = [r for r in rows if r.get("income") is not None]
    all_cost = bool(priced) and all("net" in r for r in priced)
    key = "net" if all_cost else "income"
    priced.sort(key=lambda r: r[key], reverse=True)
    unpriced = [r for r in rows if r.get("income") is None]
    ordered = priced + unpriced
    for i, r in enumerate(priced):
        r["rank"] = i + 1

    if all_cost:
        notes.append(t("profit_net", lang))
    else:
        notes.append(t("profit_estimate", lang, unit=t("unit_" + unit, lang)))
        if any("net" in r for r in priced):
            notes.append(t("profit_costmix", lang))
    for r in ordered:
        if r.get("long_duration"):
            notes.append(t("profit_long", lang, crop=r["crop"]))
        if r.get("income") is None and "error" not in r:
            notes.append(t("profit_noprice", lang, crop=r["crop"]))
    notes.append(t("profit_cotton", lang))
    notes.append(t("profit_olddata", lang, year=DATA_LAST_YEAR))
    return {"model_status": "trained", "rows": ordered, "ranked_by": key if priced else None,
            "best": priced[0]["crop"] if priced else None, "area": area, "area_unit": unit,
            "area_ha": round(area_ha, 3), "live_prices_enabled": prices.has_key(),
            "notes": list(dict.fromkeys(notes)), "disclaimer": t("yield_disclaimer", lang)}
'@
Save-File "backend\app\services\profit_service.py" $c

$c = @'
"""Government schemes a farmer can use. Texts in English / Hindi / Telugu.

IMPORTANT: amounts and rules change. Every answer carries a 'confirm with your Agriculture Officer' note.
State schemes (Telangana / Andhra Pradesh) deliberately avoid fixed amounts where the state changes them often.
Please have the Hindi and Telugu wording checked by a native speaker.
"""
from app.i18n import norm

FOOD_OIL = {"Rice", "Paddy", "Wheat", "Maize", "Jowar", "Bajra", "Ragi", "Barley", "Arhar/Tur", "Gram", "Moong(Green Gram)",
            "Urad", "Masoor", "Horse-gram", "Cowpea(Lobia)", "Groundnut", "Soyabean", "Sunflower", "Sesamum", "Castor seed",
            "Rapeseed &Mustard", "Safflower", "Niger seed", "Linseed", "Small millets", "Korra", "Samai", "Varagu"}
MSP_CROPS = FOOD_OIL | {"Kapas", "Jute & mesta", "Sugarcane"}
IRRIGATION_CROPS = {"Sugarcane", "Banana", "Mango", "Papaya", "Grapes", "Tomato", "Onion", "Potato", "Brinjal", "Bhindi",
                    "Cabbage", "Cauliflower", "Dry chillies", "Turmeric", "Ginger", "Garlic", "Kapas", "Groundnut", "Maize"}

SCHEMES = [
    {"id": "pm_kisan", "kind": "income", "scope": None, "link": "pmkisan.gov.in",
     "alias": ["pm-kisan", "pmkisan", "kisan samman", "\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D"],
     "name": {"en": "PM-KISAN", "hi": "\u092A\u0940\u090F\u092E-\u0915\u093F\u0938\u093E\u0928", "te": "\u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D"},
     "short": {"en": "Rs 6,000 per year to your bank account", "hi": "\u0938\u093E\u0932 \u092E\u0947\u0902 \u20B96,000 \u0938\u0940\u0927\u0947 \u092C\u0948\u0902\u0915 \u0916\u093E\u0924\u0947 \u092E\u0947\u0902", "te": "\u0C0F\u0C21\u0C3E\u0C26\u0C3F\u0C15\u0C3F \u20B96,000 \u0C28\u0C47\u0C30\u0C41\u0C17\u0C3E \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C16\u0C3E\u0C24\u0C3E\u0C32\u0C4B"},
     "benefit": {"en": "Income support of Rs 6,000 per year, paid in three instalments of Rs 2,000 directly to the bank account of eligible landholding farmer families.",
                 "hi": "\u092A\u093E\u0924\u094D\u0930 \u092D\u0942\u092E\u093F\u0927\u093E\u0930\u0915 \u0915\u093F\u0938\u093E\u0928 \u092A\u0930\u093F\u0935\u093E\u0930\u094B\u0902 \u0915\u0947 \u092C\u0948\u0902\u0915 \u0916\u093E\u0924\u0947 \u092E\u0947\u0902 \u0938\u0940\u0927\u0947 \u0938\u093E\u0932 \u092E\u0947\u0902 \u20B96,000, \u0924\u0940\u0928 \u0915\u093F\u0938\u094D\u0924\u094B\u0902 (\u20B92,000 \u092A\u094D\u0930\u0924\u093F \u0915\u093F\u0938\u094D\u0924) \u092E\u0947\u0902\u0964",
                 "te": "\u0C05\u0C30\u0C4D\u0C39\u0C41\u0C32\u0C48\u0C28 \u0C2D\u0C42\u0C2E\u0C3F \u0C15\u0C32\u0C3F\u0C17\u0C3F\u0C28 \u0C30\u0C48\u0C24\u0C41 \u0C15\u0C41\u0C1F\u0C41\u0C02\u0C2C\u0C3E\u0C32 \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C16\u0C3E\u0C24\u0C3E\u0C32\u0C4B \u0C28\u0C47\u0C30\u0C41\u0C17\u0C3E \u0C0F\u0C21\u0C3E\u0C26\u0C3F\u0C15\u0C3F \u20B96,000, \u0C2E\u0C42\u0C21\u0C41 \u0C35\u0C3F\u0C21\u0C24\u0C32\u0C4D\u0C32\u0C4B (\u0C12\u0C15\u0C4D\u0C15\u0C4B \u0C35\u0C3F\u0C21\u0C24\u0C15\u0C41 \u20B92,000)."},
     "how": {"en": "Register at pmkisan.gov.in or at your Common Service Centre (CSC) / Agriculture Office. Keep Aadhaar, bank passbook and land records ready and complete e-KYC.",
             "hi": "pmkisan.gov.in \u092A\u0930 \u092F\u093E \u0905\u092A\u0928\u0947 \u0915\u0949\u092E\u0928 \u0938\u0930\u094D\u0935\u093F\u0938 \u0938\u0947\u0902\u091F\u0930 (CSC) / \u0915\u0943\u0937\u093F \u0915\u093E\u0930\u094D\u092F\u093E\u0932\u092F \u092E\u0947\u0902 \u092A\u0902\u091C\u0940\u0915\u0930\u0923 \u0915\u0930\u0947\u0902\u0964 \u0906\u0927\u093E\u0930, \u092C\u0948\u0902\u0915 \u092A\u093E\u0938\u092C\u0941\u0915 \u0914\u0930 \u092D\u0942\u092E\u093F \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u0924\u0948\u092F\u093E\u0930 \u0930\u0916\u0947\u0902 \u0914\u0930 e-KYC \u092A\u0942\u0930\u093E \u0915\u0930\u0947\u0902\u0964",
             "te": "pmkisan.gov.in \u0C32\u0C4B \u0C32\u0C47\u0C26\u0C3E \u0C2E\u0C40 \u0C15\u0C3E\u0C2E\u0C28\u0C4D \u0C38\u0C30\u0C4D\u0C35\u0C40\u0C38\u0C4D \u0C38\u0C46\u0C02\u0C1F\u0C30\u0C4D (CSC) / \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C15\u0C3E\u0C30\u0C4D\u0C2F\u0C3E\u0C32\u0C2F\u0C02\u0C32\u0C4B \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F. \u0C06\u0C27\u0C3E\u0C30\u0C4D, \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C2A\u0C3E\u0C38\u0C4D\u200C\u0C2C\u0C41\u0C15\u0C4D, \u0C2D\u0C42\u0C2E\u0C3F \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32\u0C41 \u0C38\u0C3F\u0C26\u0C4D\u0C27\u0C02\u0C17\u0C3E \u0C09\u0C02\u0C1A\u0C3F e-KYC \u0C2A\u0C42\u0C30\u0C4D\u0C24\u0C3F \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F."}},
    {"id": "pmfby", "kind": "insurance", "scope": None, "link": "pmfby.gov.in",
     "alias": ["pmfby", "insurance", "fasal bima", "bima", "\u0C2C\u0C40\u0C2E\u0C3E", "\u092C\u0940\u092E\u093E"],
     "name": {"en": "PM Fasal Bima Yojana (crop insurance)", "hi": "\u092A\u0940\u090F\u092E \u092B\u0938\u0932 \u092C\u0940\u092E\u093E \u092F\u094B\u091C\u0928\u093E", "te": "\u0C2A\u0C40\u0C0E\u0C02 \u0C2B\u0C38\u0C32\u0C4D \u0C2C\u0C40\u0C2E\u0C3E \u0C2F\u0C4B\u0C1C\u0C28 (\u0C2A\u0C02\u0C1F \u0C2C\u0C40\u0C2E\u0C3E)"},
     "short": {"en": "Crop insurance, farmer pays only 1.5% to 5%", "hi": "\u092B\u0938\u0932 \u092C\u0940\u092E\u093E, \u0915\u093F\u0938\u093E\u0928 \u0915\u0947\u0935\u0932 1.5% \u0938\u0947 5% \u0926\u0947\u0924\u093E \u0939\u0948", "te": "\u0C2A\u0C02\u0C1F \u0C2C\u0C40\u0C2E\u0C3E, \u0C30\u0C48\u0C24\u0C41 \u0C15\u0C47\u0C35\u0C32\u0C02 1.5% \u0C28\u0C41\u0C02\u0C21\u0C3F 5% \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C3E\u0C30\u0C41"},
     "benefit": {"en": "Insurance against crop loss from drought, flood, pests, disease and other natural risks. The farmer pays a small premium: 2% for Kharif food crops and oilseeds, 1.5% for Rabi food crops and oilseeds, 5% for commercial and horticultural crops. The government pays the rest.",
                 "hi": "\u0938\u0942\u0916\u093E, \u092C\u093E\u0922\u093C, \u0915\u0940\u091F, \u0930\u094B\u0917 \u0914\u0930 \u0905\u0928\u094D\u092F \u092A\u094D\u0930\u093E\u0915\u0943\u0924\u093F\u0915 \u091C\u094B\u0916\u093F\u092E\u094B\u0902 \u0938\u0947 \u092B\u0938\u0932 \u0928\u0941\u0915\u0938\u093E\u0928 \u0915\u093E \u092C\u0940\u092E\u093E\u0964 \u0915\u093F\u0938\u093E\u0928 \u0925\u094B\u0921\u093C\u093E \u092A\u094D\u0930\u0940\u092E\u093F\u092F\u092E \u0926\u0947\u0924\u093E \u0939\u0948: \u0916\u0930\u0940\u092B \u0916\u093E\u0926\u094D\u092F \u092B\u0938\u0932\u094B\u0902 \u0914\u0930 \u0924\u093F\u0932\u0939\u0928 \u092A\u0930 2%, \u0930\u092C\u0940 \u092A\u0930 1.5%, \u0935\u093E\u0923\u093F\u091C\u094D\u092F\u093F\u0915 \u0914\u0930 \u092C\u093E\u0917\u0935\u093E\u0928\u0940 \u092B\u0938\u0932\u094B\u0902 \u092A\u0930 5%\u0964 \u092C\u093E\u0915\u0940 \u0938\u0930\u0915\u093E\u0930 \u0926\u0947\u0924\u0940 \u0939\u0948\u0964",
                 "te": "\u0C15\u0C30\u0C35\u0C41, \u0C35\u0C30\u0C26, \u0C2A\u0C41\u0C30\u0C41\u0C17\u0C41\u0C32\u0C41, \u0C24\u0C46\u0C17\u0C41\u0C33\u0C4D\u0C32\u0C41, \u0C07\u0C24\u0C30 \u0C2A\u0C4D\u0C30\u0C15\u0C43\u0C24\u0C3F \u0C2A\u0C4D\u0C30\u0C2E\u0C3E\u0C26\u0C3E\u0C32 \u0C35\u0C32\u0C4D\u0C32 \u0C2A\u0C02\u0C1F \u0C28\u0C37\u0C4D\u0C1F\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C2C\u0C40\u0C2E\u0C3E. \u0C30\u0C48\u0C24\u0C41 \u0C24\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C2A\u0C4D\u0C30\u0C40\u0C2E\u0C3F\u0C2F\u0C02 \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C3E\u0C30\u0C41: \u0C16\u0C30\u0C40\u0C2B\u0C4D \u0C06\u0C39\u0C3E\u0C30 \u0C2A\u0C02\u0C1F\u0C32\u0C41, \u0C28\u0C42\u0C28\u0C46\u0C17\u0C3F\u0C02\u0C1C\u0C32\u0C15\u0C41 2%, \u0C30\u0C2C\u0C40\u0C15\u0C3F 1.5%, \u0C35\u0C3E\u0C23\u0C3F\u0C1C\u0C4D\u0C2F, \u0C09\u0C26\u0C4D\u0C2F\u0C3E\u0C28 \u0C2A\u0C02\u0C1F\u0C32\u0C15\u0C41 5%. \u0C2E\u0C3F\u0C17\u0C24\u0C3E\u0C26\u0C3F \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35\u0C02 \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F."},
     "how": {"en": "Enrol through your bank, CSC or pmfby.gov.in before the last date of the season. If crop is damaged, report it within 72 hours (Crop Insurance app or helpline 14447).",
             "hi": "\u0938\u0940\u091C\u093C\u0928 \u0915\u0940 \u0905\u0902\u0924\u093F\u092E \u0924\u093E\u0930\u0940\u0916 \u0938\u0947 \u092A\u0939\u0932\u0947 \u0905\u092A\u0928\u0947 \u092C\u0948\u0902\u0915, CSC \u092F\u093E pmfby.gov.in \u0938\u0947 \u0928\u093E\u092E\u093E\u0902\u0915\u0928 \u0915\u0930\u0947\u0902\u0964 \u092B\u0938\u0932 \u0916\u0930\u093E\u092C \u0939\u094B \u0924\u094B 72 \u0918\u0902\u091F\u0947 \u092E\u0947\u0902 \u092C\u0924\u093E\u090F\u0901 (\u0915\u094D\u0930\u0949\u092A \u0907\u0902\u0936\u094D\u092F\u094B\u0930\u0947\u0902\u0938 \u0910\u092A \u092F\u093E \u0939\u0947\u0932\u094D\u092A\u0932\u093E\u0907\u0928 14447)\u0964",
             "te": "\u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C1A\u0C3F\u0C35\u0C30\u0C3F \u0C24\u0C47\u0C26\u0C40 \u0C32\u0C4B\u0C2A\u0C41 \u0C2E\u0C40 \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41, CSC \u0C32\u0C47\u0C26\u0C3E pmfby.gov.in \u0C26\u0C4D\u0C35\u0C3E\u0C30\u0C3E \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F. \u0C2A\u0C02\u0C1F \u0C26\u0C46\u0C2C\u0C4D\u0C2C\u0C24\u0C3F\u0C02\u0C1F\u0C47 72 \u0C17\u0C02\u0C1F\u0C32\u0C4D\u0C32\u0C4B \u0C24\u0C46\u0C32\u0C3F\u0C2F\u0C1C\u0C47\u0C2F\u0C02\u0C21\u0C3F (\u0C15\u0C4D\u0C30\u0C3E\u0C2A\u0C4D \u0C07\u0C28\u0C4D\u0C38\u0C42\u0C30\u0C46\u0C28\u0C4D\u0C38\u0C4D \u0C2F\u0C3E\u0C2A\u0C4D \u0C32\u0C47\u0C26\u0C3E \u0C39\u0C46\u0C32\u0C4D\u0C2A\u0C4D\u200C\u0C32\u0C48\u0C28\u0C4D 14447)."}},
    {"id": "kcc", "kind": "credit", "scope": None, "link": "your bank / cooperative society",
     "alias": ["kcc", "kisan credit", "loan", "\u0C30\u0C41\u0C23\u0C02", "\u090B\u0923", "\u0C15\u0C4D\u0C30\u0C46\u0C21\u0C3F\u0C1F\u0C4D"],
     "name": {"en": "Kisan Credit Card (KCC)", "hi": "\u0915\u093F\u0938\u093E\u0928 \u0915\u094D\u0930\u0947\u0921\u093F\u091F \u0915\u093E\u0930\u094D\u0921 (KCC)", "te": "\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D \u0C15\u0C4D\u0C30\u0C46\u0C21\u0C3F\u0C1F\u0C4D \u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C4D (KCC)"},
     "short": {"en": "Low-interest farm loan, about 4% if repaid on time", "hi": "\u0915\u092E \u092C\u094D\u092F\u093E\u091C \u0915\u093E \u0916\u0947\u0924\u0940 \u090B\u0923, \u0938\u092E\u092F \u092A\u0930 \u091A\u0941\u0915\u093E\u0928\u0947 \u092A\u0930 \u0932\u0917\u092D\u0917 4%", "te": "\u0C24\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C35\u0C21\u0C4D\u0C21\u0C40 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C30\u0C41\u0C23\u0C02, \u0C38\u0C2E\u0C2F\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C47 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 4%"},
     "benefit": {"en": "Short-term farm loan at low interest: about 7% a year, and about 4% if you repay on time (loans up to Rs 3 lakh, with government interest support). Limits and rules can change.",
                 "hi": "\u0915\u092E \u092C\u094D\u092F\u093E\u091C \u092A\u0930 \u0905\u0932\u094D\u092A\u0915\u093E\u0932\u093F\u0915 \u0916\u0947\u0924\u0940 \u090B\u0923: \u0932\u0917\u092D\u0917 7% \u0938\u093E\u0932\u093E\u0928\u093E, \u0914\u0930 \u0938\u092E\u092F \u092A\u0930 \u091A\u0941\u0915\u093E\u0928\u0947 \u092A\u0930 \u0932\u0917\u092D\u0917 4% (\u20B93 \u0932\u093E\u0916 \u0924\u0915, \u0938\u0930\u0915\u093E\u0930\u0940 \u092C\u094D\u092F\u093E\u091C \u0938\u0939\u093E\u092F\u0924\u093E \u0915\u0947 \u0938\u093E\u0925)\u0964 \u0938\u0940\u092E\u093E \u0914\u0930 \u0928\u093F\u092F\u092E \u092C\u0926\u0932 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902\u0964",
                 "te": "\u0C24\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C35\u0C21\u0C4D\u0C21\u0C40\u0C24\u0C4B \u0C38\u0C4D\u0C35\u0C32\u0C4D\u0C2A\u0C15\u0C3E\u0C32\u0C3F\u0C15 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C30\u0C41\u0C23\u0C02: \u0C0F\u0C21\u0C3E\u0C26\u0C3F\u0C15\u0C3F \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 7%, \u0C38\u0C2E\u0C2F\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C47 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 4% (\u20B93 \u0C32\u0C15\u0C4D\u0C37\u0C32 \u0C35\u0C30\u0C15\u0C41, \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C35\u0C21\u0C4D\u0C21\u0C40 \u0C38\u0C3E\u0C2F\u0C02\u0C24\u0C4B). \u0C2A\u0C30\u0C3F\u0C2E\u0C3F\u0C24\u0C41\u0C32\u0C41, \u0C28\u0C3F\u0C2F\u0C2E\u0C3E\u0C32\u0C41 \u0C2E\u0C3E\u0C30\u0C35\u0C1A\u0C4D\u0C1A\u0C41."},
     "how": {"en": "Apply at any bank or cooperative society with land record, Aadhaar and photographs.",
             "hi": "\u092D\u0942\u092E\u093F \u0930\u093F\u0915\u0949\u0930\u094D\u0921, \u0906\u0927\u093E\u0930 \u0914\u0930 \u092B\u094B\u091F\u094B \u0915\u0947 \u0938\u093E\u0925 \u0915\u093F\u0938\u0940 \u092D\u0940 \u092C\u0948\u0902\u0915 \u092F\u093E \u0938\u0939\u0915\u093E\u0930\u0940 \u0938\u092E\u093F\u0924\u093F \u092E\u0947\u0902 \u0906\u0935\u0947\u0926\u0928 \u0915\u0930\u0947\u0902\u0964",
             "te": "\u0C2D\u0C42\u0C2E\u0C3F \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41, \u0C06\u0C27\u0C3E\u0C30\u0C4D, \u0C2B\u0C4B\u0C1F\u0C4B\u0C32\u0C24\u0C4B \u0C0F\u0C26\u0C48\u0C28\u0C3E \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C32\u0C47\u0C26\u0C3E \u0C38\u0C39\u0C15\u0C3E\u0C30 \u0C38\u0C02\u0C18\u0C02\u0C32\u0C4B \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F."}},
    {"id": "soil_health", "kind": "soil", "scope": None, "link": "soilhealth.dac.gov.in",
     "alias": ["soil", "soil health", "\u0C2E\u0C1F\u0C4D\u0C1F\u0C3F", "\u0C28\u0C47\u0C32", "\u092E\u093F\u091F\u094D\u091F\u0940"],
     "name": {"en": "Soil Health Card", "hi": "\u0938\u0949\u092F\u0932 \u0939\u0947\u0932\u094D\u0925 \u0915\u093E\u0930\u094D\u0921", "te": "\u0C38\u0C3E\u0C2F\u0C3F\u0C32\u0C4D \u0C39\u0C46\u0C32\u0C4D\u0C24\u0C4D \u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C4D"},
     "short": {"en": "Free soil test and fertilizer advice", "hi": "\u092E\u0941\u092B\u093C\u094D\u0924 \u092E\u093F\u091F\u094D\u091F\u0940 \u091C\u093E\u0901\u091A \u0914\u0930 \u0909\u0930\u094D\u0935\u0930\u0915 \u0938\u0932\u093E\u0939", "te": "\u0C09\u0C1A\u0C3F\u0C24 \u0C28\u0C47\u0C32 \u0C2A\u0C30\u0C40\u0C15\u0C4D\u0C37, \u0C0E\u0C30\u0C41\u0C35\u0C41\u0C32 \u0C38\u0C32\u0C39\u0C3E"},
     "benefit": {"en": "Free soil test and a card that tells you how much fertilizer each crop needs. It helps you spend less on fertilizer.",
                 "hi": "\u092E\u0941\u092B\u093C\u094D\u0924 \u092E\u093F\u091F\u094D\u091F\u0940 \u091C\u093E\u0901\u091A \u0914\u0930 \u090F\u0915 \u0915\u093E\u0930\u094D\u0921 \u091C\u094B \u092C\u0924\u093E\u0924\u093E \u0939\u0948 \u0915\u093F \u0939\u0930 \u092B\u0938\u0932 \u0915\u094B \u0915\u093F\u0924\u0928\u093E \u0909\u0930\u094D\u0935\u0930\u0915 \u091A\u093E\u0939\u093F\u090F\u0964 \u0907\u0938\u0938\u0947 \u0909\u0930\u094D\u0935\u0930\u0915 \u092A\u0930 \u0916\u0930\u094D\u091A \u0915\u092E \u0939\u094B\u0924\u093E \u0939\u0948\u0964",
                 "te": "\u0C09\u0C1A\u0C3F\u0C24 \u0C28\u0C47\u0C32 \u0C2A\u0C30\u0C40\u0C15\u0C4D\u0C37, \u0C2A\u0C4D\u0C30\u0C24\u0C3F \u0C2A\u0C02\u0C1F\u0C15\u0C41 \u0C0E\u0C02\u0C24 \u0C0E\u0C30\u0C41\u0C35\u0C41 \u0C15\u0C3E\u0C35\u0C3E\u0C32\u0C4B \u0C1A\u0C46\u0C2A\u0C4D\u0C2A\u0C47 \u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41. \u0C0E\u0C30\u0C41\u0C35\u0C41\u0C32 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C24\u0C17\u0C4D\u0C17\u0C41\u0C24\u0C41\u0C02\u0C26\u0C3F."},
     "how": {"en": "Ask your Agriculture Officer, KVK or nearest soil testing lab to test your soil.",
             "hi": "\u0905\u092A\u0928\u0947 \u0915\u0943\u0937\u093F \u0905\u0927\u093F\u0915\u093E\u0930\u0940, KVK \u092F\u093E \u0928\u091C\u093C\u0926\u0940\u0915\u0940 \u092E\u093F\u091F\u094D\u091F\u0940 \u091C\u093E\u0901\u091A \u092A\u094D\u0930\u092F\u094B\u0917\u0936\u093E\u0932\u093E \u0938\u0947 \u092E\u093F\u091F\u094D\u091F\u0940 \u0915\u0940 \u091C\u093E\u0901\u091A \u0915\u0930\u0935\u093E\u090F\u0901\u0964",
             "te": "\u0C2E\u0C40 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C05\u0C27\u0C3F\u0C15\u0C3E\u0C30\u0C3F, KVK \u0C32\u0C47\u0C26\u0C3E \u0C26\u0C17\u0C4D\u0C17\u0C30\u0C3F \u0C28\u0C47\u0C32 \u0C2A\u0C30\u0C40\u0C15\u0C4D\u0C37 \u0C32\u0C4D\u0C2F\u0C3E\u0C2C\u0C4D\u200C\u0C28\u0C41 \u0C2E\u0C40 \u0C28\u0C47\u0C32 \u0C2A\u0C30\u0C40\u0C15\u0C4D\u0C37\u0C3F\u0C02\u0C1A\u0C2E\u0C28\u0C3F \u0C05\u0C21\u0C17\u0C02\u0C21\u0C3F."}},
    {"id": "micro_irrigation", "kind": "irrigation", "scope": None, "link": "your Horticulture / Agriculture department",
     "alias": ["drip", "sprinkler", "irrigation", "\u0C2C\u0C3F\u0C02\u0C26\u0C41", "\u0C21\u0C4D\u0C30\u0C3F\u0C2A\u0C4D", "\u0921\u094D\u0930\u093F\u092A", "\u0938\u093F\u0902\u091A\u093E\u0908"],
     "name": {"en": "Drip and sprinkler subsidy (PMKSY - Per Drop More Crop)", "hi": "\u0921\u094D\u0930\u093F\u092A \u0914\u0930 \u0938\u094D\u092A\u094D\u0930\u093F\u0902\u0915\u0932\u0930 \u0938\u092C\u094D\u0938\u093F\u0921\u0940 (PMKSY)", "te": "\u0C21\u0C4D\u0C30\u0C3F\u0C2A\u0C4D, \u0C38\u0C4D\u0C2A\u0C4D\u0C30\u0C3F\u0C02\u0C15\u0C4D\u0C32\u0C30\u0C4D \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40 (PMKSY)"},
     "short": {"en": "Subsidy on drip and sprinkler, saves water", "hi": "\u0921\u094D\u0930\u093F\u092A \u0914\u0930 \u0938\u094D\u092A\u094D\u0930\u093F\u0902\u0915\u0932\u0930 \u092A\u0930 \u0938\u092C\u094D\u0938\u093F\u0921\u0940, \u092A\u093E\u0928\u0940 \u092C\u091A\u0924", "te": "\u0C21\u0C4D\u0C30\u0C3F\u0C2A\u0C4D, \u0C38\u0C4D\u0C2A\u0C4D\u0C30\u0C3F\u0C02\u0C15\u0C4D\u0C32\u0C30\u0C4D\u200C\u0C15\u0C41 \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40, \u0C28\u0C40\u0C1F\u0C3F \u0C06\u0C26\u0C3E"},
     "benefit": {"en": "Subsidy on drip and sprinkler irrigation: about 55% for small and marginal farmers and 45% for other farmers (states may add more). Saves water and can raise yield.",
                 "hi": "\u0921\u094D\u0930\u093F\u092A \u0914\u0930 \u0938\u094D\u092A\u094D\u0930\u093F\u0902\u0915\u0932\u0930 \u092A\u0930 \u0938\u092C\u094D\u0938\u093F\u0921\u0940: \u091B\u094B\u091F\u0947 \u0914\u0930 \u0938\u0940\u092E\u093E\u0902\u0924 \u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u094B \u0932\u0917\u092D\u0917 55% \u0914\u0930 \u0905\u0928\u094D\u092F \u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u094B 45% (\u0930\u093E\u091C\u094D\u092F \u0914\u0930 \u091C\u094B\u0921\u093C \u0938\u0915\u0924\u0947 \u0939\u0948\u0902)\u0964 \u092A\u093E\u0928\u0940 \u092C\u091A\u0924\u093E \u0939\u0948 \u0914\u0930 \u0909\u092A\u091C \u092C\u0922\u093C \u0938\u0915\u0924\u0940 \u0939\u0948\u0964",
                 "te": "\u0C21\u0C4D\u0C30\u0C3F\u0C2A\u0C4D, \u0C38\u0C4D\u0C2A\u0C4D\u0C30\u0C3F\u0C02\u0C15\u0C4D\u0C32\u0C30\u0C4D \u0C38\u0C47\u0C26\u0C4D\u0C2F\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40: \u0C1A\u0C3F\u0C28\u0C4D\u0C28, \u0C38\u0C28\u0C4D\u0C28\u0C15\u0C3E\u0C30\u0C41 \u0C30\u0C48\u0C24\u0C41\u0C32\u0C15\u0C41 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 55%, \u0C07\u0C24\u0C30\u0C41\u0C32\u0C15\u0C41 45% (\u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C3E\u0C32\u0C41 \u0C07\u0C02\u0C15\u0C3E \u0C1C\u0C4B\u0C21\u0C3F\u0C02\u0C1A\u0C35\u0C1A\u0C4D\u0C1A\u0C41). \u0C28\u0C40\u0C30\u0C41 \u0C06\u0C26\u0C3E \u0C05\u0C35\u0C41\u0C24\u0C41\u0C02\u0C26\u0C3F, \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C2A\u0C46\u0C30\u0C17\u0C35\u0C1A\u0C4D\u0C1A\u0C41."},
     "how": {"en": "Apply through your district Horticulture or Agriculture department.",
             "hi": "\u0905\u092A\u0928\u0947 \u091C\u093C\u093F\u0932\u0947 \u0915\u0947 \u092C\u093E\u0917\u0935\u093E\u0928\u0940 \u092F\u093E \u0915\u0943\u0937\u093F \u0935\u093F\u092D\u093E\u0917 \u0938\u0947 \u0906\u0935\u0947\u0926\u0928 \u0915\u0930\u0947\u0902\u0964",
             "te": "\u0C2E\u0C40 \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E \u0C09\u0C26\u0C4D\u0C2F\u0C3E\u0C28 \u0C32\u0C47\u0C26\u0C3E \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C36\u0C3E\u0C16 \u0C26\u0C4D\u0C35\u0C3E\u0C30\u0C3E \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F."}},
    {"id": "pm_kusum", "kind": "energy", "scope": None, "link": "pmkusum.mnre.gov.in",
     "alias": ["kusum", "solar", "pump", "\u0C38\u0C4B\u0C32\u0C3E\u0C30\u0C4D", "\u0938\u094B\u0932\u0930"],
     "name": {"en": "PM-KUSUM (solar pumps)", "hi": "\u092A\u0940\u090F\u092E-\u0915\u0941\u0938\u0941\u092E (\u0938\u094B\u0932\u0930 \u092A\u0902\u092A)", "te": "\u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C41\u0C38\u0C41\u0C2E\u0C4D (\u0C38\u0C4B\u0C32\u0C3E\u0C30\u0C4D \u0C2A\u0C02\u0C2A\u0C41\u0C32\u0C41)"},
     "short": {"en": "Subsidy on solar pumps for the farm", "hi": "\u0916\u0947\u0924 \u0915\u0947 \u0932\u093F\u090F \u0938\u094B\u0932\u0930 \u092A\u0902\u092A \u092A\u0930 \u0938\u092C\u094D\u0938\u093F\u0921\u0940", "te": "\u0C2A\u0C4A\u0C32\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C38\u0C4B\u0C32\u0C3E\u0C30\u0C4D \u0C2A\u0C02\u0C2A\u0C41\u0C2A\u0C48 \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40"},
     "benefit": {"en": "Subsidy on solar water pumps so you can save on diesel and electricity. The subsidy share depends on the component and your state.",
                 "hi": "\u0938\u094B\u0932\u0930 \u092A\u093E\u0928\u0940 \u092A\u0902\u092A \u092A\u0930 \u0938\u092C\u094D\u0938\u093F\u0921\u0940, \u091C\u093F\u0938\u0938\u0947 \u0921\u0940\u091C\u093C\u0932 \u0914\u0930 \u092C\u093F\u091C\u0932\u0940 \u0915\u0940 \u092C\u091A\u0924 \u0939\u094B\u0964 \u0938\u092C\u094D\u0938\u093F\u0921\u0940 \u0915\u093E \u0939\u093F\u0938\u094D\u0938\u093E \u092F\u094B\u091C\u0928\u093E \u0915\u0947 \u092D\u093E\u0917 \u0914\u0930 \u0906\u092A\u0915\u0947 \u0930\u093E\u091C\u094D\u092F \u092A\u0930 \u0928\u093F\u0930\u094D\u092D\u0930 \u0939\u0948\u0964",
                 "te": "\u0C38\u0C4B\u0C32\u0C3E\u0C30\u0C4D \u0C28\u0C40\u0C1F\u0C3F \u0C2A\u0C02\u0C2A\u0C41\u0C32\u0C2A\u0C48 \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40, \u0C21\u0C40\u0C1C\u0C3F\u0C32\u0C4D, \u0C15\u0C30\u0C46\u0C02\u0C1F\u0C41 \u0C16\u0C30\u0C4D\u0C1A\u0C41 \u0C06\u0C26\u0C3E. \u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40 \u0C35\u0C3E\u0C1F\u0C3E \u0C2A\u0C25\u0C15\u0C02 \u0C2D\u0C3E\u0C17\u0C02, \u0C2E\u0C40 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C02\u0C2A\u0C48 \u0C06\u0C27\u0C3E\u0C30\u0C2A\u0C21\u0C3F \u0C09\u0C02\u0C1F\u0C41\u0C02\u0C26\u0C3F."},
     "how": {"en": "Apply through your state renewable energy agency or pmkusum.mnre.gov.in. Details differ by state.",
             "hi": "\u0905\u092A\u0928\u0947 \u0930\u093E\u091C\u094D\u092F \u0915\u0940 \u0928\u0935\u0940\u0915\u0930\u0923\u0940\u092F \u090A\u0930\u094D\u091C\u093E \u090F\u091C\u0947\u0902\u0938\u0940 \u092F\u093E pmkusum.mnre.gov.in \u0938\u0947 \u0906\u0935\u0947\u0926\u0928 \u0915\u0930\u0947\u0902\u0964 \u0935\u093F\u0935\u0930\u0923 \u0930\u093E\u091C\u094D\u092F \u0915\u0947 \u0905\u0928\u0941\u0938\u093E\u0930 \u0905\u0932\u0917 \u0939\u0948\u0902\u0964",
             "te": "\u0C2E\u0C40 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C2A\u0C41\u0C28\u0C30\u0C41\u0C24\u0C4D\u0C2A\u0C3E\u0C26\u0C15 \u0C07\u0C02\u0C27\u0C28 \u0C38\u0C02\u0C38\u0C4D\u0C25 \u0C32\u0C47\u0C26\u0C3E pmkusum.mnre.gov.in \u0C26\u0C4D\u0C35\u0C3E\u0C30\u0C3E \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C2F\u0C02\u0C21\u0C3F. \u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C3E\u0C28\u0C4D\u0C28\u0C3F \u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C2E\u0C3E\u0C30\u0C24\u0C3E\u0C2F\u0C3F."}},
    {"id": "enam", "kind": "market", "scope": None, "link": "enam.gov.in",
     "alias": ["enam", "e-nam", "mandi", "market", "\u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D", "\u0C2E\u0C02\u0C21\u0C3F"],
     "name": {"en": "eNAM (online mandi)", "hi": "\u0908-\u0928\u093E\u092E (\u0911\u0928\u0932\u093E\u0907\u0928 \u092E\u0902\u0921\u0940)", "te": "\u0C08-\u0C28\u0C3E\u0C2E\u0C4D (\u0C06\u0C28\u0C4D\u200C\u0C32\u0C48\u0C28\u0C4D \u0C2E\u0C02\u0C21\u0C3F)"},
     "short": {"en": "Sell to buyers across mandis online", "hi": "\u0911\u0928\u0932\u093E\u0907\u0928 \u0915\u0908 \u092E\u0902\u0921\u093F\u092F\u094B\u0902 \u0915\u0947 \u0916\u0930\u0940\u0926\u093E\u0930\u094B\u0902 \u0915\u094B \u092C\u0947\u091A\u0947\u0902", "te": "\u0C06\u0C28\u0C4D\u200C\u0C32\u0C48\u0C28\u0C4D\u200C\u0C32\u0C4B \u0C05\u0C28\u0C47\u0C15 \u0C2E\u0C02\u0C21\u0C40\u0C32 \u0C15\u0C4A\u0C28\u0C41\u0C17\u0C4B\u0C32\u0C41\u0C26\u0C3E\u0C30\u0C41\u0C32\u0C15\u0C41 \u0C05\u0C2E\u0C4D\u0C2E\u0C02\u0C21\u0C3F"},
     "benefit": {"en": "Online trading platform that connects mandis, so you can sell to buyers in many markets and get paid directly in your bank account.",
                 "hi": "\u0911\u0928\u0932\u093E\u0907\u0928 \u091F\u094D\u0930\u0947\u0921\u093F\u0902\u0917 \u092A\u094D\u0932\u0947\u091F\u092B\u093C\u0949\u0930\u094D\u092E \u091C\u094B \u092E\u0902\u0921\u093F\u092F\u094B\u0902 \u0915\u094B \u091C\u094B\u0921\u093C\u0924\u093E \u0939\u0948; \u0906\u092A \u0915\u0908 \u092C\u093E\u091C\u093C\u093E\u0930\u094B\u0902 \u0915\u0947 \u0916\u0930\u0940\u0926\u093E\u0930\u094B\u0902 \u0915\u094B \u092C\u0947\u091A \u0938\u0915\u0924\u0947 \u0939\u0948\u0902 \u0914\u0930 \u092A\u0948\u0938\u093E \u0938\u0940\u0927\u0947 \u092C\u0948\u0902\u0915 \u0916\u093E\u0924\u0947 \u092E\u0947\u0902 \u092A\u093E\u0924\u0947 \u0939\u0948\u0902\u0964",
                 "te": "\u0C2E\u0C02\u0C21\u0C40\u0C32\u0C28\u0C41 \u0C15\u0C32\u0C3F\u0C2A\u0C47 \u0C06\u0C28\u0C4D\u200C\u0C32\u0C48\u0C28\u0C4D \u0C1F\u0C4D\u0C30\u0C47\u0C21\u0C3F\u0C02\u0C17\u0C4D \u0C35\u0C47\u0C26\u0C3F\u0C15; \u0C05\u0C28\u0C47\u0C15 \u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D\u0C32 \u0C15\u0C4A\u0C28\u0C41\u0C17\u0C4B\u0C32\u0C41\u0C26\u0C3E\u0C30\u0C41\u0C32\u0C15\u0C41 \u0C05\u0C2E\u0C4D\u0C2E\u0C35\u0C1A\u0C4D\u0C1A\u0C41, \u0C21\u0C2C\u0C4D\u0C2C\u0C41 \u0C28\u0C47\u0C30\u0C41\u0C17\u0C3E \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C16\u0C3E\u0C24\u0C3E\u0C32\u0C4B \u0C2A\u0C21\u0C41\u0C24\u0C41\u0C02\u0C26\u0C3F."},
     "how": {"en": "Register at enam.gov.in or at your nearest eNAM mandi with Aadhaar, bank details and mobile number.",
             "hi": "\u0906\u0927\u093E\u0930, \u092C\u0948\u0902\u0915 \u0935\u093F\u0935\u0930\u0923 \u0914\u0930 \u092E\u094B\u092C\u093E\u0907\u0932 \u0928\u0902\u092C\u0930 \u0915\u0947 \u0938\u093E\u0925 enam.gov.in \u092F\u093E \u0928\u091C\u093C\u0926\u0940\u0915\u0940 \u0908-\u0928\u093E\u092E \u092E\u0902\u0921\u0940 \u092E\u0947\u0902 \u092A\u0902\u091C\u0940\u0915\u0930\u0923 \u0915\u0930\u0947\u0902\u0964",
             "te": "\u0C06\u0C27\u0C3E\u0C30\u0C4D, \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C41, \u0C2E\u0C4A\u0C2C\u0C48\u0C32\u0C4D \u0C28\u0C02\u0C2C\u0C30\u0C4D\u200C\u0C24\u0C4B enam.gov.in \u0C32\u0C4B \u0C32\u0C47\u0C26\u0C3E \u0C26\u0C17\u0C4D\u0C17\u0C30\u0C3F \u0C08-\u0C28\u0C3E\u0C2E\u0C4D \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."}},
    {"id": "msp", "kind": "market", "scope": None, "link": "your Agriculture Office / procurement centre",
     "alias": ["msp", "support price", "\u0C2E\u0C26\u0C4D\u0C26\u0C24\u0C41", "\u0938\u092E\u0930\u094D\u0925\u0928"],
     "name": {"en": "Minimum Support Price (MSP)", "hi": "\u0928\u094D\u092F\u0942\u0928\u0924\u092E \u0938\u092E\u0930\u094D\u0925\u0928 \u092E\u0942\u0932\u094D\u092F (MSP)", "te": "\u0C15\u0C28\u0C40\u0C38 \u0C2E\u0C26\u0C4D\u0C26\u0C24\u0C41 \u0C27\u0C30 (MSP)"},
     "short": {"en": "Government buys major crops at a fixed price", "hi": "\u0938\u0930\u0915\u093E\u0930 \u092A\u094D\u0930\u092E\u0941\u0916 \u092B\u0938\u0932\u0947\u0902 \u0924\u092F \u092D\u093E\u0935 \u092A\u0930 \u0916\u0930\u0940\u0926\u0924\u0940 \u0939\u0948", "te": "\u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35\u0C02 \u0C2A\u0C4D\u0C30\u0C27\u0C3E\u0C28 \u0C2A\u0C02\u0C1F\u0C32\u0C28\u0C41 \u0C28\u0C3F\u0C30\u0C4D\u0C23\u0C40\u0C24 \u0C27\u0C30\u0C15\u0C41 \u0C15\u0C4A\u0C02\u0C1F\u0C41\u0C02\u0C26\u0C3F"},
     "benefit": {"en": "The government announces a guaranteed buying price for major crops (paddy, jowar, bajra, maize, pulses, groundnut, sunflower, soybean, cotton, wheat and others). If the market price is lower, you can sell to government agencies at MSP.",
                 "hi": "\u0938\u0930\u0915\u093E\u0930 \u092A\u094D\u0930\u092E\u0941\u0916 \u092B\u0938\u0932\u094B\u0902 (\u0927\u093E\u0928, \u091C\u094D\u0935\u093E\u0930, \u092C\u093E\u091C\u0930\u093E, \u092E\u0915\u094D\u0915\u093E, \u0926\u093E\u0932\u0947\u0902, \u092E\u0942\u0902\u0917\u092B\u0932\u0940, \u0938\u0942\u0930\u091C\u092E\u0941\u0916\u0940, \u0938\u094B\u092F\u093E\u092C\u0940\u0928, \u0915\u092A\u093E\u0938, \u0917\u0947\u0939\u0942\u0901 \u0906\u0926\u093F) \u0915\u093E \u0917\u093E\u0930\u0902\u091F\u0940\u0936\u0941\u0926\u093E \u0916\u0930\u0940\u0926 \u092D\u093E\u0935 \u0918\u094B\u0937\u093F\u0924 \u0915\u0930\u0924\u0940 \u0939\u0948\u0964 \u092C\u093E\u091C\u093C\u093E\u0930 \u092D\u093E\u0935 \u0915\u092E \u0939\u094B \u0924\u094B \u0906\u092A \u0938\u0930\u0915\u093E\u0930\u0940 \u090F\u091C\u0947\u0902\u0938\u093F\u092F\u094B\u0902 \u0915\u094B MSP \u092A\u0930 \u092C\u0947\u091A \u0938\u0915\u0924\u0947 \u0939\u0948\u0902\u0964",
                 "te": "\u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35\u0C02 \u0C2A\u0C4D\u0C30\u0C27\u0C3E\u0C28 \u0C2A\u0C02\u0C1F\u0C32\u0C15\u0C41 (\u0C35\u0C30\u0C3F, \u0C1C\u0C4A\u0C28\u0C4D\u0C28, \u0C38\u0C1C\u0C4D\u0C1C, \u0C2E\u0C4A\u0C15\u0C4D\u0C15\u0C1C\u0C4A\u0C28\u0C4D\u0C28, \u0C2A\u0C2A\u0C4D\u0C2A\u0C41\u0C27\u0C3E\u0C28\u0C4D\u0C2F\u0C3E\u0C32\u0C41, \u0C35\u0C47\u0C30\u0C41\u0C36\u0C28\u0C17, \u0C2A\u0C4A\u0C26\u0C4D\u0C26\u0C41\u0C24\u0C3F\u0C30\u0C41\u0C17\u0C41\u0C21\u0C41, \u0C38\u0C4B\u0C2F\u0C3E\u0C2C\u0C40\u0C28\u0C4D, \u0C2A\u0C24\u0C4D\u0C24\u0C3F, \u0C17\u0C4B\u0C27\u0C41\u0C2E \u0C2E\u0C4A\u0C26\u0C32\u0C48\u0C28\u0C35\u0C3F) \u0C39\u0C3E\u0C2E\u0C40 \u0C15\u0C4A\u0C28\u0C41\u0C17\u0C4B\u0C32\u0C41 \u0C27\u0C30 \u0C2A\u0C4D\u0C30\u0C15\u0C1F\u0C3F\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F. \u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D \u0C27\u0C30 \u0C24\u0C15\u0C4D\u0C15\u0C41\u0C35\u0C17\u0C3E \u0C09\u0C02\u0C1F\u0C47 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C38\u0C02\u0C38\u0C4D\u0C25\u0C32\u0C15\u0C41 MSP \u0C15\u0C3F \u0C05\u0C2E\u0C4D\u0C2E\u0C35\u0C1A\u0C4D\u0C1A\u0C41."},
     "how": {"en": "Register at the nearest procurement centre (PACS / Civil Supplies / FCI / NAFED) before harvest. Ask your Agriculture Office for this season's MSP.",
             "hi": "\u0915\u091F\u093E\u0908 \u0938\u0947 \u092A\u0939\u0932\u0947 \u0928\u091C\u093C\u0926\u0940\u0915\u0940 \u0916\u0930\u0940\u0926 \u0915\u0947\u0902\u0926\u094D\u0930 (PACS / \u0938\u093F\u0935\u093F\u0932 \u0938\u092A\u094D\u0932\u093E\u0908 / FCI / NAFED) \u092E\u0947\u0902 \u092A\u0902\u091C\u0940\u0915\u0930\u0923 \u0915\u0930\u0947\u0902\u0964 \u0907\u0938 \u0938\u0940\u091C\u093C\u0928 \u0915\u093E MSP \u0905\u092A\u0928\u0947 \u0915\u0943\u0937\u093F \u0915\u093E\u0930\u094D\u092F\u093E\u0932\u092F \u0938\u0947 \u092A\u0942\u091B\u0947\u0902\u0964",
             "te": "\u0C15\u0C4B\u0C24\u0C15\u0C41 \u0C2E\u0C41\u0C02\u0C26\u0C41 \u0C26\u0C17\u0C4D\u0C17\u0C30\u0C3F \u0C15\u0C4A\u0C28\u0C41\u0C17\u0C4B\u0C32\u0C41 \u0C15\u0C47\u0C02\u0C26\u0C4D\u0C30\u0C02\u0C32\u0C4B (PACS / \u0C38\u0C3F\u0C35\u0C3F\u0C32\u0C4D \u0C38\u0C2A\u0C4D\u0C32\u0C48\u0C38\u0C4D / FCI / NAFED) \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F. \u0C08 \u0C38\u0C40\u0C1C\u0C28\u0C4D MSP \u0C28\u0C3F \u0C2E\u0C40 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C15\u0C3E\u0C30\u0C4D\u0C2F\u0C3E\u0C32\u0C2F\u0C02\u0C32\u0C4B \u0C05\u0C21\u0C17\u0C02\u0C21\u0C3F."}},
    {"id": "rythu_bharosa", "kind": "state", "scope": ["Telangana"], "link": "your Mandal Agriculture Officer (AEO)",
     "alias": ["rythu", "bharosa", "bandhu", "\u0C30\u0C48\u0C24\u0C41 \u0C2D\u0C30\u0C4B\u0C38\u0C3E", "\u0C30\u0C48\u0C24\u0C41\u0C2C\u0C02\u0C27\u0C41", "\u0C30\u0C48\u0C24\u0C41 \u0C2C\u0C02\u0C27\u0C41"],
     "name": {"en": "Rythu Bharosa / Rythu Bandhu (Telangana)", "hi": "\u0930\u093E\u092F\u0924\u0941 \u092D\u0930\u094B\u0938\u093E / \u0930\u093E\u092F\u0924\u0941 \u092C\u0902\u0927\u0941 (\u0924\u0947\u0932\u0902\u0917\u093E\u0928\u093E)", "te": "\u0C30\u0C48\u0C24\u0C41 \u0C2D\u0C30\u0C4B\u0C38\u0C3E / \u0C30\u0C48\u0C24\u0C41\u0C2C\u0C02\u0C27\u0C41 (\u0C24\u0C46\u0C32\u0C02\u0C17\u0C3E\u0C23)"},
     "short": {"en": "State investment support per acre", "hi": "\u0930\u093E\u091C\u094D\u092F \u0915\u0940 \u092A\u094D\u0930\u0924\u093F \u090F\u0915\u0921\u093C \u0928\u093F\u0935\u0947\u0936 \u0938\u0939\u093E\u092F\u0924\u093E", "te": "\u0C0E\u0C15\u0C30\u0C3E\u0C15\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C2A\u0C46\u0C1F\u0C4D\u0C1F\u0C41\u0C2C\u0C21\u0C3F \u0C38\u0C3E\u0C2F\u0C02"},
     "benefit": {"en": "State investment support paid per acre for farmers' cultivation costs. The amount and rules are decided by the state government, so confirm the current amount.",
                 "hi": "\u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u0940 \u0916\u0947\u0924\u0940 \u0915\u0940 \u0932\u093E\u0917\u0924 \u0915\u0947 \u0932\u093F\u090F \u0930\u093E\u091C\u094D\u092F \u0926\u094D\u0935\u093E\u0930\u093E \u092A\u094D\u0930\u0924\u093F \u090F\u0915\u0921\u093C \u0928\u093F\u0935\u0947\u0936 \u0938\u0939\u093E\u092F\u0924\u093E\u0964 \u0930\u093E\u0936\u093F \u0914\u0930 \u0928\u093F\u092F\u092E \u0930\u093E\u091C\u094D\u092F \u0938\u0930\u0915\u093E\u0930 \u0924\u092F \u0915\u0930\u0924\u0940 \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u092E\u094C\u091C\u0942\u0926\u093E \u0930\u093E\u0936\u093F \u0915\u0940 \u092A\u0941\u0937\u094D\u091F\u093F \u0915\u0930\u0947\u0902\u0964",
                 "te": "\u0C30\u0C48\u0C24\u0C41\u0C32 \u0C38\u0C3E\u0C17\u0C41 \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C15\u0C41 \u0C0E\u0C15\u0C30\u0C3E\u0C15\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C2A\u0C46\u0C1F\u0C4D\u0C1F\u0C41\u0C2C\u0C21\u0C3F \u0C38\u0C3E\u0C2F\u0C02. \u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C02, \u0C28\u0C3F\u0C2F\u0C2E\u0C3E\u0C32\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35\u0C02 \u0C28\u0C3F\u0C30\u0C4D\u0C23\u0C2F\u0C3F\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C2A\u0C4D\u0C30\u0C38\u0C4D\u0C24\u0C41\u0C24 \u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C3E\u0C28\u0C4D\u0C28\u0C3F \u0C28\u0C3F\u0C30\u0C4D\u0C27\u0C3E\u0C30\u0C3F\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."},
     "how": {"en": "Contact your Mandal Agriculture Officer / Rythu Vedika. Keep your pattadar passbook and bank account ready.",
             "hi": "\u0905\u092A\u0928\u0947 \u092E\u0902\u0921\u0932 \u0915\u0943\u0937\u093F \u0905\u0927\u093F\u0915\u093E\u0930\u0940 / \u0930\u093E\u092F\u0924\u0941 \u0935\u0947\u0926\u093F\u0915\u093E \u0938\u0947 \u0938\u0902\u092A\u0930\u094D\u0915 \u0915\u0930\u0947\u0902\u0964 \u092A\u091F\u094D\u091F\u093E\u0926\u093E\u0930 \u092A\u093E\u0938\u092C\u0941\u0915 \u0914\u0930 \u092C\u0948\u0902\u0915 \u0916\u093E\u0924\u093E \u0924\u0948\u092F\u093E\u0930 \u0930\u0916\u0947\u0902\u0964",
             "te": "\u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C32 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C05\u0C27\u0C3F\u0C15\u0C3E\u0C30\u0C3F / \u0C30\u0C48\u0C24\u0C41 \u0C35\u0C47\u0C26\u0C3F\u0C15\u0C28\u0C41 \u0C38\u0C02\u0C2A\u0C4D\u0C30\u0C26\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F. \u0C2A\u0C1F\u0C4D\u0C1F\u0C3E\u0C26\u0C3E\u0C30\u0C41 \u0C2A\u0C3E\u0C38\u0C4D\u200C\u0C2C\u0C41\u0C15\u0C4D, \u0C2C\u0C4D\u0C2F\u0C3E\u0C02\u0C15\u0C41 \u0C16\u0C3E\u0C24\u0C3E \u0C38\u0C3F\u0C26\u0C4D\u0C27\u0C02\u0C17\u0C3E \u0C09\u0C02\u0C1A\u0C02\u0C21\u0C3F."}},
    {"id": "rythu_bima", "kind": "state", "scope": ["Telangana"], "link": "your Mandal Agriculture Officer (AEO)",
     "alias": ["rythu bima", "\u0C30\u0C48\u0C24\u0C41 \u0C2C\u0C40\u0C2E\u0C3E"],
     "name": {"en": "Rythu Bima (Telangana)", "hi": "\u0930\u093E\u092F\u0924\u0941 \u092C\u0940\u092E\u093E (\u0924\u0947\u0932\u0902\u0917\u093E\u0928\u093E)", "te": "\u0C30\u0C48\u0C24\u0C41 \u0C2C\u0C40\u0C2E\u0C3E (\u0C24\u0C46\u0C32\u0C02\u0C17\u0C3E\u0C23)"},
     "short": {"en": "Life insurance for registered farmers", "hi": "\u092A\u0902\u091C\u0940\u0915\u0943\u0924 \u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u093E \u091C\u0940\u0935\u0928 \u092C\u0940\u092E\u093E", "te": "\u0C28\u0C2E\u0C4B\u0C26\u0C48\u0C28 \u0C30\u0C48\u0C24\u0C41\u0C32\u0C15\u0C41 \u0C1C\u0C40\u0C35\u0C3F\u0C24 \u0C2C\u0C40\u0C2E\u0C3E"},
     "benefit": {"en": "Life insurance for registered farmers: if a farmer dies, the family receives the insured amount (about Rs 5 lakh). The state pays the premium. Confirm current rules.",
                 "hi": "\u092A\u0902\u091C\u0940\u0915\u0943\u0924 \u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u093E \u091C\u0940\u0935\u0928 \u092C\u0940\u092E\u093E: \u0915\u093F\u0938\u093E\u0928 \u0915\u0940 \u092E\u0943\u0924\u094D\u092F\u0941 \u092A\u0930 \u092A\u0930\u093F\u0935\u093E\u0930 \u0915\u094B \u092C\u0940\u092E\u093E \u0930\u093E\u0936\u093F (\u0932\u0917\u092D\u0917 \u20B95 \u0932\u093E\u0916) \u092E\u093F\u0932\u0924\u0940 \u0939\u0948\u0964 \u092A\u094D\u0930\u0940\u092E\u093F\u092F\u092E \u0930\u093E\u091C\u094D\u092F \u0926\u0947\u0924\u093E \u0939\u0948\u0964 \u092E\u094C\u091C\u0942\u0926\u093E \u0928\u093F\u092F\u092E \u092A\u0942\u091B \u0932\u0947\u0902\u0964",
                 "te": "\u0C28\u0C2E\u0C4B\u0C26\u0C48\u0C28 \u0C30\u0C48\u0C24\u0C41\u0C32\u0C15\u0C41 \u0C1C\u0C40\u0C35\u0C3F\u0C24 \u0C2C\u0C40\u0C2E\u0C3E: \u0C30\u0C48\u0C24\u0C41 \u0C2E\u0C30\u0C23\u0C3F\u0C38\u0C4D\u0C24\u0C47 \u0C15\u0C41\u0C1F\u0C41\u0C02\u0C2C\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C2C\u0C40\u0C2E\u0C3E \u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C02 (\u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 \u20B95 \u0C32\u0C15\u0C4D\u0C37\u0C32\u0C41) \u0C35\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F. \u0C2A\u0C4D\u0C30\u0C40\u0C2E\u0C3F\u0C2F\u0C02 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C2E\u0C47 \u0C1A\u0C46\u0C32\u0C4D\u0C32\u0C3F\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F. \u0C2A\u0C4D\u0C30\u0C38\u0C4D\u0C24\u0C41\u0C24 \u0C28\u0C3F\u0C2F\u0C2E\u0C3E\u0C32\u0C41 \u0C28\u0C3F\u0C30\u0C4D\u0C27\u0C3E\u0C30\u0C3F\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."},
     "how": {"en": "Register through your Agriculture Extension Officer (AEO) with passbook, Aadhaar and nominee details.",
             "hi": "\u092A\u093E\u0938\u092C\u0941\u0915, \u0906\u0927\u093E\u0930 \u0914\u0930 \u0928\u093E\u092E\u093F\u0928\u0940 \u0935\u093F\u0935\u0930\u0923 \u0915\u0947 \u0938\u093E\u0925 \u0905\u092A\u0928\u0947 \u0915\u0943\u0937\u093F \u0935\u093F\u0938\u094D\u0924\u093E\u0930 \u0905\u0927\u093F\u0915\u093E\u0930\u0940 (AEO) \u0938\u0947 \u092A\u0902\u091C\u0940\u0915\u0930\u0923 \u0915\u0930\u0947\u0902\u0964",
             "te": "\u0C2A\u0C3E\u0C38\u0C4D\u200C\u0C2C\u0C41\u0C15\u0C4D, \u0C06\u0C27\u0C3E\u0C30\u0C4D, \u0C28\u0C3E\u0C2E\u0C3F\u0C28\u0C40 \u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C24\u0C4B \u0C2E\u0C40 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C35\u0C3F\u0C38\u0C4D\u0C24\u0C30\u0C23 \u0C05\u0C27\u0C3F\u0C15\u0C3E\u0C30\u0C3F (AEO) \u0C26\u0C4D\u0C35\u0C3E\u0C30\u0C3E \u0C28\u0C2E\u0C4B\u0C26\u0C41 \u0C1A\u0C47\u0C38\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."}},
    {"id": "annadata", "kind": "state", "scope": ["Andhra Pradesh"], "link": "your Rythu Seva Kendram / Agriculture Office",
     "alias": ["annadata", "sukhibhava", "\u0C05\u0C28\u0C4D\u0C28\u0C26\u0C3E\u0C24"],
     "name": {"en": "Annadata Sukhibhava (Andhra Pradesh)", "hi": "\u0905\u0928\u094D\u0928\u0926\u093E\u0924\u093E \u0938\u0941\u0916\u0940\u092D\u0935 (\u0906\u0902\u0927\u094D\u0930 \u092A\u094D\u0930\u0926\u0947\u0936)", "te": "\u0C05\u0C28\u0C4D\u0C28\u0C26\u0C3E\u0C24 \u0C38\u0C41\u0C16\u0C40\u0C2D\u0C35 (\u0C06\u0C02\u0C27\u0C4D\u0C30\u0C2A\u0C4D\u0C30\u0C26\u0C47\u0C36\u0C4D)"},
     "short": {"en": "State income support, along with PM-KISAN", "hi": "\u0930\u093E\u091C\u094D\u092F \u0915\u0940 \u0906\u092F \u0938\u0939\u093E\u092F\u0924\u093E, \u092A\u0940\u090F\u092E-\u0915\u093F\u0938\u093E\u0928 \u0915\u0947 \u0938\u093E\u0925", "te": "\u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C06\u0C26\u0C3E\u0C2F \u0C38\u0C3E\u0C2F\u0C02, \u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D\u200C\u0C24\u0C4B \u0C15\u0C32\u0C3F\u0C2A\u0C3F"},
     "benefit": {"en": "State income support for farmers, given together with PM-KISAN. The amount and instalments are set by the state, so confirm the current details.",
                 "hi": "\u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u094B \u0930\u093E\u091C\u094D\u092F \u0915\u0940 \u0906\u092F \u0938\u0939\u093E\u092F\u0924\u093E, \u092A\u0940\u090F\u092E-\u0915\u093F\u0938\u093E\u0928 \u0915\u0947 \u0938\u093E\u0925\u0964 \u0930\u093E\u0936\u093F \u0914\u0930 \u0915\u093F\u0938\u094D\u0924\u0947\u0902 \u0930\u093E\u091C\u094D\u092F \u0924\u092F \u0915\u0930\u0924\u093E \u0939\u0948, \u0907\u0938\u0932\u093F\u090F \u092E\u094C\u091C\u0942\u0926\u093E \u0935\u093F\u0935\u0930\u0923 \u0915\u0940 \u092A\u0941\u0937\u094D\u091F\u093F \u0915\u0930\u0947\u0902\u0964",
                 "te": "\u0C30\u0C48\u0C24\u0C41\u0C32\u0C15\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30 \u0C06\u0C26\u0C3E\u0C2F \u0C38\u0C3E\u0C2F\u0C02, \u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D\u200C\u0C24\u0C4B \u0C15\u0C32\u0C3F\u0C2A\u0C3F \u0C07\u0C38\u0C4D\u0C24\u0C3E\u0C30\u0C41. \u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C02, \u0C35\u0C3F\u0C21\u0C24\u0C32\u0C41 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C02 \u0C28\u0C3F\u0C30\u0C4D\u0C23\u0C2F\u0C3F\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F, \u0C15\u0C3E\u0C2C\u0C1F\u0C4D\u0C1F\u0C3F \u0C2A\u0C4D\u0C30\u0C38\u0C4D\u0C24\u0C41\u0C24 \u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C41 \u0C28\u0C3F\u0C30\u0C4D\u0C27\u0C3E\u0C30\u0C3F\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."},
     "how": {"en": "Contact your Rythu Seva Kendram or village Agriculture Assistant.",
             "hi": "\u0905\u092A\u0928\u0947 \u0930\u093E\u092F\u0924\u0941 \u0938\u0947\u0935\u093E \u0915\u0947\u0902\u0926\u094D\u0930 \u092F\u093E \u0917\u094D\u0930\u093E\u092E \u0915\u0943\u0937\u093F \u0938\u0939\u093E\u092F\u0915 \u0938\u0947 \u0938\u0902\u092A\u0930\u094D\u0915 \u0915\u0930\u0947\u0902\u0964",
             "te": "\u0C2E\u0C40 \u0C30\u0C48\u0C24\u0C41 \u0C38\u0C47\u0C35\u0C3E \u0C15\u0C47\u0C02\u0C26\u0C4D\u0C30\u0C02 \u0C32\u0C47\u0C26\u0C3E \u0C17\u0C4D\u0C30\u0C3E\u0C2E \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C38\u0C39\u0C3E\u0C2F\u0C15\u0C41\u0C21\u0C3F\u0C28\u0C3F \u0C38\u0C02\u0C2A\u0C4D\u0C30\u0C26\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F."}},
]

NOTE = {"en": "Amounts and rules change. Always confirm the latest details with your Agriculture Officer or the official website before applying.",
        "hi": "\u0930\u093E\u0936\u093F \u0914\u0930 \u0928\u093F\u092F\u092E \u092C\u0926\u0932\u0924\u0947 \u0930\u0939\u0924\u0947 \u0939\u0948\u0902\u0964 \u0906\u0935\u0947\u0926\u0928 \u0938\u0947 \u092A\u0939\u0932\u0947 \u0905\u092A\u0928\u0947 \u0915\u0943\u0937\u093F \u0905\u0927\u093F\u0915\u093E\u0930\u0940 \u092F\u093E \u0906\u0927\u093F\u0915\u093E\u0930\u093F\u0915 \u0935\u0947\u092C\u0938\u093E\u0907\u091F \u0938\u0947 \u0928\u0935\u0940\u0928\u0924\u092E \u091C\u093E\u0928\u0915\u093E\u0930\u0940 \u0915\u0940 \u092A\u0941\u0937\u094D\u091F\u093F \u0915\u0930\u0947\u0902\u0964",
        "te": "\u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C3E\u0C32\u0C41, \u0C28\u0C3F\u0C2F\u0C2E\u0C3E\u0C32\u0C41 \u0C2E\u0C3E\u0C30\u0C41\u0C24\u0C42 \u0C09\u0C02\u0C1F\u0C3E\u0C2F\u0C3F. \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C38\u0C47 \u0C2E\u0C41\u0C02\u0C26\u0C41 \u0C2E\u0C40 \u0C35\u0C4D\u0C2F\u0C35\u0C38\u0C3E\u0C2F \u0C05\u0C27\u0C3F\u0C15\u0C3E\u0C30\u0C3F \u0C32\u0C47\u0C26\u0C3E \u0C05\u0C27\u0C3F\u0C15\u0C3E\u0C30\u0C3F\u0C15 \u0C35\u0C46\u0C2C\u0C4D\u200C\u0C38\u0C48\u0C1F\u0C4D\u200C\u0C32\u0C4B \u0C24\u0C3E\u0C1C\u0C3E \u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C41 \u0C28\u0C3F\u0C30\u0C4D\u0C27\u0C3E\u0C30\u0C3F\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."}

REL = {
    "pmfby": {"en": "For {crop} the farmer premium is about {rate}.", "hi": "{crop} \u0915\u0947 \u0932\u093F\u090F \u0915\u093F\u0938\u093E\u0928 \u0915\u093E \u092A\u094D\u0930\u0940\u092E\u093F\u092F\u092E \u0932\u0917\u092D\u0917 {rate} \u0939\u0948\u0964", "te": "{crop} \u0C15\u0C41 \u0C30\u0C48\u0C24\u0C41 \u0C2A\u0C4D\u0C30\u0C40\u0C2E\u0C3F\u0C2F\u0C02 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {rate}."},
    "msp": {"en": "A government MSP is announced for {crop}.", "hi": "{crop} \u0915\u0947 \u0932\u093F\u090F \u0938\u0930\u0915\u093E\u0930\u0940 MSP \u0918\u094B\u0937\u093F\u0924 \u0939\u094B\u0924\u093E \u0939\u0948\u0964", "te": "{crop} \u0C15\u0C41 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 MSP \u0C2A\u0C4D\u0C30\u0C15\u0C1F\u0C3F\u0C38\u0C4D\u0C24\u0C3E\u0C30\u0C41."},
    "micro_irrigation": {"en": "Especially useful for {crop}.", "hi": "{crop} \u0915\u0947 \u0932\u093F\u090F \u0935\u093F\u0936\u0947\u0937 \u0930\u0942\u092A \u0938\u0947 \u0909\u092A\u092F\u094B\u0917\u0940\u0964", "te": "{crop} \u0C15\u0C41 \u0C2A\u0C4D\u0C30\u0C24\u0C4D\u0C2F\u0C47\u0C15\u0C02\u0C17\u0C3E \u0C09\u0C2A\u0C2F\u0C4B\u0C17\u0C15\u0C30\u0C02."},
}


def pmfby_rate(crop: str | None, season: str | None) -> str | None:
    if not crop:
        return None
    if crop in FOOD_OIL:
        s = (season or "").strip().lower()
        return "1.5%" if s == "rabi" else "2%" if s == "kharif" else "1.5% - 2%"
    return "5%"


def for_farmer(state: str | None, crop: str | None, season: str | None, lang: str = "en") -> dict:
    lg = norm(lang)
    out = []
    for s in SCHEMES:
        if s["scope"] and (not state or state not in s["scope"]):
            continue
        rel = None
        if s["id"] == "pmfby" and crop:
            rel = REL["pmfby"][lg].format(crop=crop, rate=pmfby_rate(crop, season))
        elif s["id"] == "msp" and crop in MSP_CROPS:
            rel = REL["msp"][lg].format(crop=crop)
        elif s["id"] == "micro_irrigation" and crop in IRRIGATION_CROPS:
            rel = REL["micro_irrigation"][lg].format(crop=crop)
        out.append({"id": s["id"], "kind": s["kind"], "name": s["name"][lg], "short": s["short"][lg],
                    "benefit": s["benefit"][lg], "how": s["how"][lg], "link": s["link"], "relevance": rel,
                    "state_scheme": bool(s["scope"])})
    out.sort(key=lambda x: (x["relevance"] is None, not x["state_scheme"]))
    return {"schemes": out, "note": NOTE[lg]}


def find(text: str, state: str | None, lang: str = "en") -> dict | None:
    """Find one scheme mentioned in a message (used by the chat bot)."""
    low = text.lower()
    lg = norm(lang)
    for s in SCHEMES:
        if s["scope"] and state and state not in s["scope"]:
            continue
        if any(a in low for a in s["alias"]):
            return {"name": s["name"][lg], "benefit": s["benefit"][lg], "how": s["how"][lg]}
    return None
'@
Save-File "backend\app\services\schemes_service.py" $c

$c = @'
"""'Was this right?' feedback. Saves what really happened, so we can measure REAL accuracy later.

Tables are created here (CREATE IF NOT EXISTS), so no change to the existing database code is needed.
One feedback row per (module, history_id): sending again updates the same row.
"""
import csv
import io
import json
from datetime import datetime, timezone

from app.database import db

MODULES = ("yield_prediction", "crop_recommendation", "profit_comparison")

# profit comparisons are saved in history like the other modules
db.TABLES.setdefault("profit_comparison", "profit_comparisons")

SCHEMA = """
CREATE TABLE IF NOT EXISTS profit_comparisons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    farmer_input_id INTEGER REFERENCES farmer_inputs(id),
    result_json TEXT NOT NULL, summary TEXT, model_info TEXT, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module TEXT NOT NULL, history_id INTEGER, correct INTEGER NOT NULL,
    state TEXT, district TEXT, crop TEXT, season TEXT,
    predicted_value REAL, predicted_text TEXT,
    actual_yield REAL, actual_crop TEXT, actual_price REAL, comment TEXT,
    created_at TEXT NOT NULL
);
"""


def ensure_tables() -> None:
    with db.connect() as c:
        c.executescript(SCHEMA)


def _snapshot(module: str, history_id: int | None) -> dict:
    """What the app predicted (and for which farm), read from saved history."""
    if not history_id or module not in db.TABLES:
        return {}
    try:
        with db.connect() as c:
            r = c.execute(f"SELECT h.result_json, f.input_json FROM {db.TABLES[module]} h "
                          f"JOIN farmer_inputs f ON f.id = h.farmer_input_id WHERE h.id = ?", (history_id,)).fetchone()
        if not r:
            return {}
        res, inp = json.loads(r["result_json"]), json.loads(r["input_json"])
    except Exception:
        return {}
    snap = {"state": inp.get("state"), "district": inp.get("district"), "season": inp.get("season"),
            "crop": inp.get("crop")}
    if module == "yield_prediction":
        snap["predicted_value"] = res.get("predicted_yield")
    elif module == "crop_recommendation":
        recs = res.get("recommendations") or []
        snap["predicted_text"] = recs[0]["crop"] if recs else None
        snap["crop"] = snap["predicted_text"]
    elif module == "profit_comparison":
        snap["predicted_text"] = res.get("best")
        snap["crop"] = res.get("best")
    return snap


def submit(module: str, history_id: int | None, correct: bool, actual_yield=None, actual_crop=None,
           actual_price=None, comment=None) -> dict:
    snap = _snapshot(module, history_id)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    vals = (int(correct), snap.get("state"), snap.get("district"), snap.get("crop"), snap.get("season"),
            snap.get("predicted_value"), snap.get("predicted_text"), actual_yield, actual_crop, actual_price,
            (comment or "").strip() or None)
    with db.connect() as c:
        old = c.execute("SELECT id FROM feedback WHERE module=? AND history_id=?", (module, history_id)).fetchone() \
            if history_id else None
        if old:
            c.execute("UPDATE feedback SET correct=?, state=?, district=?, crop=?, season=?, predicted_value=?, "
                      "predicted_text=?, actual_yield=?, actual_crop=?, actual_price=?, comment=?, created_at=? "
                      "WHERE id=?", (*vals, now, old["id"]))
            return {"id": old["id"], "updated": True}
        cur = c.execute("INSERT INTO feedback (module, history_id, correct, state, district, crop, season, "
                        "predicted_value, predicted_text, actual_yield, actual_crop, actual_price, comment, created_at) "
                        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (module, history_id, *vals, now))
        return {"id": cur.lastrowid, "updated": False}


def summary() -> dict:
    by = {}
    with db.connect() as c:
        for m in MODULES:
            n, right = c.execute("SELECT COUNT(*), COALESCE(SUM(correct),0) FROM feedback WHERE module=?", (m,)).fetchone()
            by[m] = {"count": n, "right": int(right), "wrong": n - int(right),
                     "percent_right": round(100 * right / n, 1) if n else None}
        rows = c.execute("SELECT predicted_value, actual_yield FROM feedback WHERE module='yield_prediction' "
                         "AND predicted_value IS NOT NULL AND actual_yield IS NOT NULL AND actual_yield > 0").fetchall()
    yerr = None
    if rows:
        errs = [abs(r["predicted_value"] - r["actual_yield"]) for r in rows]
        pct = [e / r["actual_yield"] * 100 for e, r in zip(errs, rows)]
        yerr = {"count": len(rows), "mae_t_per_ha": round(sum(errs) / len(errs), 3),
                "mean_pct_error": round(sum(pct) / len(pct), 1),
                "within_20_percent": round(100 * sum(1 for p in pct if p <= 20) / len(pct), 1)}
    return {"total": sum(v["count"] for v in by.values()), "by_module": by, "yield_error": yerr}


def export_csv() -> str:
    with db.connect() as c:
        rows = c.execute("SELECT * FROM feedback ORDER BY id").fetchall()
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(rows[0].keys() if rows else ["id", "module", "history_id", "correct"])
    for r in rows:
        w.writerow(list(r))
    return buf.getvalue()
'@
Save-File "backend\app\services\feedback_service.py" $c

$c = @'
"""WhatsApp / SMS bot brain (Telugu, Hindi, English). No smartphone skills needed: the farmer just texts.

Examples the farmer can send:   \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2      (crop, district, acres -> yield)
                                 \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300 (... plus price Rs/quintal -> income)
                                 \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2     (which crop earns most)
                                 \u0C27\u0C30 \u0C35\u0C30\u0C3F             (mandi price)       \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41  (government schemes)
Roman letters work too:          vari nalgonda 2 / schemes / profit nalgonda 2
Works as plain functions, so it can be tested without Twilio. See routes/upgrade.py for the web hooks.
"""
import hashlib
import os
import re
from datetime import datetime, timezone

from app.database import db
from app.services import prices, profit_service, schemes_service, yield_service

ACRE_PER_HA = 2.471
LANG_WORDS = {"english": "en", "en": "en", "\u0C07\u0C02\u0C17\u0C4D\u0C32\u0C40\u0C37\u0C4D": "en", "\u0C05\u0C02\u0C17\u0C4D\u0C32\u0C02": "en",
              "telugu": "te", "te": "te", "\u0C24\u0C46\u0C32\u0C41\u0C17\u0C41": "te",
              "hindi": "hi", "\u0939\u093F\u0928\u094D\u0926\u0940": "hi", "\u0939\u093F\u0902\u0926\u0940": "hi"}
MENU_WORDS = {"hi", "hello", "hey", "menu", "help", "start", "0", "\u0C28\u0C2E\u0C38\u0C4D\u0C24\u0C47", "\u0C28\u0C2E\u0C38\u0C4D\u0C15\u0C3E\u0C30\u0C02", "\u0C39\u0C32\u0C4B", "\u0C38\u0C39\u0C3E\u0C2F\u0C02", "\u0C2E\u0C46\u0C28\u0C42", "\u0C2E\u0C46\u0C28\u0C41",
              "\u0928\u092E\u0938\u094D\u0924\u0947", "\u092E\u0926\u0926", "\u092E\u0947\u0928\u0942", "\u0939\u0947\u0932\u094D\u092A"}
SCHEME_WORDS = ["scheme", "subsidy", "\u0C2A\u0C25\u0C15", "\u0C38\u0C2C\u0C4D\u0C38\u0C3F\u0C21\u0C40", "\u0C38\u0C4D\u0C15\u0C40\u0C2E\u0C4D", "\u092F\u094B\u091C\u0928\u093E", "\u0938\u092C\u094D\u0938\u093F\u0921\u0940"]
PROFIT_WORDS = ["profit", "income", "earn", "\u0C32\u0C3E\u0C2D\u0C02", "\u0C32\u0C3E\u0C2D", "\u0C06\u0C26\u0C3E\u0C2F\u0C02", "\u092E\u0941\u0928\u093E\u092B\u093E", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E", "\u0932\u093E\u092D", "\u0915\u092E\u093E\u0908"]
PRICE_WORDS = ["price", "rate", "\u0C27\u0C30", "\u0C30\u0C47\u0C1F\u0C41", "\u0C2D\u0C3E\u0C35\u0C02", "\u092D\u093E\u0935", "\u0915\u0940\u092E\u0924", "\u0926\u093E\u092E"]
HECTARE_WORDS = ["hectare", "hectar", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C4D", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C41", "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930"]

# crop (model name): (english, telugu, hindi, extra aliases)
CROPS = {
    "Rice": ("rice", "\u0C35\u0C30\u0C3F", "\u0927\u093E\u0928", ["\u0C27\u0C3E\u0C28\u0C4D\u0C2F\u0C02", "vari", "paddy", "dhan", "chawal", "\u091A\u093E\u0935\u0932"]),
    "Maize": ("maize", "\u0C2E\u0C4A\u0C15\u0C4D\u0C15\u0C1C\u0C4A\u0C28\u0C4D\u0C28", "\u092E\u0915\u094D\u0915\u093E", ["mokkajonna", "corn"]),
    "Jowar": ("jowar", "\u0C1C\u0C4A\u0C28\u0C4D\u0C28", "\u091C\u094D\u0935\u093E\u0930", ["\u0C1C\u0C4A\u0C28\u0C4D\u0C28\u0C32\u0C41", "jonna", "sorghum"]),
    "Bajra": ("bajra", "\u0C38\u0C1C\u0C4D\u0C1C", "\u092C\u093E\u091C\u0930\u093E", ["\u0C38\u0C1C\u0C4D\u0C1C\u0C32\u0C41", "sajja"]),
    "Ragi": ("ragi", "\u0C30\u0C3E\u0C17\u0C3F", "\u0930\u093E\u0917\u0940", ["\u0C30\u0C3E\u0C17\u0C41\u0C32\u0C41"]),
    "Wheat": ("wheat", "\u0C17\u0C4B\u0C27\u0C41\u0C2E", "\u0917\u0947\u0939\u0942\u0902", ["\u0C17\u0C4B\u0C27\u0C41\u0C2E\u0C32\u0C41", "godhuma", "\u0917\u0947\u0939\u0942\u0901"]),
    "Arhar/Tur": ("red gram (tur)", "\u0C15\u0C02\u0C26\u0C3F", "\u0905\u0930\u0939\u0930", ["kandi", "tur", "toor", "arhar", "red gram", "\u0924\u0942\u0930"]),
    "Gram": ("chickpea (gram)", "\u0C36\u0C28\u0C17", "\u091A\u0928\u093E", ["\u0C36\u0C28\u0C17\u0C32\u0C41", "senaga", "chana", "gram", "chickpea"]),
    "Moong(Green Gram)": ("green gram (moong)", "\u0C2A\u0C46\u0C38\u0C30", "\u092E\u0942\u0902\u0917", ["\u0C2A\u0C46\u0C38\u0C32\u0C41", "pesara", "pesalu", "moong", "green gram", "mung"]),
    "Urad": ("black gram (urad)", "\u0C2E\u0C3F\u0C28\u0C41\u0C2E\u0C41", "\u0909\u0921\u093C\u0926", ["\u0C2E\u0C3F\u0C28\u0C41\u0C2E\u0C41\u0C32\u0C41", "minumu", "urad", "black gram"]),
    "Groundnut": ("groundnut", "\u0C35\u0C47\u0C30\u0C41\u0C36\u0C28\u0C17", "\u092E\u0942\u0902\u0917\u092B\u0932\u0940", ["verusenaga", "peanut", "groundnut"]),
    "Sunflower": ("sunflower", "\u0C2A\u0C4A\u0C26\u0C4D\u0C26\u0C41\u0C24\u0C3F\u0C30\u0C41\u0C17\u0C41\u0C21\u0C41", "\u0938\u0942\u0930\u091C\u092E\u0941\u0916\u0940", []),
    "Sesamum": ("sesame", "\u0C28\u0C41\u0C35\u0C4D\u0C35\u0C41\u0C32\u0C41", "\u0924\u093F\u0932", ["nuvvulu", "sesame", "gingelly"]),
    "Castor seed": ("castor", "\u0C06\u0C2E\u0C41\u0C26\u0C02", "\u0905\u0930\u0902\u0921\u0940", ["amudam", "castor"]),
    "Soyabean": ("soybean", "\u0C38\u0C4B\u0C2F\u0C3E\u0C2C\u0C40\u0C28\u0C4D", "\u0938\u094B\u092F\u093E\u092C\u0940\u0928", ["soyabean", "soya"]),
    "Dry chillies": ("chilli", "\u0C2E\u0C3F\u0C30\u0C4D\u0C1A\u0C3F", "\u092E\u093F\u0930\u094D\u091A", ["\u0C2E\u0C3F\u0C30\u0C2A", "\u0C2E\u0C3F\u0C30\u0C2A\u0C15\u0C3E\u0C2F", "mirchi", "mirapa", "chili", "chilly"]),
    "Turmeric": ("turmeric", "\u0C2A\u0C38\u0C41\u0C2A\u0C41", "\u0939\u0932\u094D\u0926\u0940", ["pasupu"]),
    "Onion": ("onion", "\u0C09\u0C32\u0C4D\u0C32\u0C3F", "\u092A\u094D\u092F\u093E\u091C", ["\u0C09\u0C32\u0C4D\u0C32\u0C3F\u0C2A\u0C3E\u0C2F", "ulli"]),
    "Potato": ("potato", "\u0C2C\u0C02\u0C17\u0C3E\u0C33\u0C26\u0C41\u0C02\u0C2A", "\u0906\u0932\u0942", ["\u0C06\u0C32\u0C41\u0C17\u0C21\u0C4D\u0C21", "batata"]),
    "Tomato": ("tomato", "\u0C1F\u0C2E\u0C3E\u0C1F\u0C3E", "\u091F\u092E\u093E\u091F\u0930", ["\u0C1F\u0C2E\u0C4B\u0C1F\u0C3E", "tomata"]),
    "Brinjal": ("brinjal", "\u0C35\u0C02\u0C15\u0C3E\u0C2F", "\u092C\u0948\u0902\u0917\u0928", ["vankaya", "eggplant"]),
    "Bhindi": ("okra (bhindi)", "\u0C2C\u0C46\u0C02\u0C21\u0C15\u0C3E\u0C2F", "\u092D\u093F\u0902\u0921\u0940", ["\u0C2C\u0C46\u0C02\u0C21", "bendakaya", "bhindi", "okra"]),
    "Banana": ("banana", "\u0C05\u0C30\u0C1F\u0C3F", "\u0915\u0947\u0932\u093E", ["arati"]),
    "Mango": ("mango", "\u0C2E\u0C3E\u0C2E\u0C3F\u0C21\u0C3F", "\u0906\u092E", ["mamidi"]),
    "Sugarcane": ("sugarcane", "\u0C1A\u0C46\u0C30\u0C15\u0C41", "\u0917\u0928\u094D\u0928\u093E", ["cheruku"]),
    "Rapeseed &Mustard": ("mustard", "\u0C06\u0C35\u0C3E\u0C32\u0C41", "\u0938\u0930\u0938\u094B\u0902", ["mustard"]),
    "Masoor": ("lentil (masoor)", "\u0C2E\u0C38\u0C42\u0C30\u0C4D", "\u092E\u0938\u0942\u0930", ["masoor", "lentil"]),
}
CROP_ALIASES = sorted(
    [(a.lower().replace("\u200c", ""), c) for c, (en, te, hi, extra) in CROPS.items() for a in {en, te, hi, c.lower(), *extra}],
    key=lambda x: -len(x[0]))

# district names in Telugu script (old district names used in the government data)
TELUGU_DISTRICTS = {
    "\u0C06\u0C26\u0C3F\u0C32\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "ADILABAD", "\u0C39\u0C48\u0C26\u0C30\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "HYDERABAD", "\u0C15\u0C30\u0C40\u0C02\u0C28\u0C17\u0C30\u0C4D": "KARIMNAGAR", "\u0C16\u0C2E\u0C4D\u0C2E\u0C02": "KHAMMAM",
    "\u0C2E\u0C39\u0C2C\u0C42\u0C2C\u0C4D\u200C\u0C28\u0C17\u0C30\u0C4D": "MAHBUBNAGAR", "\u0C2E\u0C39\u0C2C\u0C42\u0C2C\u0C4D \u0C28\u0C17\u0C30\u0C4D": "MAHBUBNAGAR", "\u0C2E\u0C46\u0C26\u0C15\u0C4D": "MEDAK", "\u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21": "NALGONDA",
    "\u0C28\u0C32\u0C4D\u0C32\u0C17\u0C4A\u0C02\u0C21": "NALGONDA", "\u0C28\u0C3F\u0C1C\u0C3E\u0C2E\u0C3E\u0C2C\u0C3E\u0C26\u0C4D": "NIZAMABAD", "\u0C30\u0C02\u0C17\u0C3E\u0C30\u0C46\u0C21\u0C4D\u0C21\u0C3F": "RANGAREDDI", "\u0C35\u0C30\u0C02\u0C17\u0C32\u0C4D": "WARANGAL",
    "\u0C05\u0C28\u0C02\u0C24\u0C2A\u0C41\u0C30\u0C02": "ANANTAPUR", "\u0C1A\u0C3F\u0C24\u0C4D\u0C24\u0C42\u0C30\u0C41": "CHITTOOR", "\u0C24\u0C42\u0C30\u0C4D\u0C2A\u0C41 \u0C17\u0C4B\u0C26\u0C3E\u0C35\u0C30\u0C3F": "EAST GODAVARI", "\u0C17\u0C41\u0C02\u0C1F\u0C42\u0C30\u0C41": "GUNTUR",
    "\u0C15\u0C21\u0C2A": "KADAPA", "\u0C15\u0C43\u0C37\u0C4D\u0C23\u0C3E": "KRISHNA", "\u0C15\u0C30\u0C4D\u0C28\u0C42\u0C32\u0C41": "KURNOOL", "\u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C36\u0C02": "PRAKASAM", "\u0C28\u0C46\u0C32\u0C4D\u0C32\u0C42\u0C30\u0C41": "SPSR NELLORE",
    "\u0C36\u0C4D\u0C30\u0C40\u0C15\u0C3E\u0C15\u0C41\u0C33\u0C02": "SRIKAKULAM", "\u0C35\u0C3F\u0C36\u0C3E\u0C16\u0C2A\u0C1F\u0C4D\u0C28\u0C02": "VISAKHAPATANAM", "\u0C35\u0C3F\u0C1C\u0C2F\u0C28\u0C17\u0C30\u0C02": "VIZIANAGARAM",
    "\u0C2A\u0C36\u0C4D\u0C1A\u0C3F\u0C2E \u0C17\u0C4B\u0C26\u0C3E\u0C35\u0C30\u0C3F": "WEST GODAVARI"}
ROMAN_EXTRA = {"nellore": "SPSR NELLORE", "vizag": "VISAKHAPATANAM", "cuddapah": "KADAPA", "mahabubnagar": "MAHBUBNAGAR",
               "rangareddy": "RANGAREDDI", "ranga reddy": "RANGAREDDI", "nalagonda": "NALGONDA", "kurnool": "KURNOOL"}
STATE_PREFERENCE = ("Telangana", "Andhra Pradesh")

T = {
    "menu": {
        "en": "GeoYield AI - farmer help. Send:\n1. crop + district + acres (e.g. rice nalgonda 2) = yield\n2. schemes = government schemes\n3. profit + district + acres (e.g. profit nalgonda 2) = which crop earns most\n4. price rice = mandi price\nLanguage: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940",
        "te": "GeoYield AI - \u0C30\u0C48\u0C24\u0C41 \u0C38\u0C39\u0C3E\u0C2F\u0C02. \u0C07\u0C32\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F:\n1. \u0C2A\u0C02\u0C1F + \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E + \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 (\u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2) = \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F\n2. \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41 = \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41\n3. \u0C32\u0C3E\u0C2D\u0C02 + \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E + \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 (\u0C09\u0C26\u0C3E: \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2) = \u0C0F \u0C2A\u0C02\u0C1F\u0C15\u0C41 \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02\n4. \u0C27\u0C30 \u0C35\u0C30\u0C3F = \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\n\u0C2D\u0C3E\u0C37: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940",
        "hi": "GeoYield AI - \u0915\u093F\u0938\u093E\u0928 \u0938\u0939\u093E\u092F\u0924\u093E\u0964 \u0910\u0938\u0947 \u092D\u0947\u091C\u0947\u0902:\n1. \u092B\u0938\u0932 + \u091C\u093C\u093F\u0932\u093E + \u090F\u0915\u0921\u093C (\u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2) = \u0909\u092A\u091C\n2. \u092F\u094B\u091C\u0928\u093E = \u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901\n3. \u092E\u0941\u0928\u093E\u092B\u093E + \u091C\u093C\u093F\u0932\u093E + \u090F\u0915\u0921\u093C (\u091C\u0948\u0938\u0947: \u092E\u0941\u0928\u093E\u092B\u093E nalgonda 2) = \u0915\u093F\u0938 \u092B\u0938\u0932 \u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0906\u092F\n4. \u092D\u093E\u0935 \u0927\u093E\u0928 = \u092E\u0902\u0921\u0940 \u092D\u093E\u0935\n\u092D\u093E\u0937\u093E: English / \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41 / \u0939\u093F\u0928\u094D\u0926\u0940"},
    "lang_set": {"en": "Language set to English.", "te": "\u0C2D\u0C3E\u0C37 \u0C24\u0C46\u0C32\u0C41\u0C17\u0C41\u0C15\u0C41 \u0C2E\u0C3E\u0C30\u0C4D\u0C1A\u0C3E\u0C02.", "hi": "\u092D\u093E\u0937\u093E \u0939\u093F\u0928\u094D\u0926\u0940 \u0915\u0930 \u0926\u0940 \u0917\u0908\u0964"},
    "need_crop": {"en": "Which crop? Example: rice nalgonda 2", "te": "\u0C0F \u0C2A\u0C02\u0C1F? \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u0915\u094C\u0928 \u0938\u0940 \u092B\u0938\u0932? \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "need_district": {"en": "Which district? Example: rice nalgonda 2", "te": "\u0C0F \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E? \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u0915\u094C\u0928 \u0938\u093E \u091C\u093C\u093F\u0932\u093E? \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "need_both": {"en": "Please send crop, district and acres. Example: rice nalgonda 2", "te": "\u0C2A\u0C02\u0C1F, \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E, \u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F. \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2", "hi": "\u092B\u0938\u0932, \u091C\u093C\u093F\u0932\u093E \u0914\u0930 \u090F\u0915\u0921\u093C \u092D\u0947\u091C\u0947\u0902\u0964 \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2"},
    "fail": {"en": "Sorry, I could not work this out: {e}", "te": "\u0C15\u0C4D\u0C37\u0C2E\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F, \u0C07\u0C26\u0C3F \u0C32\u0C46\u0C15\u0C4D\u0C15\u0C3F\u0C02\u0C1A\u0C32\u0C47\u0C15\u0C2A\u0C4B\u0C2F\u0C3E\u0C02: {e}", "hi": "\u0915\u094D\u0937\u092E\u093E \u0915\u0930\u0947\u0902, \u092F\u0939 \u0939\u093F\u0938\u093E\u092C \u0928\u0939\u0940\u0902 \u0939\u094B \u0938\u0915\u093E: {e}"},
    "yield": {
        "en": "{crop}, {district} ({season}), {area} {unit}\nExpected yield: about {qa} quintals per acre (total about {qt} quintals).\n{income}This is only an estimate from old government records (up to 2015); real yield can differ.",
        "te": "{crop}, {district} ({season}), {area} {unit}\n\u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F: \u0C0E\u0C15\u0C30\u0C3E\u0C15\u0C41 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {qa} \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41 (\u0C2E\u0C4A\u0C24\u0C4D\u0C24\u0C02 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {qt} \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41).\n{income}\u0C07\u0C26\u0C3F 2015 \u0C35\u0C30\u0C15\u0C41 \u0C09\u0C28\u0C4D\u0C28 \u0C2A\u0C3E\u0C24 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C30\u0C3F\u0C15\u0C3E\u0C30\u0C4D\u0C21\u0C41\u0C32 \u0C06\u0C27\u0C3E\u0C30\u0C02\u0C17\u0C3E \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47; \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F \u0C2D\u0C3F\u0C28\u0C4D\u0C28\u0C02\u0C17\u0C3E \u0C09\u0C02\u0C21\u0C35\u0C1A\u0C4D\u0C1A\u0C41.",
        "hi": "{crop}, {district} ({season}), {area} {unit}\n\u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0909\u092A\u091C: \u0932\u0917\u092D\u0917 {qa} \u0915\u094D\u0935\u093F\u0902\u091F\u0932 \u092A\u094D\u0930\u0924\u093F \u090F\u0915\u0921\u093C (\u0915\u0941\u0932 \u0932\u0917\u092D\u0917 {qt} \u0915\u094D\u0935\u093F\u0902\u091F\u0932)\u0964\n{income}\u092F\u0939 2015 \u0924\u0915 \u0915\u0947 \u092A\u0941\u0930\u093E\u0928\u0947 \u0938\u0930\u0915\u093E\u0930\u0940 \u0930\u093F\u0915\u0949\u0930\u094D\u0921 \u092A\u0930 \u0906\u0927\u093E\u0930\u093F\u0924 \u0905\u0928\u0941\u092E\u093E\u0928 \u0939\u0948; \u0905\u0938\u0932\u0940 \u0909\u092A\u091C \u0905\u0932\u0917 \u0939\u094B \u0938\u0915\u0924\u0940 \u0939\u0948\u0964"},
    "income": {
        "en": "At Rs {p}/quintal ({src}) income is about Rs {rev} (costs not included).\n",
        "te": "\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9{p} ({src}) \u0C2A\u0C4D\u0C30\u0C15\u0C3E\u0C30\u0C02 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 \u20B9{rev} (\u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41).\n",
        "hi": "\u20B9{p}/\u0915\u094D\u0935\u093F\u0902\u091F\u0932 ({src}) \u092A\u0930 \u0906\u092F \u0932\u0917\u092D\u0917 \u20B9{rev} (\u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902)\u0964\n"},
    "income_hint": {"en": "For income, also send the price. Example: rice nalgonda 2 2300\n", "te": "\u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C15\u0C4B\u0C38\u0C02 \u0C27\u0C30 \u0C15\u0C42\u0C21\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F. \u0C09\u0C26\u0C3E: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300\n", "hi": "\u0906\u092F \u0915\u0947 \u0932\u093F\u090F \u092D\u093E\u0935 \u092D\u0940 \u092D\u0947\u091C\u0947\u0902\u0964 \u091C\u0948\u0938\u0947: \u0927\u093E\u0928 nalgonda 2 2300\n"},
    "src_typed": {"en": "your price", "te": "\u0C2E\u0C40\u0C30\u0C41 \u0C1A\u0C46\u0C2A\u0C4D\u0C2A\u0C3F\u0C28 \u0C27\u0C30", "hi": "\u0906\u092A\u0915\u093E \u092D\u093E\u0935"},
    "src_live": {"en": "mandi price", "te": "\u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30", "hi": "\u092E\u0902\u0921\u0940 \u092D\u093E\u0935"},
    "price_ok": {"en": "{crop} mandi price in {state}: Rs {p} per quintal ({date}, {n} markets). Source: Agmarknet.",
                 "te": "{state}\u0C32\u0C4B {crop} \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30: \u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9{p} ({date}, {n} \u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D\u0C32\u0C41). \u0C2E\u0C42\u0C32\u0C02: Agmarknet.",
                 "hi": "{state} \u092E\u0947\u0902 {crop} \u0915\u093E \u092E\u0902\u0921\u0940 \u092D\u093E\u0935: \u20B9{p} \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932 ({date}, {n} \u092C\u093E\u091C\u093C\u093E\u0930)\u0964 \u0938\u094D\u0930\u094B\u0924: Agmarknet\u0964"},
    "price_none": {"en": "Today's price was not found. Check your mandi and send: rice nalgonda 2 2300",
                   "te": "\u0C08 \u0C30\u0C4B\u0C1C\u0C41 \u0C27\u0C30 \u0C26\u0C4A\u0C30\u0C15\u0C32\u0C47\u0C26\u0C41. \u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B \u0C1A\u0C42\u0C38\u0C3F \u0C07\u0C32\u0C3E \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F: \u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 2300",
                   "hi": "\u0906\u091C \u0915\u093E \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u092E\u093F\u0932\u093E\u0964 \u0905\u092A\u0928\u0940 \u092E\u0902\u0921\u0940 \u092E\u0947\u0902 \u0926\u0947\u0916\u0915\u0930 \u092D\u0947\u091C\u0947\u0902: \u0927\u093E\u0928 nalgonda 2 2300"},
    "profit_head": {"en": "{district} ({season}), {area} {unit} - crops with best income:\n", "te": "{district} ({season}), {area} {unit} - \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C07\u0C1A\u0C4D\u0C1A\u0C47 \u0C2A\u0C02\u0C1F\u0C32\u0C41:\n", "hi": "{district} ({season}), {area} {unit} - \u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0906\u092F \u0935\u093E\u0932\u0940 \u092B\u0938\u0932\u0947\u0902:\n"},
    "profit_line": {"en": "{i}. {crop}: about Rs {inc}\n", "te": "{i}. {crop}: \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 \u20B9{inc}\n", "hi": "{i}. {crop}: \u0932\u0917\u092D\u0917 \u20B9{inc}\n"},
    "profit_tail": {"en": "Income only, costs not included. Prices change daily.", "te": "\u0C07\u0C26\u0C3F \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47, \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41. \u0C27\u0C30\u0C32\u0C41 \u0C30\u0C4B\u0C1C\u0C42 \u0C2E\u0C3E\u0C30\u0C24\u0C3E\u0C2F\u0C3F.", "hi": "\u0915\u0947\u0935\u0932 \u0906\u092F, \u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902\u0964 \u092D\u093E\u0935 \u0930\u094B\u091C\u093C \u092C\u0926\u0932\u0924\u0947 \u0939\u0948\u0902\u0964"},
    "profit_noprice": {"en": "No live prices. Send prices from your mandi, e.g.: profit nalgonda 2 rice=2300 maize=2100", "te": "\u0C32\u0C48\u0C35\u0C4D \u0C27\u0C30\u0C32\u0C41 \u0C32\u0C47\u0C35\u0C41. \u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\u0C32\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F, \u0C09\u0C26\u0C3E: \u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2 \u0C35\u0C30\u0C3F=2300 \u0C2E\u0C4A\u0C15\u0C4D\u0C15\u0C1C\u0C4A\u0C28\u0C4D\u0C28=2100", "hi": "\u0932\u093E\u0907\u0935 \u092D\u093E\u0935 \u0928\u0939\u0940\u0902 \u0939\u0948\u0902\u0964 \u0905\u092A\u0928\u0940 \u092E\u0902\u0921\u0940 \u0915\u0947 \u092D\u093E\u0935 \u092D\u0947\u091C\u0947\u0902, \u091C\u0948\u0938\u0947: \u092E\u0941\u0928\u093E\u092B\u093E nalgonda 2 \u0927\u093E\u0928=2300 \u092E\u0915\u094D\u0915\u093E=2100"},
    "schemes_head": {"en": "Government schemes:\n", "te": "\u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41:\n", "hi": "\u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901:\n"},
    "schemes_tail": {"en": "For details send the scheme name, e.g. PMFBY.", "te": "\u0C35\u0C3F\u0C35\u0C30\u0C3E\u0C32\u0C15\u0C41 \u0C2A\u0C25\u0C15\u0C02 \u0C2A\u0C47\u0C30\u0C41 \u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F, \u0C09\u0C26\u0C3E: PMFBY.", "hi": "\u0935\u093F\u0935\u0930\u0923 \u0915\u0947 \u0932\u093F\u090F \u092F\u094B\u091C\u0928\u093E \u0915\u093E \u0928\u093E\u092E \u092D\u0947\u091C\u0947\u0902, \u091C\u0948\u0938\u0947: PMFBY\u0964"},
    "how": {"en": "How: ", "te": "\u0C0E\u0C32\u0C3E: ", "hi": "\u0915\u0948\u0938\u0947: "},
}
SEASON_WORDS = {"kharif": "Kharif", "\u0C16\u0C30\u0C40\u0C2B\u0C4D": "Kharif", "\u0916\u0930\u0940\u092B": "Kharif", "rabi": "Rabi", "\u0C30\u0C2C\u0C40": "Rabi", "\u0930\u092C\u0940": "Rabi"}
SEASON_LABEL = {"Kharif": {"en": "Kharif", "te": "\u0C16\u0C30\u0C40\u0C2B\u0C4D", "hi": "\u0916\u0930\u0940\u092B"}, "Rabi": {"en": "Rabi", "te": "\u0C30\u0C2C\u0C40", "hi": "\u0930\u092C\u0940"}}
UNIT = {"acre": {"en": "acres", "te": "\u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41", "hi": "\u090F\u0915\u0921\u093C"}, "hectare": {"en": "hectares", "te": "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C4D\u0C32\u0C41", "hi": "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930"}}


def _tr(key: str, lang: str, **kw) -> str:
    s = T[key].get(lang) or T[key]["en"]
    return s.format(**kw) if kw else s


# ---------- small helpers ----------
def inr(n: float) -> str:
    """Indian digit grouping: 1234567 -> 12,34,567"""
    s = str(int(round(n)))
    if len(s) <= 3:
        return s
    head, tail = s[:-3], s[-3:]
    head = re.sub(r"(\d)(?=(\d\d)+$)", r"\1,", head)
    return head + "," + tail


def num(x: float) -> str:
    return str(int(x)) if float(x).is_integer() else str(round(x, 2))


def normalise(text: str) -> str:
    out = []
    for ch in text:
        o = ord(ch)
        if 0x0C66 <= o <= 0x0C6F:
            ch = str(o - 0x0C66)       # Telugu digits
        elif 0x0966 <= o <= 0x096F:
            ch = str(o - 0x0966)       # Hindi digits
        out.append(ch)
    s = "".join(out).lower().replace("\u200c", "").replace("\u200d", "")
    s = re.sub(r"[,;!?\"'()\[\]]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def detect_lang(text: str, saved: str | None) -> str:
    if re.search(r"[\u0C00-\u0C7F]", text):
        return "te"
    if re.search(r"[\u0900-\u097F]", text):
        return "hi"
    return saved or "en"


def _scan(text: str, pairs: list[tuple[str, object]]) -> list[tuple[int, int, object]]:
    """Find alias words in text (longest first, no overlaps). Latin words must be whole words."""
    taken = [False] * len(text)
    found = []
    for alias, val in pairs:
        start = 0
        while True:
            i = text.find(alias, start)
            if i < 0:
                break
            j = i + len(alias)
            start = i + 1
            if any(taken[i:j]):
                continue
            if alias[0].isascii() and alias[0].isalnum() and i > 0 and text[i - 1].isascii() and text[i - 1].isalnum():
                continue
            if alias[-1].isascii() and alias[-1].isalnum() and j < len(text) and text[j].isascii() and text[j].isalpha():
                continue
            for k in range(i, j):
                taken[k] = True
            found.append((i, j, val))
    return sorted(found, key=lambda x: x[0])


_dist_cache: list | None = None


def _district_pairs() -> list[tuple[str, tuple[str, str]]]:
    global _dist_cache
    if _dist_cache is not None:
        return _dist_cache
    opts = yield_service.options() or {}
    where: dict[str, list[tuple[str, str]]] = {}
    for state, ds in (opts.get("districts") or {}).items():
        for d in ds:
            where.setdefault(d, []).append((state, d))

    def pick(d):
        cands = where.get(d, [])
        for s in STATE_PREFERENCE:
            for c in cands:
                if c[0] == s:
                    return c
        return cands[0] if cands else None

    pairs = []
    for d in where:
        pairs.append((d.lower(), pick(d)))
    for alias, d in {**TELUGU_DISTRICTS, **ROMAN_EXTRA}.items():
        p = pick(d)
        if p:
            pairs.append((alias.lower().replace("\u200c", ""), p))
    _dist_cache = sorted(pairs, key=lambda x: -len(x[0]))
    return _dist_cache


def _district_label(district: str, lang: str) -> str:
    if lang == "te":
        for te, d in TELUGU_DISTRICTS.items():
            if d == district:
                return te
    return district.title()


def _season_now() -> str:
    m = datetime.now().month
    return "Kharif" if m in (4, 5, 6, 7, 8, 9, 10) else "Rabi"


def parse(text: str) -> dict:
    """Pull crop(s), district, numbers, season and unit out of a farmer's message."""
    low = normalise(text)
    crops = _scan(low, CROP_ALIASES)
    dists = _scan(low, _district_pairs())
    used = [(a, b) for a, b, _ in crops + dists]
    # crop=price pairs, e.g. "rice=2300"
    typed, pair_spans = {}, []
    for a, b, crop in crops:
        m = re.match(r"\s*[=:]\s*(\d+(?:\.\d+)?)", low[b:])
        if m:
            typed[crop] = float(m.group(1))
            pair_spans.append((b, b + m.end()))
    nums = [(m.start(), float(m.group())) for m in re.finditer(r"\d+(?:\.\d+)?", low)
            if not any(s <= m.start() < e for s, e in pair_spans + used)]
    price_pos = min((low.find(w) for w in PRICE_WORDS if w in low), default=-1)
    acres = price = None
    if price_pos >= 0 and nums:
        after = [n for n in nums if n[0] >= price_pos]
        pr = after[0] if after else nums[-1]
        price = pr[1]
        rest = [n for n in nums if n is not pr]
        acres = rest[0][1] if rest else None
    elif len(nums) >= 2:
        small, big = sorted(nums, key=lambda n: n[1])[0], sorted(nums, key=lambda n: n[1])[-1]
        acres, price = small[1], (big[1] if big[1] >= 100 else None)
    elif nums:
        acres = nums[0][1]
    season = next((v for k, v in SEASON_WORDS.items() if k in low), None)
    unit = "hectare" if (any(w in low for w in HECTARE_WORDS) or re.search(r"\bha\b", low)) else "acre"
    return {"low": low, "crops": [c for _, _, c in crops], "district": dists[0][2] if dists else None,
            "typed_prices": typed, "acres": acres, "price": price, "season": season, "unit": unit,
            "has_number": bool(nums or typed)}


# ---------- language memory (phone number is stored only as a hash) ----------
def ensure_tables() -> None:
    with db.connect() as c:
        c.execute("CREATE TABLE IF NOT EXISTS bot_users (id TEXT PRIMARY KEY, lang TEXT, updated_at TEXT)")


def _uid(phone: str) -> str:
    return hashlib.sha256((os.getenv("BOT_HASH_SALT", "geoyield") + phone).encode()).hexdigest()[:24]


def _saved_lang(phone: str) -> str | None:
    if not phone:
        return None
    try:
        with db.connect() as c:
            r = c.execute("SELECT lang FROM bot_users WHERE id=?", (_uid(phone),)).fetchone()
        return r["lang"] if r else None
    except Exception:
        return None


def _save_lang(phone: str, lang: str) -> None:
    if not phone:
        return
    try:
        with db.connect() as c:
            c.execute("INSERT INTO bot_users (id, lang, updated_at) VALUES (?,?,?) "
                      "ON CONFLICT(id) DO UPDATE SET lang=excluded.lang, updated_at=excluded.updated_at",
                      (_uid(phone), lang, datetime.now(timezone.utc).isoformat(timespec="seconds")))
    except Exception:
        pass


# ---------- replies ----------
def _crop_label(crop: str, lang: str) -> str:
    en, te, hi, _ = CROPS.get(crop, (crop, crop, crop, []))
    return {"te": te, "hi": hi}.get(lang, en.title() if crop in CROPS else crop)


def _schemes_reply(state, lang):
    data = schemes_service.for_farmer(state, None, None, lang)
    lines = "".join(f"- {s['name'].split(' (')[0]}: {s['short']}\n" for s in data["schemes"])
    return _tr("schemes_head", lang) + lines + _tr("schemes_tail", lang) + "\n" + data["note"]


def _yield_reply(p, state, district, lang, phone):
    crop, unit = p["crops"][0], p["unit"]
    area = p["acres"] or 1
    area_ha = area if unit == "hectare" else area / ACRE_PER_HA
    season = p["season"] or _season_now()
    inp = {"state": state, "district": district, "season": season, "crop": crop, "area_hectares": area_ha, "lang": lang}
    res = yield_service.predict(inp)
    if res.get("model_status") == "unavailable":
        return res["message"]
    if "error" in res:
        return _tr("fail", lang, e=res["error"])
    y = res["predicted_yield"]
    qa, qt = round(y * 10 / ACRE_PER_HA, 1), round(y * 10 * area_ha, 1)
    price, src = p["price"] or p["typed_prices"].get(crop), "src_typed"
    if not price:
        live = prices.latest_price(crop, state, district)
        price, src = (live["price"], "src_live") if live else (None, None)
    income = _tr("income", lang, p=inr(price), src=_tr(src, lang), rev=inr(qt * price)) if price else _tr("income_hint", lang)
    try:
        db.save_analysis("yield_prediction", {**inp, "source": "bot"}, res, f"{crop}: {y} t/ha (bot)",
                         {"model": "sklearn regressor", "status": "trained"})
    except Exception:
        pass
    return _tr("yield", lang, crop=_crop_label(crop, lang), district=_district_label(district, lang),
               season=SEASON_LABEL.get(season, {}).get(lang, season), area=num(area), unit=UNIT[unit][lang], qa=qa, qt=qt, income=income)


def _profit_reply(p, state, district, lang):
    area, unit = p["acres"] or 1, p["unit"]
    season = p["season"] or _season_now()
    res = profit_service.compare({"state": state, "district": district, "season": season, "area": area,
                                  "area_unit": unit, "prices": p["typed_prices"], "lang": lang})
    rows = [r for r in res.get("rows", []) if r.get("income") is not None][:3]
    if not rows:
        return _tr("profit_noprice", lang)
    out = _tr("profit_head", lang, area=num(area), unit=UNIT[unit][lang], district=_district_label(district, lang),
              season=SEASON_LABEL.get(season, {}).get(lang, season))
    for i, r in enumerate(rows, 1):
        out += _tr("profit_line", lang, i=i, crop=_crop_label(r["crop"], lang), inc=inr(r["income"]))
    return out + _tr("profit_tail", lang)


def handle(text: str, phone: str = "") -> dict:
    """Main entry: message in -> {"reply": str, "lang": str}."""
    saved = _saved_lang(phone)
    lang = detect_lang(text or "", saved)
    low = normalise(text or "")
    if low in LANG_WORDS:
        lang = LANG_WORDS[low]
        _save_lang(phone, lang)
        return {"reply": _tr("lang_set", lang) + "\n" + _tr("menu", lang), "lang": lang}
    if lang != saved and re.search(r"[\u0C00-\u0C7F\u0900-\u097F]", text or ""):
        _save_lang(phone, lang)
    if not low or low in MENU_WORDS:
        return {"reply": _tr("menu", lang), "lang": lang}
    p = parse(text)
    state, district = None, None
    if p["district"]:
        state, district = p["district"]
    wants_schemes = any(w in low for w in SCHEME_WORDS) or low == "2"
    if wants_schemes:
        one = schemes_service.find(low, state, lang)
        if one:
            return {"reply": f"{one['name']}\n{one['benefit']}\n{_tr('how', lang)}{one['how']}", "lang": lang}
        return {"reply": _schemes_reply(state, lang), "lang": lang}
    if low in ("1", "3", "4"):
        return {"reply": _tr("menu", lang), "lang": lang}
    if not p["crops"] and not wants_schemes:
        one = schemes_service.find(low, state, lang)
        if one and not any(w in low for w in PROFIT_WORDS):
            return {"reply": f"{one['name']}\n{one['benefit']}\n{_tr('how', lang)}{one['how']}", "lang": lang}
    try:
        if any(w in low for w in PROFIT_WORDS):
            if not district:
                return {"reply": _tr("need_district", lang), "lang": lang}
            return {"reply": _profit_reply(p, state, district, lang), "lang": lang}
        if p["crops"] and any(w in low for w in PRICE_WORDS) and not p["has_number"] and not district:
            crop = p["crops"][0]
            st = state or "Telangana"
            live = prices.latest_price(crop, st, None)
            if not live:
                return {"reply": _tr("price_none", lang), "lang": lang}
            return {"reply": _tr("price_ok", lang, crop=_crop_label(crop, lang), state=st, p=inr(live["price"]),
                                 date=live["date"], n=live["markets"]), "lang": lang}
        if p["crops"] and district:
            return {"reply": _yield_reply(p, state, district, lang, phone), "lang": lang}
        if p["crops"]:
            return {"reply": _tr("need_district", lang), "lang": lang}
        if district:
            return {"reply": _tr("need_crop", lang), "lang": lang}
    except Exception as e:  # never crash a farmer's chat
        return {"reply": _tr("fail", lang, e=str(e)[:120]), "lang": lang}
    return {"reply": _tr("need_both", lang) + "\n\n" + _tr("menu", lang), "lang": lang}
'@
Save-File "backend\app\services\bot_service.py" $c

$c = @'
"""New endpoints: profit mode, government schemes, 'was this right?' feedback, WhatsApp/SMS bot."""
import base64
import hashlib
import hmac
import os
from typing import Literal, Optional
from xml.sax.saxutils import escape

from fastapi import APIRouter, Form, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field

from app.database import db
from app.i18n import norm, t
from app.schemas.schemas import Location
from app.services import bot_service, feedback_service, prices, profit_service, schemes_service

router = APIRouter(prefix="/api")


# ---------------- profit mode ----------------
class ProfitIn(Location):
    season: str = Field(..., min_length=2, max_length=20)
    area: float = Field(..., gt=0, le=100000)
    area_unit: Literal["acre", "hectare"] = "acre"
    crops: Optional[list[str]] = Field(None, max_length=15)
    prices: dict[str, float] = Field(default_factory=dict, description="crop -> Rs per quintal typed by the farmer")
    costs: dict[str, float] = Field(default_factory=dict, description="crop -> cost per acre/hectare typed by the farmer")


@router.get("/profit/options")
def profit_options(state: str = Query(..., max_length=60), district: str | None = Query(None, max_length=60),
                   season: str | None = Query(None, max_length=20)):
    return {"candidates": profit_service.candidates(state, district, season), "all_crops": profit_service.addable_crops(),
            "live_prices_enabled": prices.has_key()}


@router.post("/profit/compare")
def profit_compare(body: ProfitIn):
    inp = body.model_dump()
    inp["state"] = body.state or ""
    lang = norm(body.lang)
    if not body.state:
        raise HTTPException(422, "state is required")
    res = profit_service.compare(inp)
    if res.get("model_status") == "unavailable":
        raise HTTPException(503, res["message"])
    if res.get("error") == "no_crops":
        raise HTTPException(422, "No crops to compare. Pick at least one crop.")
    best = res.get("best") or "-"
    res["history_id"] = None if body.relocalize else db.save_analysis(
        "profit_comparison", {k: v for k, v in inp.items() if k != "relocalize"}, res,
        t("sum_profit", lang, crop=best), {"model": "yield model x price", "status": "trained"})
    return res


# ---------------- government schemes ----------------
@router.get("/schemes")
def schemes(state: str | None = Query(None, max_length=60), crop: str | None = Query(None, max_length=60),
            season: str | None = Query(None, max_length=20), lang: str = Query("en")):
    return schemes_service.for_farmer(state, crop, season, norm(lang))


# ---------------- "Was this right?" ----------------
class FeedbackIn(BaseModel):
    module: Literal["yield_prediction", "crop_recommendation", "profit_comparison"]
    history_id: Optional[int] = Field(None, ge=1)
    correct: bool
    actual_yield: Optional[float] = Field(None, ge=0, le=500, description="real yield, tonnes per hectare")
    actual_crop: Optional[str] = Field(None, max_length=60)
    actual_price: Optional[float] = Field(None, ge=0, le=10000000)
    comment: Optional[str] = Field(None, max_length=500)


@router.post("/feedback")
def feedback(body: FeedbackIn):
    return feedback_service.submit(body.module, body.history_id, body.correct, body.actual_yield,
                                   body.actual_crop, body.actual_price, body.comment)


@router.get("/feedback/summary")
def feedback_summary():
    return feedback_service.summary()


@router.get("/feedback/export")
def feedback_export():
    return Response(content=feedback_service.export_csv(), media_type="text/csv",
                    headers={"Content-Disposition": "attachment; filename=geoyield_feedback.csv"})


# ---------------- WhatsApp / SMS bot ----------------
class BotIn(BaseModel):
    text: str = Field(..., max_length=500)
    phone: str = Field("", max_length=30)


@router.post("/bot/message")
def bot_message(body: BotIn):
    """Same brain as the Twilio hook, as plain JSON (for testing without Twilio)."""
    return bot_service.handle(body.text, body.phone)


def twilio_signature(token: str, url: str, params: dict) -> str:
    data = url + "".join(k + params[k] for k in sorted(params))
    return base64.b64encode(hmac.new(token.encode(), data.encode(), hashlib.sha1).digest()).decode()


@router.post("/bot/twilio")
async def bot_twilio(request: Request, From: str = Form(""), Body: str = Form("")):
    """Twilio webhook (WhatsApp and SMS use the same format). Replies with TwiML."""
    token, public = os.getenv("TWILIO_AUTH_TOKEN", ""), os.getenv("BOT_PUBLIC_URL", "").rstrip("/")
    if token and public:  # check the message really comes from Twilio
        form = dict((await request.form()).items())
        sent = request.headers.get("X-Twilio-Signature", "")
        if not hmac.compare_digest(sent, twilio_signature(token, public + "/api/bot/twilio", form)):
            raise HTTPException(403, "bad signature")
    reply = bot_service.handle(Body, From)["reply"][:1500]
    xml = f'<?xml version="1.0" encoding="UTF-8"?><Response><Message>{escape(reply)}</Message></Response>'
    return Response(content=xml, media_type="application/xml")
'@
Save-File "backend\app\routes\upgrade.py" $c

$c = @'
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import ALLOWED_ORIGINS
from app.database import db
from app.routes.api import router
from app.routes.extras import router as extras_router
from app.routes.upgrade import router as upgrade_router
from app.services import bot_service, feedback_service


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_db()
    feedback_service.ensure_tables()  # profit history + feedback tables
    bot_service.ensure_tables()       # bot language memory
    yield


app = FastAPI(title="GeoYield AI API", description="Smart Farming. Better Yield. - Team Vibe_coders, AAROHAN 2.0",
              version="1.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=ALLOWED_ORIGINS, allow_methods=["*"], allow_headers=["*"])
app.include_router(router)
app.include_router(extras_router)
app.include_router(upgrade_router)


@app.get("/")
def root():
    return {"app": "GeoYield AI", "docs": "/docs", "status": "/api/status"}
'@
Save-File "backend\app\main.py" $c

$c = @'
"""Checks for: profit mode, mandi prices, government schemes, feedback, WhatsApp/SMS bot.
Run from the backend folder:   .\\venv\\Scripts\\python.exe -m pytest -q tests\\test_upgrade.py
"""
import pytest
from fastapi.testclient import TestClient

from app import config
from app.database import db
from app.services import bot_service, prices, profit_service, schemes_service


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "t.db")
    monkeypatch.setattr("app.database.db.DB_PATH", tmp_path / "t.db")
    monkeypatch.delenv("DATA_GOV_API_KEY", raising=False)
    from app.main import app
    with TestClient(app) as c:
        yield c


# ---------- prices ----------
def test_pick_price_uses_newest_day_and_district_first():
    recs = [
        {"state": "Telangana", "district": "Nalgonda", "arrival_date": "01/11/2026", "modal_price": "2000"},
        {"state": "Telangana", "district": "Nalgonda", "arrival_date": "02/11/2026", "modal_price": "2300"},
        {"state": "Telangana", "district": "Nalgonda", "arrival_date": "02/11/2026", "modal_price": "2500"},
        {"state": "Telangana", "district": "Warangal", "arrival_date": "02/11/2026", "modal_price": "9999"},
        {"state": "Karnataka", "district": "X", "arrival_date": "03/11/2026", "modal_price": "1"},
    ]
    p = prices.pick_price(recs, "Telangana", "NALGONDA")
    assert p["price"] == 2400 and p["scope"] == "district" and p["markets"] == 2
    assert prices.pick_price(recs, "Telangana", "ADILABAD")["scope"] == "state"
    assert prices.pick_price([], "Telangana", None) is None


def test_no_key_means_no_live_price(monkeypatch):
    monkeypatch.delenv("DATA_GOV_API_KEY", raising=False)
    assert prices.latest_price("Rice", "Telangana", "NALGONDA") is None


# ---------- profit ----------
BASE = {"state": "Telangana", "district": "NALGONDA", "season": "Kharif", "area": 2, "area_unit": "acre", "lang": "en"}


def test_profit_income_math(monkeypatch):
    monkeypatch.setattr(prices, "latest_price", lambda *a, **k: None)
    r = profit_service.compare({**BASE, "crops": ["Rice", "Maize"], "prices": {"Rice": 2300, "Maize": 2000}})
    rice = next(x for x in r["rows"] if x["crop"] == "Rice")
    assert rice["income"] == round(rice["production_quintals"] * 2300)
    assert r["ranked_by"] == "income" and r["rows"][0]["rank"] == 1
    assert any("not profit" in n for n in r["notes"])  # honest label: income, not profit


def test_profit_net_when_all_costs_given(monkeypatch):
    monkeypatch.setattr(prices, "latest_price", lambda *a, **k: None)
    r = profit_service.compare({**BASE, "crops": ["Rice"], "prices": {"Rice": 2300}, "costs": {"Rice": 20000}})
    row = r["rows"][0]
    assert r["ranked_by"] == "net" and row["cost"] == 40000 and row["net"] == row["income"] - 40000


def test_profit_missing_price_is_flagged_not_guessed(monkeypatch):
    monkeypatch.setattr(prices, "latest_price", lambda *a, **k: None)
    r = profit_service.compare({**BASE, "crops": ["Rice", "Maize"], "prices": {"Rice": 2300}})
    maize = next(x for x in r["rows"] if x["crop"] == "Maize")
    assert maize.get("income") is None and r["rows"][-1]["crop"] == "Maize"


def test_profit_uses_live_price_when_available(monkeypatch):
    monkeypatch.setattr(prices, "latest_price", lambda *a, **k: {"price": 2100, "date": "01-11-2026", "markets": 3})
    r = profit_service.compare({**BASE, "crops": ["Rice"]})
    assert r["rows"][0]["price"] == 2100 and r["rows"][0]["price_source"] == "live"


def test_profit_candidates_are_real_telangana_crops():
    c = profit_service.candidates("Telangana", "NALGONDA", "Kharif")
    assert "Rice" in c and "Sugarcane" not in c and len(c) >= 3


def test_profit_api_saves_history(client):
    r = client.post("/api/profit/compare", json={**BASE, "crops": ["Rice"], "prices": {"Rice": 2300}})
    assert r.status_code == 200 and r.json()["history_id"]
    h = client.get("/api/history?module=profit_comparison").json()["items"]
    assert len(h) == 1


# ---------- schemes ----------
def test_schemes_state_filter_and_relevance():
    tg = schemes_service.for_farmer("Telangana", "Rice", "Kharif", "te")
    ids = [s["name"] for s in tg["schemes"]]
    assert any("\u0C30\u0C48\u0C24\u0C41 \u0C2D\u0C30\u0C4B\u0C38\u0C3E" in n for n in ids) and not any("\u0C05\u0C28\u0C4D\u0C28\u0C26\u0C3E\u0C24" in n for n in ids)
    pmfby = next(s for s in tg["schemes"] if "\u0C2B\u0C38\u0C32\u0C4D" in s["name"])
    assert "2%" in pmfby["relevance"]
    assert schemes_service.pmfby_rate("Rice", "Rabi") == "1.5%" and schemes_service.pmfby_rate("Tomato", "Rabi") == "5%"


# ---------- feedback ----------
def test_feedback_measures_real_accuracy(client):
    y = client.post("/api/yield/predict", json={"state": "Telangana", "district": "NALGONDA", "crop": "Rice",
                                                "season": "Kharif", "area_hectares": 1}).json()
    hid, pred = y["history_id"], y["predicted_yield"]
    r = client.post("/api/feedback", json={"module": "yield_prediction", "history_id": hid, "correct": False,
                                           "actual_yield": pred * 2})
    assert r.status_code == 200
    client.post("/api/feedback", json={"module": "yield_prediction", "history_id": hid, "correct": False,
                                       "actual_yield": pred * 2})  # same row updated, not duplicated
    s = client.get("/api/feedback/summary").json()
    assert s["by_module"]["yield_prediction"]["count"] == 1
    assert abs(s["yield_error"]["mean_pct_error"] - 50.0) < 1
    assert "actual_yield" in client.get("/api/feedback/export").text


def test_feedback_rejects_bad_input(client):
    assert client.post("/api/feedback", json={"module": "nope", "correct": True}).status_code == 422
    assert client.post("/api/feedback", json={"module": "yield_prediction", "correct": True, "actual_yield": -1}).status_code == 422


# ---------- bot ----------
def test_bot_telugu_yield():
    r = bot_service.handle("\u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2")
    assert r["lang"] == "te" and "\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41" in r["reply"] and "\u0C35\u0C30\u0C3F" in r["reply"] and "\u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21" in r["reply"]


def test_bot_telugu_digits_and_price():
    r = bot_service.handle("\u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 \u0C68 \u0C68\u0C69\u0C66\u0C66")
    assert "\u20B92,300" in r["reply"] and "\u0C06\u0C26\u0C3E\u0C2F\u0C02" in r["reply"]


def test_bot_roman_english_and_price():
    r = bot_service.handle("rice nalgonda 2 2300")
    assert r["lang"] == "en" and "Rs 2,300" in r["reply"]
    r = bot_service.handle("vari nalgonda 2")
    assert "Expected yield" in r["reply"]


def test_bot_schemes_and_detail():
    assert "\u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D" in bot_service.handle("\u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41")["reply"]
    d = bot_service.handle("pmfby")["reply"]
    assert "14447" in d
    assert "\u0C30\u0C48\u0C24\u0C41 \u0C2D\u0C30\u0C4B\u0C38\u0C3E" in bot_service.handle("\u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21")["reply"]


def test_bot_profit_without_prices_asks_for_prices(monkeypatch):
    monkeypatch.setattr(prices, "latest_price", lambda *a, **k: None)
    assert "=" in bot_service.handle("\u0C32\u0C3E\u0C2D\u0C02 \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2")["reply"]
    r = bot_service.handle("profit nalgonda 2 rice=2300 maize=2000")["reply"]
    assert "1." in r and "Rice" in r


def test_bot_menu_and_unknown():
    assert "GeoYield" in bot_service.handle("hello")["reply"]
    assert "GeoYield" in bot_service.handle("\u0C28\u0C2E\u0C38\u0C4D\u0C24\u0C47")["reply"]
    assert "nalgonda" in bot_service.handle("rice")["reply"].lower() or "district" in bot_service.handle("rice")["reply"].lower()
    assert bot_service.handle("blah blah")["reply"]


def test_bot_language_switch_is_remembered(client):
    bot_service.handle("telugu", "+910000000001")
    r = bot_service.handle("schemes", "+910000000001")
    assert r["lang"] == "te"


def test_twilio_hook_returns_xml_and_checks_signature(client, monkeypatch):
    r = client.post("/api/bot/twilio", data={"From": "whatsapp:+910000000002", "Body": "\u0C35\u0C30\u0C3F \u0C28\u0C32\u0C4D\u0C17\u0C4A\u0C02\u0C21 2"})
    assert r.status_code == 200 and r.headers["content-type"].startswith("application/xml") and "<Message>" in r.text
    monkeypatch.setenv("TWILIO_AUTH_TOKEN", "secret")
    monkeypatch.setenv("BOT_PUBLIC_URL", "https://example.com")
    assert client.post("/api/bot/twilio", data={"From": "x", "Body": "hi"}).status_code == 403
    from app.routes.upgrade import twilio_signature
    form = {"From": "x", "Body": "hi"}
    sig = twilio_signature("secret", "https://example.com/api/bot/twilio", form)
    assert client.post("/api/bot/twilio", data=form, headers={"X-Twilio-Signature": sig}).status_code == 200
'@
Save-File "backend\tests\test_upgrade.py" $c

$c = @'
// New text for: Profit mode, Government schemes, "Was this right?" feedback. Each entry: key: [English, Hindi, Telugu].
// Merged into the main translations when this file is imported (App.jsx imports it).
// Please have a native speaker review the Hindi and Telugu.
import { translations } from "./translations.js";

const UP_T = {
  "nav.profit": ["Profit", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E", "\u0C32\u0C3E\u0C2D\u0C02"],
  "nav.schemes": ["Schemes", "\u092F\u094B\u091C\u0928\u093E\u090F\u0901", "\u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41"],
  "mod.profit_comparison": ["Profit comparison", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E \u0924\u0941\u0932\u0928\u093E", "\u0C32\u0C3E\u0C2D\u0C02 \u0C2A\u0C4B\u0C32\u0C3F\u0C15"],
  "dash.m5": ["See which crop earns the most money (yield x price).", "\u0926\u0947\u0916\u0947\u0902 \u0915\u094C\u0928 \u0938\u0940 \u092B\u0938\u0932 \u0938\u092C\u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0915\u092E\u093E\u0908 \u0926\u0947\u0924\u0940 \u0939\u0948 (\u0909\u092A\u091C x \u092D\u093E\u0935)\u0964", "\u0C0F \u0C2A\u0C02\u0C1F \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C07\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C4B \u0C1A\u0C42\u0C21\u0C02\u0C21\u0C3F (\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F x \u0C27\u0C30)."],
  "dash.m6": ["Government schemes you can use: PM-KISAN, crop insurance and more.", "\u0906\u092A \u091C\u093F\u0928 \u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u0913\u0902 \u0915\u093E \u0932\u093E\u092D \u0932\u0947 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902: \u092A\u0940\u090F\u092E-\u0915\u093F\u0938\u093E\u0928, \u092B\u0938\u0932 \u092C\u0940\u092E\u093E \u0914\u0930 \u0905\u0928\u094D\u092F\u0964", "\u0C2E\u0C40\u0C30\u0C41 \u0C35\u0C3E\u0C21\u0C41\u0C15\u0C4B\u0C17\u0C32 \u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41: \u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D, \u0C2A\u0C02\u0C1F \u0C2C\u0C40\u0C2E\u0C3E \u0C2E\u0C30\u0C3F\u0C2F\u0C41 \u0C2E\u0C30\u0C3F\u0C28\u0C4D\u0C28\u0C3F."],

  "profit.title": ["Profit Mode", "\u092E\u0941\u0928\u093E\u092B\u093C\u093E \u092E\u094B\u0921", "\u0C32\u0C3E\u0C2D\u0C02 \u0C2E\u0C4B\u0C21\u0C4D"],
  "profit.sub": ["Which crop will earn me the most money? Expected yield x market price, side by side.", "\u0915\u094C\u0928 \u0938\u0940 \u092B\u0938\u0932 \u092E\u0941\u091D\u0947 \u0938\u092C\u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0915\u092E\u093E\u0908 \u0926\u0947\u0917\u0940? \u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0909\u092A\u091C x \u092C\u093E\u091C\u093C\u093E\u0930 \u092D\u093E\u0935, \u0938\u093E\u0925-\u0938\u093E\u0925\u0964", "\u0C0F \u0C2A\u0C02\u0C1F \u0C28\u0C3E\u0C15\u0C41 \u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C07\u0C38\u0C4D\u0C24\u0C41\u0C02\u0C26\u0C3F? \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F x \u0C2E\u0C3E\u0C30\u0C4D\u0C15\u0C46\u0C1F\u0C4D \u0C27\u0C30, \u0C2A\u0C15\u0C4D\u0C15\u0C2A\u0C15\u0C4D\u0C15\u0C28\u0C47."],
  "profit.farm": ["Your farm", "\u0906\u092A\u0915\u093E \u0916\u0947\u0924", "\u0C2E\u0C40 \u0C2A\u0C4A\u0C32\u0C02"],
  "profit.area": ["Land area", "\u091C\u093C\u092E\u0940\u0928 \u0915\u093E \u0915\u094D\u0937\u0947\u0924\u094D\u0930\u092B\u0932", "\u0C2D\u0C42\u0C2E\u0C3F \u0C35\u0C3F\u0C38\u0C4D\u0C24\u0C40\u0C30\u0C4D\u0C23\u0C02"],
  "profit.acre": ["Acres", "\u090F\u0915\u0921\u093C", "\u0C0E\u0C15\u0C30\u0C3E\u0C32\u0C41"],
  "profit.hectare": ["Hectares", "\u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930", "\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C4D\u0C32\u0C41"],
  "profit.crops": ["Crops to compare", "\u0924\u0941\u0932\u0928\u093E \u0915\u0947 \u0932\u093F\u090F \u092B\u0938\u0932\u0947\u0902", "\u0C2A\u0C4B\u0C32\u0C4D\u0C1A\u0C3E\u0C32\u0C4D\u0C38\u0C3F\u0C28 \u0C2A\u0C02\u0C1F\u0C32\u0C41"],
  "profit.cropsHint": ["These are crops really grown in your district and season. Remove or add crops.", "\u092F\u0947 \u0906\u092A\u0915\u0947 \u091C\u093C\u093F\u0932\u0947 \u0914\u0930 \u092E\u094C\u0938\u092E \u092E\u0947\u0902 \u0935\u093E\u0938\u094D\u0924\u0935 \u092E\u0947\u0902 \u0909\u0917\u093E\u0908 \u091C\u093E\u0928\u0947 \u0935\u093E\u0932\u0940 \u092B\u0938\u0932\u0947\u0902 \u0939\u0948\u0902\u0964 \u092B\u0938\u0932\u0947\u0902 \u0939\u091F\u093E\u090F\u0901 \u092F\u093E \u091C\u094B\u0921\u093C\u0947\u0902\u0964", "\u0C07\u0C35\u0C3F \u0C2E\u0C40 \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E, \u0C38\u0C40\u0C1C\u0C28\u0C4D\u200C\u0C32\u0C4B \u0C28\u0C3F\u0C1C\u0C02\u0C17\u0C3E \u0C2A\u0C02\u0C21\u0C47 \u0C2A\u0C02\u0C1F\u0C32\u0C41. \u0C2A\u0C02\u0C1F\u0C32\u0C28\u0C41 \u0C24\u0C40\u0C38\u0C3F\u0C35\u0C47\u0C2F\u0C02\u0C21\u0C3F \u0C32\u0C47\u0C26\u0C3E \u0C1C\u0C4B\u0C21\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F."],
  "profit.addCrop": ["Add a crop", "\u092B\u0938\u0932 \u091C\u094B\u0921\u093C\u0947\u0902", "\u0C2A\u0C02\u0C1F \u0C1C\u0C4B\u0C21\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F"],
  "profit.noCrops": ["Select state, district and season to see crops.", "\u092B\u0938\u0932\u0947\u0902 \u0926\u0947\u0916\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u0930\u093E\u091C\u094D\u092F, \u091C\u093C\u093F\u0932\u093E \u0914\u0930 \u092E\u094C\u0938\u092E \u091A\u0941\u0928\u0947\u0902\u0964", "\u0C2A\u0C02\u0C1F\u0C32\u0C41 \u0C1A\u0C42\u0C21\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C02, \u0C1C\u0C3F\u0C32\u0C4D\u0C32\u0C3E, \u0C38\u0C40\u0C1C\u0C28\u0C4D \u0C0E\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."],
  "profit.btn": ["Find the best crop for income", "\u0938\u092C\u0938\u0947 \u091C\u093C\u094D\u092F\u093E\u0926\u093E \u0906\u092F \u0935\u093E\u0932\u0940 \u092B\u0938\u0932 \u0916\u094B\u091C\u0947\u0902", "\u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C07\u0C1A\u0C4D\u0C1A\u0C47 \u0C2A\u0C02\u0C1F\u0C28\u0C41 \u0C15\u0C28\u0C41\u0C17\u0C4A\u0C28\u0C02\u0C21\u0C3F"],
  "profit.working": ["Calculating\u2026", "\u0917\u0923\u0928\u093E \u0939\u094B \u0930\u0939\u0940 \u0939\u0948\u2026", "\u0C32\u0C46\u0C15\u0C4D\u0C15\u0C3F\u0C38\u0C4D\u0C24\u0C4B\u0C02\u0C26\u0C3F\u2026"],
  "profit.recalc": ["Recalculate with my prices and costs", "\u092E\u0947\u0930\u0947 \u092D\u093E\u0935 \u0914\u0930 \u0932\u093E\u0917\u0924 \u0938\u0947 \u0926\u094B\u092C\u093E\u0930\u093E \u0917\u0923\u0928\u093E \u0915\u0930\u0947\u0902", "\u0C28\u0C3E \u0C27\u0C30\u0C32\u0C41, \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C24\u0C4B \u0C2E\u0C33\u0C4D\u0C32\u0C40 \u0C32\u0C46\u0C15\u0C4D\u0C15\u0C3F\u0C02\u0C1A\u0C02\u0C21\u0C3F"],
  "profit.couldNot": ["Could not compare crops", "\u092B\u0938\u0932\u094B\u0902 \u0915\u0940 \u0924\u0941\u0932\u0928\u093E \u0928\u0939\u0940\u0902 \u0939\u094B \u0938\u0915\u0940", "\u0C2A\u0C02\u0C1F\u0C32\u0C28\u0C41 \u0C2A\u0C4B\u0C32\u0C4D\u0C1A\u0C32\u0C47\u0C15\u0C2A\u0C4B\u0C2F\u0C3E\u0C02"],
  "profit.best": ["Highest income", "\u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0906\u092F", "\u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02"],
  "profit.bestNet": ["Highest net profit", "\u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E", "\u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02"],
  "profit.yield": ["Yield (t/ha)", "\u0909\u092A\u091C (\u091F\u0928/\u0939\u0947.)", "\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F (\u0C1F\u0C28\u0C4D/\u0C39\u0C46.)"],
  "profit.prod": ["Production (quintals)", "\u0909\u0924\u094D\u092A\u093E\u0926\u0928 (\u0915\u094D\u0935\u093F\u0902\u091F\u0932)", "\u0C09\u0C24\u0C4D\u0C2A\u0C24\u0C4D\u0C24\u0C3F (\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C33\u0C4D\u0C32\u0C41)"],
  "profit.price": ["Price (Rs per quintal)", "\u092D\u093E\u0935 (\u20B9 \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932)", "\u0C27\u0C30 (\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9)"],
  "profit.cost": ["Your cost per {unit} (Rs)", "\u092A\u094D\u0930\u0924\u093F {unit} \u0906\u092A\u0915\u0940 \u0932\u093E\u0917\u0924 (\u20B9)", "{unit}\u0C15\u0C41 \u0C2E\u0C40 \u0C16\u0C30\u0C4D\u0C1A\u0C41 (\u20B9)"],
  "profit.income": ["Income (Rs)", "\u0906\u092F (\u20B9)", "\u0C06\u0C26\u0C3E\u0C2F\u0C02 (\u20B9)"],
  "profit.net": ["Net profit (Rs)", "\u0936\u0941\u0926\u094D\u0927 \u092E\u0941\u0928\u093E\u092B\u093C\u093E (\u20B9)", "\u0C28\u0C3F\u0C15\u0C30 \u0C32\u0C3E\u0C2D\u0C02 (\u20B9)"],
  "profit.crop": ["Crop", "\u092B\u0938\u0932", "\u0C2A\u0C02\u0C1F"],
  "profit.srcTyped": ["your price", "\u0906\u092A\u0915\u093E \u092D\u093E\u0935", "\u0C2E\u0C40\u0C30\u0C41 \u0C07\u0C1A\u0C4D\u0C1A\u0C3F\u0C28 \u0C27\u0C30"],
  "profit.srcLive": ["live mandi price {date}", "\u092E\u0902\u0921\u0940 \u092D\u093E\u0935 {date}", "\u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30 {date}"],
  "profit.needPrice": ["type price", "\u092D\u093E\u0935 \u0932\u093F\u0916\u0947\u0902", "\u0C27\u0C30 \u0C07\u0C35\u0C4D\u0C35\u0C02\u0C21\u0C3F"],
  "profit.liveOn": ["Live mandi prices are ON (Agmarknet). You can still type your own price.", "\u0932\u093E\u0907\u0935 \u092E\u0902\u0921\u0940 \u092D\u093E\u0935 \u091A\u093E\u0932\u0942 \u0939\u0948\u0902 (Agmarknet)\u0964 \u0906\u092A \u0905\u092A\u0928\u093E \u092D\u093E\u0935 \u092D\u0940 \u0932\u093F\u0916 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902\u0964", "\u0C32\u0C48\u0C35\u0C4D \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\u0C32\u0C41 \u0C06\u0C28\u0C4D\u200C\u0C32\u0C4B \u0C09\u0C28\u0C4D\u0C28\u0C3E\u0C2F\u0C3F (Agmarknet). \u0C2E\u0C40\u0C30\u0C41 \u0C2E\u0C40 \u0C27\u0C30\u0C28\u0C41 \u0C15\u0C42\u0C21\u0C3E \u0C07\u0C35\u0C4D\u0C35\u0C35\u0C1A\u0C4D\u0C1A\u0C41."],
  "profit.liveOff": ["Live mandi prices are off. Type today's price from your mandi in the table. (Developer: add a free DATA_GOV_API_KEY in backend/.env to turn them on.)", "\u0932\u093E\u0907\u0935 \u092E\u0902\u0921\u0940 \u092D\u093E\u0935 \u092C\u0902\u0926 \u0939\u0948\u0902\u0964 \u0905\u092A\u0928\u0940 \u092E\u0902\u0921\u0940 \u0915\u093E \u0906\u091C \u0915\u093E \u092D\u093E\u0935 \u0924\u093E\u0932\u093F\u0915\u093E \u092E\u0947\u0902 \u0932\u093F\u0916\u0947\u0902\u0964 (\u0921\u0947\u0935\u0932\u092A\u0930: \u091A\u093E\u0932\u0942 \u0915\u0930\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F backend/.env \u092E\u0947\u0902 \u092E\u0941\u092B\u093C\u094D\u0924 DATA_GOV_API_KEY \u0921\u093E\u0932\u0947\u0902\u0964)", "\u0C32\u0C48\u0C35\u0C4D \u0C2E\u0C02\u0C21\u0C3F \u0C27\u0C30\u0C32\u0C41 \u0C06\u0C2B\u0C4D\u200C\u0C32\u0C4B \u0C09\u0C28\u0C4D\u0C28\u0C3E\u0C2F\u0C3F. \u0C2E\u0C40 \u0C2E\u0C02\u0C21\u0C3F\u0C32\u0C4B\u0C28\u0C3F \u0C08 \u0C30\u0C4B\u0C1C\u0C41 \u0C27\u0C30\u0C28\u0C41 \u0C2A\u0C1F\u0C4D\u0C1F\u0C3F\u0C15\u0C32\u0C4B \u0C07\u0C35\u0C4D\u0C35\u0C02\u0C21\u0C3F. (\u0C21\u0C46\u0C35\u0C32\u0C2A\u0C30\u0C4D: \u0C06\u0C28\u0C4D \u0C1A\u0C47\u0C2F\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F backend/.env \u0C32\u0C4B \u0C09\u0C1A\u0C3F\u0C24 DATA_GOV_API_KEY \u0C2A\u0C46\u0C1F\u0C4D\u0C1F\u0C02\u0C21\u0C3F.)"],
  "profit.estimateBadge": ["Estimate: costs not included", "\u0905\u0928\u0941\u092E\u093E\u0928: \u0932\u093E\u0917\u0924 \u0936\u093E\u092E\u093F\u0932 \u0928\u0939\u0940\u0902", "\u0C05\u0C02\u0C1A\u0C28\u0C3E: \u0C16\u0C30\u0C4D\u0C1A\u0C41\u0C32\u0C41 \u0C15\u0C32\u0C2A\u0C32\u0C47\u0C26\u0C41"],
  "profit.notesTitle": ["Please read", "\u0915\u0943\u092A\u092F\u093E \u092A\u0922\u093C\u0947\u0902", "\u0C26\u0C2F\u0C1A\u0C47\u0C38\u0C3F \u0C1A\u0C26\u0C35\u0C02\u0C21\u0C3F"],
  "profit.speak": ["The crop with the highest expected income is {crop}, about {inc} rupees. This is only an estimate.", "\u0938\u092C\u0938\u0947 \u0905\u0927\u093F\u0915 \u0905\u092A\u0947\u0915\u094D\u0937\u093F\u0924 \u0906\u092F \u0935\u093E\u0932\u0940 \u092B\u0938\u0932 {crop} \u0939\u0948, \u0932\u0917\u092D\u0917 {inc} \u0930\u0941\u092A\u092F\u0947\u0964 \u092F\u0939 \u0915\u0947\u0935\u0932 \u0905\u0928\u0941\u092E\u093E\u0928 \u0939\u0948\u0964", "\u0C0E\u0C15\u0C4D\u0C15\u0C41\u0C35 \u0C06\u0C26\u0C3E\u0C2F\u0C02 \u0C35\u0C1A\u0C4D\u0C1A\u0C47 \u0C2A\u0C02\u0C1F {crop}, \u0C38\u0C41\u0C2E\u0C3E\u0C30\u0C41 {inc} \u0C30\u0C42\u0C2A\u0C3E\u0C2F\u0C32\u0C41. \u0C07\u0C26\u0C3F \u0C05\u0C02\u0C1A\u0C28\u0C3E \u0C2E\u0C3E\u0C24\u0C4D\u0C30\u0C2E\u0C47."],
  "profit.example": ["Use example", "\u0909\u0926\u093E\u0939\u0930\u0923 \u092D\u0930\u0947\u0902", "\u0C09\u0C26\u0C3E\u0C39\u0C30\u0C23 \u0C28\u0C3F\u0C02\u0C2A\u0C02\u0C21\u0C3F"],

  "sch.title": ["Government Schemes", "\u0938\u0930\u0915\u093E\u0930\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901", "\u0C2A\u0C4D\u0C30\u0C2D\u0C41\u0C24\u0C4D\u0C35 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41"],
  "sch.sub": ["Schemes such as PM-KISAN and crop insurance that you can use, with how to apply.", "\u092A\u0940\u090F\u092E-\u0915\u093F\u0938\u093E\u0928 \u0914\u0930 \u092B\u0938\u0932 \u092C\u0940\u092E\u093E \u091C\u0948\u0938\u0940 \u092F\u094B\u091C\u0928\u093E\u090F\u0901 \u091C\u093F\u0928\u0915\u093E \u0906\u092A \u0932\u093E\u092D \u0932\u0947 \u0938\u0915\u0924\u0947 \u0939\u0948\u0902, \u0906\u0935\u0947\u0926\u0928 \u0915\u0947 \u0924\u0930\u0940\u0915\u0947 \u0915\u0947 \u0938\u093E\u0925\u0964", "\u0C2A\u0C40\u0C0E\u0C02-\u0C15\u0C3F\u0C38\u0C3E\u0C28\u0C4D, \u0C2A\u0C02\u0C1F \u0C2C\u0C40\u0C2E\u0C3E \u0C35\u0C02\u0C1F\u0C3F \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41, \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C38\u0C47 \u0C35\u0C3F\u0C27\u0C3E\u0C28\u0C02\u0C24\u0C4B."],
  "sch.pick": ["Choose your state and crop (optional) to see schemes that fit you.", "\u0905\u092A\u0928\u0947 \u0905\u0928\u0941\u0915\u0942\u0932 \u092F\u094B\u091C\u0928\u093E\u090F\u0901 \u0926\u0947\u0916\u0928\u0947 \u0915\u0947 \u0932\u093F\u090F \u0930\u093E\u091C\u094D\u092F \u0914\u0930 \u092B\u0938\u0932 (\u0935\u0948\u0915\u0932\u094D\u092A\u093F\u0915) \u091A\u0941\u0928\u0947\u0902\u0964", "\u0C2E\u0C40\u0C15\u0C41 \u0C38\u0C30\u0C3F\u0C2A\u0C4B\u0C2F\u0C47 \u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41 \u0C1A\u0C42\u0C21\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C02, \u0C2A\u0C02\u0C1F (\u0C10\u0C1A\u0C4D\u0C1B\u0C3F\u0C15\u0C02) \u0C0E\u0C02\u0C1A\u0C41\u0C15\u0C4B\u0C02\u0C21\u0C3F."],
  "sch.how": ["How to apply", "\u0906\u0935\u0947\u0926\u0928 \u0915\u0948\u0938\u0947 \u0915\u0930\u0947\u0902", "\u0C0E\u0C32\u0C3E \u0C26\u0C30\u0C16\u0C3E\u0C38\u0C4D\u0C24\u0C41 \u0C1A\u0C47\u0C2F\u0C3E\u0C32\u0C3F"],
  "sch.where": ["More info", "\u0905\u0927\u093F\u0915 \u091C\u093E\u0928\u0915\u093E\u0930\u0940", "\u0C2E\u0C30\u0C3F\u0C02\u0C24 \u0C38\u0C2E\u0C3E\u0C1A\u0C3E\u0C30\u0C02"],
  "sch.forYou": ["For your crop", "\u0906\u092A\u0915\u0940 \u092B\u0938\u0932 \u0915\u0947 \u0932\u093F\u090F", "\u0C2E\u0C40 \u0C2A\u0C02\u0C1F\u0C15\u0C41"],
  "sch.stateTag": ["Your state", "\u0906\u092A\u0915\u093E \u0930\u093E\u091C\u094D\u092F", "\u0C2E\u0C40 \u0C30\u0C3E\u0C37\u0C4D\u0C1F\u0C4D\u0C30\u0C02"],
  "sch.loading": ["Loading schemes\u2026", "\u092F\u094B\u091C\u0928\u093E\u090F\u0901 \u0932\u094B\u0921 \u0939\u094B \u0930\u0939\u0940 \u0939\u0948\u0902\u2026", "\u0C2A\u0C25\u0C15\u0C3E\u0C32\u0C41 \u0C32\u0C4B\u0C21\u0C4D \u0C05\u0C35\u0C41\u0C24\u0C41\u0C28\u0C4D\u0C28\u0C3E\u0C2F\u0C3F\u2026"],

  "fb.q": ["Was this right?", "\u0915\u094D\u092F\u093E \u092F\u0939 \u0938\u0939\u0940 \u0925\u093E?", "\u0C07\u0C26\u0C3F \u0C38\u0C30\u0C48\u0C28\u0C26\u0C47\u0C28\u0C3E?"],
  "fb.sub": ["Your answer helps us measure how accurate GeoYield really is on real farms.", "\u0906\u092A\u0915\u093E \u091C\u0935\u093E\u092C \u0939\u092E\u0947\u0902 \u0905\u0938\u0932\u0940 \u0916\u0947\u0924\u094B\u0902 \u092A\u0930 GeoYield \u0915\u0940 \u0938\u091F\u0940\u0915\u0924\u093E \u092E\u093E\u092A\u0928\u0947 \u092E\u0947\u0902 \u092E\u0926\u0926 \u0915\u0930\u0924\u093E \u0939\u0948\u0964", "\u0C2E\u0C40 \u0C38\u0C2E\u0C3E\u0C27\u0C3E\u0C28\u0C02 \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C2A\u0C4A\u0C32\u0C3E\u0C32\u0C4D\u0C32\u0C4B GeoYield \u0C0E\u0C02\u0C24 \u0C16\u0C1A\u0C4D\u0C1A\u0C3F\u0C24\u0C2E\u0C4B \u0C15\u0C4A\u0C32\u0C35\u0C21\u0C3E\u0C28\u0C3F\u0C15\u0C3F \u0C38\u0C39\u0C3E\u0C2F\u0C2A\u0C21\u0C41\u0C24\u0C41\u0C02\u0C26\u0C3F."],
  "fb.yes": ["Yes, right", "\u0939\u093E\u0901, \u0938\u0939\u0940", "\u0C05\u0C35\u0C41\u0C28\u0C41, \u0C38\u0C30\u0C48\u0C28\u0C26\u0C47"],
  "fb.no": ["No, wrong", "\u0928\u0939\u0940\u0902, \u0917\u093C\u0932\u0924", "\u0C15\u0C3E\u0C26\u0C41, \u0C24\u0C2A\u0C4D\u0C2A\u0C41"],
  "fb.actualYield": ["Real yield you got (tonnes per hectare, optional)", "\u0906\u092A\u0915\u094B \u092E\u093F\u0932\u0940 \u0905\u0938\u0932\u0940 \u0909\u092A\u091C (\u091F\u0928 \u092A\u094D\u0930\u0924\u093F \u0939\u0947\u0915\u094D\u091F\u0947\u092F\u0930, \u0935\u0948\u0915\u0932\u094D\u092A\u093F\u0915)", "\u0C2E\u0C40\u0C15\u0C41 \u0C35\u0C1A\u0C4D\u0C1A\u0C3F\u0C28 \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F (\u0C39\u0C46\u0C15\u0C4D\u0C1F\u0C3E\u0C30\u0C41\u0C15\u0C41 \u0C1F\u0C28\u0C4D\u0C28\u0C41\u0C32\u0C41, \u0C10\u0C1A\u0C4D\u0C1B\u0C3F\u0C15\u0C02)"],
  "fb.actualCrop": ["Crop you actually grew (optional)", "\u091C\u094B \u092B\u0938\u0932 \u0906\u092A\u0928\u0947 \u0905\u0938\u0932 \u092E\u0947\u0902 \u0909\u0917\u093E\u0908 (\u0935\u0948\u0915\u0932\u094D\u092A\u093F\u0915)", "\u0C2E\u0C40\u0C30\u0C41 \u0C28\u0C3F\u0C1C\u0C02\u0C17\u0C3E \u0C2A\u0C02\u0C21\u0C3F\u0C02\u0C1A\u0C3F\u0C28 \u0C2A\u0C02\u0C1F (\u0C10\u0C1A\u0C4D\u0C1B\u0C3F\u0C15\u0C02)"],
  "fb.actualPrice": ["Price you really got (Rs per quintal, optional)", "\u0906\u092A\u0915\u094B \u0905\u0938\u0932 \u092E\u0947\u0902 \u092E\u093F\u0932\u093E \u092D\u093E\u0935 (\u20B9 \u092A\u094D\u0930\u0924\u093F \u0915\u094D\u0935\u093F\u0902\u091F\u0932, \u0935\u0948\u0915\u0932\u094D\u092A\u093F\u0915)", "\u0C2E\u0C40\u0C15\u0C41 \u0C28\u0C3F\u0C1C\u0C02\u0C17\u0C3E \u0C35\u0C1A\u0C4D\u0C1A\u0C3F\u0C28 \u0C27\u0C30 (\u0C15\u0C4D\u0C35\u0C3F\u0C02\u0C1F\u0C3E\u0C32\u0C41\u0C15\u0C41 \u20B9, \u0C10\u0C1A\u0C4D\u0C1B\u0C3F\u0C15\u0C02)"],
  "fb.comment": ["Comment (optional)", "\u091F\u093F\u092A\u094D\u092A\u0923\u0940 (\u0935\u0948\u0915\u0932\u094D\u092A\u093F\u0915)", "\u0C35\u0C4D\u0C2F\u0C3E\u0C16\u0C4D\u0C2F (\u0C10\u0C1A\u0C4D\u0C1B\u0C3F\u0C15\u0C02)"],
  "fb.send": ["Send", "\u092D\u0947\u091C\u0947\u0902", "\u0C2A\u0C02\u0C2A\u0C02\u0C21\u0C3F"],
  "fb.thanks": ["Thank you! Your answer was saved.", "\u0927\u0928\u094D\u092F\u0935\u093E\u0926! \u0906\u092A\u0915\u093E \u091C\u0935\u093E\u092C \u0938\u0939\u0947\u091C \u0932\u093F\u092F\u093E \u0917\u092F\u093E\u0964", "\u0C27\u0C28\u0C4D\u0C2F\u0C35\u0C3E\u0C26\u0C3E\u0C32\u0C41! \u0C2E\u0C40 \u0C38\u0C2E\u0C3E\u0C27\u0C3E\u0C28\u0C02 \u0C38\u0C47\u0C35\u0C4D \u0C05\u0C2F\u0C3F\u0C02\u0C26\u0C3F."],
  "fb.err": ["Could not save your answer", "\u0906\u092A\u0915\u093E \u091C\u0935\u093E\u092C \u0938\u0939\u0947\u091C\u093E \u0928\u0939\u0940\u0902 \u091C\u093E \u0938\u0915\u093E", "\u0C2E\u0C40 \u0C38\u0C2E\u0C3E\u0C27\u0C3E\u0C28\u0C02 \u0C38\u0C47\u0C35\u0C4D \u0C15\u0C3E\u0C32\u0C47\u0C26\u0C41"],
  "dash.real": ["Real-world accuracy (from farmer feedback)", "\u0905\u0938\u0932\u0940 \u0926\u0941\u0928\u093F\u092F\u093E \u092E\u0947\u0902 \u0938\u091F\u0940\u0915\u0924\u093E (\u0915\u093F\u0938\u093E\u0928\u094B\u0902 \u0915\u0940 \u092A\u094D\u0930\u0924\u093F\u0915\u094D\u0930\u093F\u092F\u093E \u0938\u0947)", "\u0C28\u0C3F\u0C1C \u0C2A\u0C4D\u0C30\u0C2A\u0C02\u0C1A \u0C16\u0C1A\u0C4D\u0C1A\u0C3F\u0C24\u0C24\u0C4D\u0C35\u0C02 (\u0C30\u0C48\u0C24\u0C41\u0C32 \u0C2B\u0C40\u0C21\u0C4D\u200C\u0C2C\u0C4D\u0C2F\u0C3E\u0C15\u0C4D \u0C06\u0C27\u0C3E\u0C30\u0C02\u0C17\u0C3E)"],
  "dash.realNone": ["No feedback yet. Use the 'Was this right?' button under a result.", "\u0905\u092D\u0940 \u0915\u094B\u0908 \u092A\u094D\u0930\u0924\u093F\u0915\u094D\u0930\u093F\u092F\u093E \u0928\u0939\u0940\u0902\u0964 \u092A\u0930\u093F\u0923\u093E\u092E \u0915\u0947 \u0928\u0940\u091A\u0947 '\u0915\u094D\u092F\u093E \u092F\u0939 \u0938\u0939\u0940 \u0925\u093E?' \u092C\u091F\u0928 \u0926\u092C\u093E\u090F\u0901\u0964", "\u0C07\u0C02\u0C15\u0C3E \u0C2B\u0C40\u0C21\u0C4D\u200C\u0C2C\u0C4D\u0C2F\u0C3E\u0C15\u0C4D \u0C32\u0C47\u0C26\u0C41. \u0C2B\u0C32\u0C3F\u0C24\u0C02 \u0C15\u0C3F\u0C02\u0C26 '\u0C07\u0C26\u0C3F \u0C38\u0C30\u0C48\u0C28\u0C26\u0C47\u0C28\u0C3E?' \u0C2C\u0C1F\u0C28\u0C4D \u0C35\u0C3E\u0C21\u0C02\u0C21\u0C3F."],
  "dash.realRight": ["{n} answers, {p}% said right", "{n} \u091C\u0935\u093E\u092C, {p}% \u0928\u0947 \u0938\u0939\u0940 \u0915\u0939\u093E", "{n} \u0C38\u0C2E\u0C3E\u0C27\u0C3E\u0C28\u0C3E\u0C32\u0C41, {p}% \u0C38\u0C30\u0C48\u0C28\u0C26\u0C28\u0C4D\u0C28\u0C3E\u0C30\u0C41"],
  "dash.realYield": ["Yield: average error {e}% from {n} real farms ({w}% within 20%)", "\u0909\u092A\u091C: {n} \u0905\u0938\u0932\u0940 \u0916\u0947\u0924\u094B\u0902 \u092A\u0930 \u0914\u0938\u0924 \u0924\u094D\u0930\u0941\u091F\u093F {e}% ({w}% 20% \u0915\u0947 \u092D\u0940\u0924\u0930)", "\u0C26\u0C3F\u0C17\u0C41\u0C2C\u0C21\u0C3F: {n} \u0C28\u0C3F\u0C1C\u0C2E\u0C48\u0C28 \u0C2A\u0C4A\u0C32\u0C3E\u0C32\u0C4D\u0C32\u0C4B \u0C38\u0C17\u0C1F\u0C41 \u0C24\u0C2A\u0C4D\u0C2A\u0C41 {e}% ({w}% 20% \u0C32\u0C4B\u0C2A\u0C41)"],
};

for (const [k, v] of Object.entries(UP_T)) {
  if (v.length !== 3) throw new Error("Translation entry needs 3 languages: " + k);
  translations.en[k] = v[0]; translations.hi[k] = v[1]; translations.te[k] = v[2];
}
'@
Save-File "frontend\src\i18n\translations_upgrade.js" $c

$c = @'
import { useState } from "react";
import { api } from "../services/api.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { Alert } from "./ui.jsx";

/** "Was this right?" box. kind: "yield" | "crop" | "profit" decides which real value we ask for. */
export default function FeedbackBox({ module, historyId, kind }) {
  const { t } = useLang();
  const [choice, setChoice] = useState(null);
  const [actual, setActual] = useState("");
  const [comment, setComment] = useState("");
  const [state, setState] = useState("idle"); // idle | sending | done
  const [error, setError] = useState("");
  if (!historyId) return null;

  async function send() {
    setState("sending"); setError("");
    const body = { module, history_id: historyId, correct: choice };
    if (comment.trim()) body.comment = comment.trim();
    if (actual.trim() !== "") {
      if (kind === "yield") body.actual_yield = Number(actual);
      else if (kind === "profit") body.actual_price = Number(actual);
      else body.actual_crop = actual.trim();
    }
    try { await api.sendFeedback(body); setState("done"); }
    catch (e) { setError(e.message); setState("idle"); }
  }

  const label = kind === "yield" ? t("fb.actualYield") : kind === "profit" ? t("fb.actualPrice") : t("fb.actualCrop");
  return (
    <div className="card feedback">
      <h4>{t("fb.q")}</h4>
      <p className="muted small">{t("fb.sub")}</p>
      {state === "done" ? <Alert kind="info">{t("fb.thanks")}</Alert> : (
        <>
          <div className="btn-row">
            <button type="button" className={"btn " + (choice === true ? "primary" : "outline")} onClick={() => setChoice(true)}>{"\u{1F44D} "}{t("fb.yes")}</button>
            <button type="button" className={"btn " + (choice === false ? "primary" : "outline")} onClick={() => setChoice(false)}>{"\u{1F44E} "}{t("fb.no")}</button>
          </div>
          {choice !== null && (
            <div className="fb-more">
              <label className="field">
                <span className="label">{label}</span>
                <input type={kind === "crop" ? "text" : "number"} min="0" step="any" value={actual} onChange={(e) => setActual(e.target.value)} />
              </label>
              <label className="field">
                <span className="label">{t("fb.comment")}</span>
                <input type="text" maxLength={500} value={comment} onChange={(e) => setComment(e.target.value)} />
              </label>
              <button type="button" className="btn primary" disabled={state === "sending"} onClick={send}>{t("fb.send")}</button>
            </div>
          )}
          <Alert title={t("fb.err")}>{error}</Alert>
        </>
      )}
    </div>
  );
}
'@
Save-File "frontend\src\components\FeedbackBox.jsx" $c

$c = @'
import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Spinner, List, Badge, SpeakButton } from "../components/ui.jsx";
import FeedbackBox from "../components/FeedbackBox.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";

const SEASON_KEY = { Kharif: "season.kharif", Rabi: "season.rabi", Summer: "season.summer", "Whole Year": "season.whole", Autumn: "season.autumn", Winter: "season.winter" };
const INIT = { state: "", district: "", season: "", area: "1", area_unit: "acre" };
const pretty = (s) => s.charAt(0) + s.slice(1).toLowerCase();
const RS = "\u20B9";
const money = (n) => (n === null || n === undefined ? "-" : RS + Number(n).toLocaleString("en-IN"));
const onlyNumbers = (obj) => Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== "" && !Number.isNaN(Number(v))).map(([k, v]) => [k, Number(v)]));

export default function ProfitMode() {
  const { t } = useLang();
  const [v, setV] = useState(INIT);
  const [opts, setOpts] = useState({ crops: [], seasons: [], states: [], districts: {} });
  const [crops, setCrops] = useState([]);
  const [allCrops, setAllCrops] = useState([]);
  const [live, setLive] = useState(false);
  const [prices, setPrices] = useState({});
  const [costs, setCosts] = useState({});
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  const hid = useRef(null);
  if (res?.history_id) hid.current = res.history_id;

  useEffect(() => { api.yieldOptions().then(setOpts).catch((e) => setError(e.message)); }, []);
  // when state / district / season change, load the crops really grown there
  useEffect(() => {
    if (!v.state || !v.season) { setCrops([]); return; }
    api.profitOptions(v.state, v.district, v.season)
      .then((r) => { setCrops(r.candidates); setAllCrops(r.all_crops); setLive(r.live_prices_enabled); })
      .catch((e) => setError(e.message));
  }, [v.state, v.district, v.season]);

  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const districts = opts.districts[v.state] || [];
  const unitLabel = t(v.area_unit === "acre" ? "profit.acre" : "profit.hectare").toLowerCase();

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); setPrices({}); setCosts({}); setCrops([]); hid.current = null; lastRun.current = null; }, []);
  useRelang(lastRun, setRes);

  function example() {
    const state = opts.states.includes("Telangana") ? "Telangana" : opts.states[0] || "";
    setV({ ...INIT, state, district: (opts.districts[state] || [])[0] || "", season: "Kharif", area: "2" });
  }

  async function run() {
    setBusy(true); setError(""); hid.current = null;
    const payload = { state: v.state, district: v.district || undefined, season: v.season, area: Number(v.area),
      area_unit: v.area_unit, crops, prices: onlyNumbers(prices), costs: onlyNumbers(costs) };
    lastRun.current = (re) => api.profitCompare({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); setRes(null); }
    finally { setBusy(false); }
  }
  const submit = (e) => { e.preventDefault(); run(); };

  const top = res?.rows?.find((r) => r.rank === 1);
  const speech = top ? t("profit.speak", { crop: top.crop, inc: top.income }) : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon={"\u{1F4B0}"} title={t("profit.title")} subtitle={t("profit.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("profit.farm")}</h3>
          <div className="form-grid">
            <Field label={t("common.state")}>
              <select required value={v.state} onChange={(e) => setV((p) => ({ ...p, state: e.target.value, district: "" }))}>
                <option value="">{t("common.selectState")}</option>{opts.states.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.district")}>
              <select value={v.district} onChange={(e) => set("district")(e.target.value)} disabled={!v.state}>
                <option value="">{v.state ? t("common.selectDistrict") : t("common.selectStateFirst")}</option>
                {districts.map((d) => <option key={d} value={d}>{pretty(d)}</option>)}
              </select>
            </Field>
            <Field label={t("common.season")}>
              <select required value={v.season} onChange={(e) => set("season")(e.target.value)}>
                <option value="">{t("common.select")}</option>{opts.seasons.map((s) => <option key={s} value={s}>{SEASON_KEY[s] ? t(SEASON_KEY[s]) : s}</option>)}
              </select>
            </Field>
            <Field label={t("profit.area")}>
              <div className="inline-pair">
                <NumberInput required min={0.01} value={v.area} onChange={set("area")} />
                <select value={v.area_unit} onChange={(e) => set("area_unit")(e.target.value)}>
                  <option value="acre">{t("profit.acre")}</option><option value="hectare">{t("profit.hectare")}</option>
                </select>
              </div>
            </Field>
          </div>

          <h3>{t("profit.crops")}</h3>
          <p className="muted small">{t("profit.cropsHint")}</p>
          {crops.length === 0 && <p className="muted small">{t("profit.noCrops")}</p>}
          <div className="chips">
            {crops.map((c) => (
              <span className="chip" key={c}>{c}<button type="button" aria-label="remove" onClick={() => setCrops((p) => p.filter((x) => x !== c))}>{"\u00D7"}</button></span>
            ))}
          </div>
          <Field label={t("profit.addCrop")}>
            <select value="" onChange={(e) => e.target.value && setCrops((p) => (p.includes(e.target.value) ? p : [...p, e.target.value]))}>
              <option value="">{t("common.select")}</option>
              {allCrops.filter((c) => !crops.includes(c)).map((c) => <option key={c}>{c}</option>)}
            </select>
          </Field>

          <Alert kind="info">{live ? t("profit.liveOn") : t("profit.liveOff")}</Alert>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy || crops.length === 0}>{busy ? t("profit.working") : t("profit.btn")}</button>
            <button type="button" className="btn outline" onClick={example}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner text={t("profit.working")} />}
          <Alert title={t("profit.couldNot")}>{error}</Alert>
          {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              {top && (
                <div className="card result big">
                  <div className="muted">{res.ranked_by === "net" ? t("profit.bestNet") : t("profit.best")}</div>
                  <div className="big-number">{top.crop}</div>
                  <p><b>{money(res.ranked_by === "net" ? top.net : top.income)}</b> {res.ranked_by !== "net" && <Badge tone="amber">{t("profit.estimateBadge")}</Badge>}</p>
                  <SpeakButton text={speech} />
                </div>
              )}
              <div className="card">
                <div className="table-wrap">
                  <table className="ptable">
                    <thead>
                      <tr>
                        <th>#</th><th>{t("profit.crop")}</th><th>{t("profit.yield")}</th><th>{t("profit.prod")}</th>
                        <th>{t("profit.price")}</th><th>{t("profit.cost", { unit: unitLabel })}</th><th>{t("profit.income")}</th><th>{t("profit.net")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {res.rows.map((r) => (
                        <tr key={r.crop} className={r.rank === 1 ? "top" : ""}>
                          <td>{r.rank || "-"}</td>
                          <td><b>{r.crop}</b>{r.error && <div className="small err">{r.error}</div>}</td>
                          <td>{r.yield_t_per_ha ?? "-"}</td>
                          <td>{r.production_quintals ?? "-"}</td>
                          <td>
                            <input className="cell" type="number" min="0" step="any" placeholder={t("profit.needPrice")}
                              value={prices[r.crop] ?? (r.price ?? "")} onChange={(e) => setPrices((p) => ({ ...p, [r.crop]: e.target.value }))} />
                            <div className="small muted">
                              {r.price_source === "typed" && t("profit.srcTyped")}
                              {r.price_source === "live" && r.live && t("profit.srcLive", { date: r.live.date })}
                            </div>
                          </td>
                          <td>
                            <input className="cell" type="number" min="0" step="any" value={costs[r.crop] ?? ""}
                              onChange={(e) => setCosts((p) => ({ ...p, [r.crop]: e.target.value }))} />
                          </td>
                          <td>{money(r.income)}</td>
                          <td>{money(r.net)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <div className="btn-row mt-s"><button type="button" className="btn outline" disabled={busy} onClick={run}>{t("profit.recalc")}</button></div>
              </div>
              <div className="card">
                <h4>{t("profit.notesTitle")}</h4>
                <List items={res.notes} tone="warn" />
                <Alert kind="warn">{res.disclaimer}</Alert>
              </div>
              {hid.current && <FeedbackBox key={hid.current} module="profit_comparison" historyId={hid.current} kind="profit" />}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
'@
Save-File "frontend\src\pages\ProfitMode.jsx" $c

$c = @'
import { useEffect, useState } from "react";
import { api } from "../services/api.js";
import { PageHeader, Field, Alert, Spinner, Badge } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { STATES } from "../data/locations.js";

export default function Schemes() {
  const { t, lang } = useLang();
  const [state, setState] = useState("");
  const [crop, setCrop] = useState("");
  const [season, setSeason] = useState("");
  const [opts, setOpts] = useState({ crops: [], seasons: [] });
  const [data, setData] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(true);

  useEffect(() => { api.yieldOptions().then(setOpts).catch(() => {}); }, []);
  useEffect(() => {
    setBusy(true); setError("");
    api.schemes(state, crop, season).then(setData).catch((e) => setError(e.message)).finally(() => setBusy(false));
  }, [state, crop, season, lang]);

  return (
    <>
      <PageHeader icon={"\u{1F3DB}\uFE0F"} title={t("sch.title")} subtitle={t("sch.sub")} />
      <div className="container page">
        <div className="card form">
          <p className="muted small">{t("sch.pick")}</p>
          <div className="form-grid three">
            <Field label={t("common.state")}>
              <select value={state} onChange={(e) => setState(e.target.value)}>
                <option value="">{t("common.selectState")}</option>
                {STATES.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.crop")}>
              <select value={crop} onChange={(e) => setCrop(e.target.value)}>
                <option value="">{t("common.select")}</option>
                {opts.crops.map((c) => <option key={c}>{c}</option>)}
              </select>
            </Field>
            <Field label={t("common.season")}>
              <select value={season} onChange={(e) => setSeason(e.target.value)}>
                <option value="">{t("common.select")}</option>
                {["Kharif", "Rabi"].map((s) => <option key={s} value={s}>{t("season." + s.toLowerCase())}</option>)}
              </select>
            </Field>
          </div>
        </div>

        {busy && <Spinner text={t("sch.loading")} />}
        <Alert title={t("common.problem")}>{error}</Alert>
        {data && <Alert kind="warn">{data.note}</Alert>}
        <div className="scheme-grid">
          {data && data.schemes.map((s) => (
            <div className="card scheme" key={s.id}>
              <div className="result-head">
                <h3>{s.name}</h3>
                {s.state_scheme && <Badge tone="green">{t("sch.stateTag")}</Badge>}
              </div>
              {s.relevance && <p className="scheme-rel"><b>{t("sch.forYou")}:</b> {s.relevance}</p>}
              <p>{s.benefit}</p>
              <h4>{t("sch.how")}</h4>
              <p>{s.how}</p>
              <p className="muted small">{t("sch.where")}: {s.link}</p>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}
'@
Save-File "frontend\src\pages\Schemes.jsx" $c

$c = @'
/* Styles for Profit mode, Schemes and the feedback box */
.form-grid.three { grid-template-columns: repeat(3, 1fr); }
.inline-pair { display: flex; gap: .5rem; } .inline-pair input { flex: 1; min-width: 0; } .inline-pair select { width: 8.5rem; }
.chips { display: flex; flex-wrap: wrap; gap: .45rem; margin: .4rem 0 .8rem; }
.chip { display: inline-flex; align-items: center; gap: .35rem; background: var(--green-l); color: var(--green-d); border-radius: 99px; padding: .3rem .4rem .3rem .8rem; font-weight: 600; font-size: .88rem; }
.chip button { border: 0; background: rgba(0,0,0,.08); border-radius: 50%; width: 1.4rem; height: 1.4rem; cursor: pointer; line-height: 1; font-size: 1rem; color: inherit; }
.table-wrap { overflow-x: auto; }
.ptable { width: 100%; border-collapse: collapse; font-size: .88rem; }
.ptable th { text-align: left; font-size: .74rem; color: var(--muted); font-weight: 700; padding: .4rem .5rem; border-bottom: 2px solid var(--line); white-space: nowrap; }
.ptable td { padding: .5rem; border-bottom: 1px solid var(--line); vertical-align: top; }
.ptable tr.top td { background: var(--green-l); }
.ptable input.cell { width: 6.5rem; padding: .35rem .5rem; border: 1.5px solid var(--line); border-radius: 8px; font: inherit; }
.ptable .err { color: var(--red); } .mt-s { margin-top: .8rem; }
.feedback .fb-more { margin-top: .9rem; display: grid; gap: .7rem; max-width: 460px; }
.scheme-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1.1rem; margin-top: 1rem; }
.scheme .scheme-rel { background: var(--green-l); color: var(--green-d); border-radius: 10px; padding: .45rem .7rem; font-size: .9rem; }
.grid.six { grid-template-columns: repeat(3, 1fr); }
@media (max-width: 1250px) { .nav-links a { padding: .45rem .5rem; font-size: .84rem; } }
@media (max-width: 900px) { .scheme-grid, .grid.six { grid-template-columns: 1fr; } .form-grid.three { grid-template-columns: 1fr; } }
'@
Save-File "frontend\src\styles\upgrade.css" $c

$c = @'
import { Routes, Route, Navigate, useLocation } from "react-router-dom";
import { useEffect } from "react";
import Navbar from "./components/Navbar.jsx";
import Footer from "./components/Footer.jsx";
import Landing from "./pages/Landing.jsx";
import Dashboard from "./pages/Dashboard.jsx";
import CropRecommendation from "./pages/CropRecommendation.jsx";
import YieldPrediction from "./pages/YieldPrediction.jsx";
import CropHealth from "./pages/CropHealth.jsx";
import FertilizerEvaluation from "./pages/FertilizerEvaluation.jsx";
import History from "./pages/History.jsx";
import About from "./pages/About.jsx";
import ProfitMode from "./pages/ProfitMode.jsx";
import Schemes from "./pages/Schemes.jsx";
import "./i18n/translations_upgrade.js";
import "./styles/upgrade.css";
import VoiceAssistant from "./voice/VoiceAssistant.jsx";

function ScrollTop() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);
  return null;
}

export default function App() {
  return (
    <>
      <ScrollTop />
      <Navbar />
      <main>
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/crop-recommendation" element={<CropRecommendation />} />
          <Route path="/yield-prediction" element={<YieldPrediction />} />
          <Route path="/crop-health" element={<CropHealth />} />
          <Route path="/fertilizer" element={<FertilizerEvaluation />} />
          <Route path="/profit" element={<ProfitMode />} />
          <Route path="/schemes" element={<Schemes />} />
          <Route path="/history" element={<History />} />
          <Route path="/about" element={<About />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
      <Footer />
      <VoiceAssistant />
    </>
  );
}
'@
Save-File "frontend\src\App.jsx" $c

$c = @'
import { useState } from "react";
import { NavLink, Link } from "react-router-dom";
import Logo from "./Logo.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { LANGS } from "../i18n/translations.js";

const LINKS = [
  ["/dashboard", "nav.dashboard"], ["/crop-recommendation", "nav.crop"], ["/yield-prediction", "nav.yield"],
  ["/crop-health", "nav.health"], ["/fertilizer", "nav.fertilizer"], ["/profit", "nav.profit"], ["/schemes", "nav.schemes"], ["/history", "nav.history"], ["/about", "nav.about"],
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
'@
Save-File "frontend\src\components\Navbar.jsx" $c

$c = @'
export const BASE = import.meta.env.VITE_API_URL || "http://localhost:8000";
let LANG = "en";
const NO_BACKEND = {
  en: "Cannot reach the GeoYield backend. Start it with .\\run-backend.ps1 and check it is running at ",
  hi: "GeoYield \u092C\u0948\u0915\u090F\u0902\u0921 \u0938\u0947 \u0938\u0902\u092A\u0930\u094D\u0915 \u0928\u0939\u0940\u0902 \u0939\u094B \u092A\u093E \u0930\u0939\u093E\u0964 \u0907\u0938\u0947 .\\run-backend.ps1 \u0938\u0947 \u0936\u0941\u0930\u0942 \u0915\u0930\u0947\u0902 \u0914\u0930 \u091C\u093E\u0901\u091A\u0947\u0902 \u0915\u093F \u092F\u0939 \u092F\u0939\u093E\u0901 \u091A\u0932 \u0930\u0939\u093E \u0939\u0948: ",
  te: "GeoYield \u0C2C\u0C4D\u0C2F\u0C3E\u0C15\u0C46\u0C02\u0C21\u0C4D\u200C\u0C28\u0C41 \u0C1A\u0C47\u0C30\u0C41\u0C15\u0C4B\u0C32\u0C47\u0C15\u0C2A\u0C4B\u0C24\u0C41\u0C28\u0C4D\u0C28\u0C3E\u0C02. \u0C26\u0C40\u0C28\u0C4D\u0C28\u0C3F .\\run-backend.ps1 \u0C24\u0C4B \u0C2A\u0C4D\u0C30\u0C3E\u0C30\u0C02\u0C2D\u0C3F\u0C02\u0C1A\u0C3F \u0C07\u0C15\u0C4D\u0C15\u0C21 \u0C28\u0C21\u0C41\u0C38\u0C4D\u0C24\u0C4B\u0C02\u0C26\u0C4B \u0C1A\u0C42\u0C21\u0C02\u0C21\u0C3F: ",
};
export const setApiLang = (l) => { LANG = l; };

async function request(path, options = {}) {
  let res;
  try {
    res = await fetch(`${BASE}${path}`, options);
  } catch {
    throw new Error((NO_BACKEND[LANG] || NO_BACKEND.en) + BASE);
  }
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* empty body */
  }
  if (!res.ok) {
    const d = data?.detail;
    let msg = "Request failed (" + res.status + ")";
    if (typeof d === "string") msg = d;
    else if (Array.isArray(d))
      msg = d.map((e) => `${(e.loc || []).slice(1).join(".")}: ${e.msg}`).join("; ");
    const err = new Error(msg);
    err.status = res.status;
    throw err;
  }
  return data;
}

const json = (body) => ({
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ ...body, lang: LANG }),
});

export const api = {
  status: () => request("/api/status"),
  recommendCrop: (b) => request("/api/crop/recommend", json(b)),
  yieldOptions: () => request("/api/yield/options"),
  predictYield: (b) => request("/api/yield/predict", json(b)),
  healthSymptoms: (b) => request("/api/health/symptoms", json(b)),
  healthImage: (file, crop, relocalize = false) => {
    const fd = new FormData();
    fd.append("file", file);
    const q = `?lang=${LANG}` + (crop ? `&crop=${encodeURIComponent(crop)}` : "") + (relocalize ? "&relocalize=true" : "");
    return request(`/api/health/image${q}`, { method: "POST", body: fd });
  },
  fertilizers: () => request(`/api/fertilizers?lang=${LANG}`),
  problems: () => request(`/api/problems?lang=${LANG}`),
  areaCrops: (state, district, season) => request(`/api/area/crops?state=${encodeURIComponent(state)}`
    + (district ? `&district=${encodeURIComponent(district)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  evaluateFertilizer: (b) => request("/api/fertilizer/evaluate", json(b)),
  profitOptions: (state, district, season) => request(`/api/profit/options?state=${encodeURIComponent(state)}`
    + (district ? `&district=${encodeURIComponent(district)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  profitCompare: (b) => request("/api/profit/compare", json(b)),
  schemes: (state, crop, season) => request(`/api/schemes?lang=${LANG}` + (state ? `&state=${encodeURIComponent(state)}` : "")
    + (crop ? `&crop=${encodeURIComponent(crop)}` : "") + (season ? `&season=${encodeURIComponent(season)}` : "")),
  sendFeedback: (b) => request("/api/feedback", json(b)),
  feedbackSummary: () => request("/api/feedback/summary"),
  history: (module, limit = 50) =>
    request(`/api/history?limit=${limit}${module ? `&module=${module}` : ""}`),
};

/** Convert form strings into a clean payload: numbers parsed, empty values dropped. */
export function cleanPayload(values, numericKeys) {
  const out = {};
  for (const [k, v] of Object.entries(values)) {
    if (v === "" || v === null || v === undefined) continue;
    out[k] = numericKeys.includes(k) ? Number(v) : typeof v === "string" ? v.trim() : v;
  }
  return out;
}

/** Fallback voice from the backend (gTTS). Returns an audio Blob. */
export async function ttsBlob(text, lang) {
  let res;
  try {
    res = await fetch(`${BASE}/api/tts`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text, lang }) });
  } catch {
    throw new Error(NO_BACKEND[LANG] || NO_BACKEND.en);
  }
  if (!res.ok) { let d = ""; try { d = (await res.json()).detail; } catch { /* ignore */ } throw new Error(d || "TTS failed"); }
  return res.blob();
}
'@
Save-File "frontend\src\services\api.js" $c

$c = @'
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../services/api.js";
import { Badge, Alert } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";

const MODULES = [["\u{1F33E}", "nav.crop", "dash.m1", "/crop-recommendation"], ["\u{1F4C8}", "nav.yield", "dash.m2", "/yield-prediction"],
  ["\u{1FA7A}", "nav.health", "dash.m3", "/crop-health"], ["\u{1F9EA}", "nav.fertilizer", "dash.m4", "/fertilizer"],
  ["\u{1F4B0}", "nav.profit", "dash.m5", "/profit"], ["\u{1F3DB}\uFE0F", "nav.schemes", "dash.m6", "/schemes"]];
const tone = (s = "") => (s.startsWith("trained") ? "green" : s.startsWith("unavailable") ? "red" : "amber");
const statusKey = (s = "") => "status." + (s.startsWith("rule-based") ? "rule-based" : s.split(" ")[0]);

export default function Dashboard() {
  const { t } = useLang();
  const [recent, setRecent] = useState([]);
  const [models, setModels] = useState(null);
  const [error, setError] = useState("");
  const [real, setReal] = useState(null);

  useEffect(() => {
    api.history(null, 5).then((d) => setRecent(d.items)).catch((e) => setError(e.message));
    api.status().then((d) => setModels(d.models)).catch(() => {});
    api.feedbackSummary().then(setReal).catch(() => {});
  }, []);

  return (
    <div className="container page">
      <div className="welcome card">
        <div><h1>{t("dash.welcome")}</h1><p>{t("dash.sub")}</p></div>
        <Link to="/crop-recommendation" className="btn primary">{t("dash.start")}</Link>
      </div>

      <div className="grid six mt">
        {MODULES.map(([i, title, d, to]) => (
          <Link key={to} to={to} className="card feature">
            <div className="icon">{i}</div><h3>{t(title)}</h3><p>{t(d)}</p><span className="more">{t("common.open")}</span>
          </Link>
        ))}
      </div>

      <div className="grid two mt">
        <section className="card">
          <h3>{t("dash.recent")}</h3>
          <Alert>{error}</Alert>
          {!error && recent.length === 0 && <p className="muted">{t("dash.none")}</p>}
          {recent.map((r) => (
            <div className="hist-row" key={r.module + r.id}>
              <div><b>{t("mod." + r.module)}</b><div className="muted small">{r.summary}</div></div>
              <div className="muted small">{new Date(r.created_at).toLocaleString()}</div>
            </div>
          ))}
          <Link to="/history" className="more">{t("dash.viewAll")}</Link>
        </section>

        <section className="card">
          <h3>{t("dash.models")}</h3>
          {!models && <p className="muted">{t("dash.checking")}</p>}
          {models && Object.entries(models).map(([k, v]) => (
            <div className="hist-row" key={k}>
              <span>{t("mod." + k)}</span><Badge tone={tone(v.status)}>{t(statusKey(v.status))}</Badge>
            </div>
          ))}
          <h3 className="mt">{t("dash.real")}</h3>
          {(!real || real.total === 0) && <p className="muted small">{t("dash.realNone")}</p>}
          {real && Object.entries(real.by_module).filter(([, m]) => m.count > 0).map(([k, m]) => (
            <div className="hist-row" key={k}><span>{t("mod." + k)}</span><b>{t("dash.realRight", { n: m.count, p: m.percent_right })}</b></div>
          ))}
          {real && real.yield_error && <p className="muted small">{t("dash.realYield", { e: real.yield_error.mean_pct_error, n: real.yield_error.count, w: real.yield_error.within_20_percent })}</p>}
          <h3 className="mt">{t("dash.insights")}</h3>
          <ul className="list">{["i1", "i2", "i3", "i4"].map((k) => <li key={k}>{t("dash." + k)}</li>)}</ul>
        </section>
      </div>
    </div>
  );
}
'@
Save-File "frontend\src\pages\Dashboard.jsx" $c

$c = @'
import { useCallback, useEffect, useRef, useState } from "react";
import { api, cleanPayload } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Spinner, List, SpeakButton } from "../components/ui.jsx";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";
import { SOIL_TYPES } from "../data/locations.js";
import FeedbackBox from "../components/FeedbackBox.jsx";

const SEASON_KEY = { Kharif: "season.kharif", Rabi: "season.rabi", Summer: "season.summer", "Whole Year": "season.whole", Autumn: "season.autumn", Winter: "season.winter" };
const INPUT_KEY = { state: "common.state", district: "common.district", crop: "common.crop", season: "common.season", area_hectares: "yield.area" };

const INIT = { state: "", district: "", crop: "", season: "", area_hectares: "1", soil_type: "", n_level: "", p_level: "", k_level: "" };
const pretty = (s) => s.charAt(0) + s.slice(1).toLowerCase();

export default function YieldPrediction() {
  const { t } = useLang();
  const [v, setV] = useState(INIT);
  const [opts, setOpts] = useState({ crops: [], seasons: [], states: [], districts: {} });
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [unavailable, setUnavailable] = useState("");
  const [busy, setBusy] = useState(false);

  const lastRun = useRef(null);
  const hid = useRef(null);
  if (res?.history_id) hid.current = res.history_id;
  useEffect(() => { api.yieldOptions().then(setOpts).catch((e) => setError(e.message)); }, []);
  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const sel = (k) => ({ value: v[k], onChange: (e) => set(k)(e.target.value) });
  const districts = opts.districts[v.state] || [];

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); setUnavailable(""); lastRun.current = null; hid.current = null; }, []);
  useRelang(lastRun, setRes);
  const onFill = useCallback((f) => {
    if (f.area_hectares === undefined) return [];
    setV((p) => ({ ...p, area_hectares: String(f.area_hectares) }));
    return ["area_hectares"];
  }, []);
  useVoiceEvents({ onFill, onReset: reset });

  function example() {
    const state = opts.states.includes("Telangana") ? "Telangana" : opts.states[0] || "";
    setV({ ...INIT, state, district: (opts.districts[state] || [])[0] || "", crop: opts.crops.includes("Rice") ? "Rice" : opts.crops[0] || "", season: "Kharif", area_hectares: "1" });
  }

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(""); setRes(null); setUnavailable(""); hid.current = null;
    const payload = cleanPayload(v, ["area_hectares"]);
    lastRun.current = (re) => api.predictYield({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { err.status === 503 ? setUnavailable(err.message) : setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res ? t("yield.speak", { crop: v.crop, y: res.predicted_yield, area: v.area_hectares, tot: res.expected_total_production }) : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon={"\u{1F4C8}"} title={t("yield.title")} subtitle={t("yield.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("yield.select")}</h3>
          <div className="form-grid">
            <Field label={t("common.state")}>
              <select required value={v.state} onChange={(e) => setV((p) => ({ ...p, state: e.target.value, district: "" }))}>
                <option value="">{t("common.selectState")}</option>{opts.states.map((s) => <option key={s}>{s}</option>)}
              </select>
            </Field>
            <Field label={t("common.district")}>
              <select required {...sel("district")} disabled={!v.state}>
                <option value="">{v.state ? t("common.selectDistrict") : t("common.selectStateFirst")}</option>
                {districts.map((d) => <option key={d} value={d}>{pretty(d)}</option>)}
              </select>
            </Field>
            <Field label={t("common.crop")}>
              <select required {...sel("crop")}><option value="">{t("common.select")}</option>{opts.crops.map((c) => <option key={c}>{c}</option>)}</select>
            </Field>
            <Field label={t("common.season")}>
              <select required {...sel("season")}><option value="">{t("common.select")}</option>{opts.seasons.map((s) => <option key={s} value={s}>{SEASON_KEY[s] ? t(SEASON_KEY[s]) : s}</option>)}</select>
            </Field>
            <Field label={t("yield.area")} hint={t("yield.areaHint")}>
              <NumberInput required min={0.01} value={v.area_hectares} onChange={set("area_hectares")} />
            </Field>
          </div>
          <h3>{t("yield.soilSection")}</h3>
          <div className="form-grid">
            <Field label={t("common.soilType")}>
              <select {...sel("soil_type")}><option value="">{t("common.select")}</option>{SOIL_TYPES.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
            {[["n_level", "crop.N"], ["p_level", "crop.P"], ["k_level", "crop.K"]].map(([k, lab]) => (
              <Field key={k} label={t(lab)}><select {...sel(k)}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
            ))}
          </div>
          <p className="muted small">{t("yield.soilNote")}</p>
          <p className="muted small">{t("yield.note")}</p>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy}>{busy ? t("yield.predicting") : t("yield.btn")}</button>
            <button type="button" className="btn outline" onClick={example}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner text={t("yield.predicting")} />}
          <Alert title={t("yield.couldNot")}>{error}</Alert>
          {unavailable && <Alert kind="warn" title={t("yield.notTrained")}>{unavailable}</Alert>}
          {!res && !busy && !error && !unavailable && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              <div className="card result big">
                <div className="muted">{t("yield.predicted")}</div>
                <div className="big-number">{res.predicted_yield} <small>{t("yield.unit")}</small></div>
                <p>{t("yield.total", { area: v.area_hectares })} <b>{res.expected_total_production} {t("yield.tonnes")}</b></p>
                <List items={res.warnings} tone="warn" />
                <SpeakButton text={speech} />
              </div>
              <div className="card">
                <h4>{t("yield.inputs")}</h4>
                {Object.entries(res.inputs_used).map(([k, val]) => (
                  <div className="hist-row" key={k}><span>{t(INPUT_KEY[k] || k)}</span><b>{k === "season" && SEASON_KEY[val] ? t(SEASON_KEY[val]) : k === "district" ? pretty(String(val)) : String(val)}</b></div>
                ))}
                {res.metrics && (
                  <>
                    <h4>{t("yield.acc")}</h4>
                    <div className="metric-grid">
                      <div><span>MAE</span><b>{res.metrics.MAE}</b></div><div><span>RMSE</span><b>{res.metrics.RMSE}</b></div><div><span>R{"\u00B2"}</span><b>{res.metrics.R2}</b></div>
                    </div>
                    <p className="muted small">{t("yield.base", { r2: res.metrics.baseline_crop_average_R2 })} {t("yield.testNote")}</p>
                  </>
                )}
                {res.soil_suitability && (
                  <>
                    <h4>{t("yield.soilTitle")}</h4>
                    {res.soil_suitability.available ? <List items={res.soil_suitability.lines} tone={res.soil_suitability.ok ? "ok" : "warn"} /> : <p className="muted small">{t("yield.soilNA")}</p>}
                    {res.soil_suitability.estimated && <p className="muted small">{t("crop.estNote")}</p>}
                  </>
                )}
                <Alert kind="warn">{res.disclaimer}</Alert>
              </div>
              {hid.current && <FeedbackBox key={hid.current} module="yield_prediction" historyId={hid.current} kind="yield" />}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
'@
Save-File "frontend\src\pages\YieldPrediction.jsx" $c

$c = @'
import { useCallback, useEffect, useRef, useState } from "react";
import { api, cleanPayload } from "../services/api.js";
import { PageHeader, Field, NumberInput, Alert, Bar, Spinner, List, SpeakButton, cap } from "../components/ui.jsx";
import LocationFields from "../components/LocationFields.jsx";
import { SOIL_TYPES, SEASONS } from "../data/locations.js";
import { useLang } from "../i18n/LanguageContext.jsx";
import { useSpeechText, useVoiceEvents } from "../voice/VoiceContext.jsx";
import { useRelang } from "../i18n/useRelang.js";
import { fetchWeather } from "../services/weather.js";
import FeedbackBox from "../components/FeedbackBox.jsx";

const FEAT_KEY = { N: "crop.N", P: "crop.P", K: "crop.K", ph: "crop.ph", temperature: "crop.temp", humidity: "crop.hum", rainfall: "crop.rain" };

const NUM = ["N", "P", "K", "ph", "temperature", "humidity", "rainfall"];
const INIT = { state: "", district: "", village: "", soil_type: "", season: "", N: "", P: "", K: "", ph: "", temperature: "", humidity: "", rainfall: "", n_level: "", p_level: "", k_level: "", water: "", irrigation: "", last_crop: "" };
const EXAMPLE = { N: "90", P: "42", K: "43", ph: "6.5", temperature: "21", humidity: "82", rainfall: "203" };

export default function CropRecommendation() {
  const { t, lang } = useLang();
  const [v, setV] = useState(INIT);
  const [res, setRes] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const lastRun = useRef(null);
  const hid = useRef(null);
  if (res?.history_id) hid.current = res.history_id;
  const [wxBusy, setWxBusy] = useState(false);
  const [wxMsg, setWxMsg] = useState("");
  async function liveWeather() {
    setWxBusy(true); setWxMsg("");
    try {
      const w = await fetchWeather(v.district, v.state);
      setV((p) => ({ ...p, temperature: String(w.temperature), humidity: String(w.humidity), rainfall: String(w.rainfall) }));
      setWxMsg(t("crop.wxOk", { place: w.place }));
    } catch (err) { setWxMsg(t("crop.wxFail")); }
    finally { setWxBusy(false); }
  }
  const set = (k) => (val) => setV((p) => ({ ...p, [k]: val }));
  const [mode, setMode] = useState("dont");
  const [area, setArea] = useState(null);
  const [areaBusy, setAreaBusy] = useState(false);
  const [cropList, setCropList] = useState([]);
  useEffect(() => { api.fertilizers().then((r) => setCropList(r.crops)).catch(() => {}); }, [lang]);
  async function loadArea() {
    if (!v.state) { setArea({ error: t("crop.areaFail") }); return; }
    setAreaBusy(true);
    try { const r = await api.areaCrops(v.state, v.district, v.season); setArea(r.crops.length ? { crops: r.crops } : { error: t("crop.areaFail") }); }
    catch (err) { setArea({ error: err.message }); }
    finally { setAreaBusy(false); }
  }
  const sel = (k) => ({ value: v[k], onChange: (e) => set(k)(e.target.value) });

  const reset = useCallback(() => { setV(INIT); setRes(null); setError(""); lastRun.current = null; hid.current = null; }, []);
  useRelang(lastRun, setRes);
  const onFill = useCallback((f) => {
    const keys = Object.keys(f).filter((k) => NUM.includes(k));
    setV((p) => { const n = { ...p }; keys.forEach((k) => { n[k] = String(f[k]); }); return n; });
    return keys;
  }, []);
  useVoiceEvents({ onFill, onReset: reset });

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(""); setRes(null); hid.current = null;
    const payload = { ...cleanPayload(v, NUM), top_k: 3 };
    if (mode === "dont") { delete payload.N; delete payload.P; delete payload.K; } else { delete payload.n_level; delete payload.p_level; delete payload.k_level; }
    if (mode === "dont" && !payload.soil_type && !payload.n_level && !payload.p_level && !payload.k_level) { setError(t("crop.needSoil")); setBusy(false); return; }
    lastRun.current = (re) => api.recommendCrop({ ...payload, relocalize: !!re });
    try { setRes(await lastRun.current(false)); }
    catch (err) { setError(err.message); }
    finally { setBusy(false); }
  }

  const speech = res ? t("crop.speak", {
    crop: res.recommendations[0].crop_label, p: Math.round(res.recommendations[0].model_probability * 100),
    others: res.recommendations.length > 1 ? t("crop.speakOthers", { list: res.recommendations.slice(1).map((r) => r.crop_label).join(", ") }) : "",
  }) + " " + res.notes[res.notes.length - 1] : "";
  useSpeechText(speech);

  return (
    <>
      <PageHeader icon={"\u{1F33E}"} title={t("crop.title")} subtitle={t("crop.sub")} />
      <div className="container page two-col wide-left">
        <form className="card form" onSubmit={submit}>
          <h3>{t("crop.farm")}</h3>
          <div className="form-grid">
            <LocationFields value={v} onChange={(loc) => setV((p) => ({ ...p, ...loc }))} />
            <Field label={t("common.soilType")} hint={t("crop.soilHint")}>
              <select {...sel("soil_type")}><option value="">{t("common.select")}</option>{SOIL_TYPES.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
            <Field label={t("common.season")} hint={t("crop.seasonHint")}>
              <select {...sel("season")}><option value="">{t("common.select")}</option>{SEASONS.map(([val, k]) => <option key={val} value={val}>{t(k)}</option>)}</select>
            </Field>
          </div>
          <h3>{t("crop.soilTitle")}</h3>
          <div className="btn-row">
            <button type="button" className={"btn " + (mode === "dont" ? "primary" : "outline")} onClick={() => setMode("dont")}>{t("crop.modeDont")}</button>
            <button type="button" className={"btn " + (mode === "know" ? "primary" : "outline")} onClick={() => setMode("know")}>{t("crop.modeKnow")}</button>
          </div>
          {mode === "dont" && (
            <>
              <p className="muted small">{t("crop.dontHelp")}</p>
              <div className="form-grid">
                {[["n_level", "crop.N"], ["p_level", "crop.P"], ["k_level", "crop.K"]].map(([k, lab]) => (
                  <Field key={k} label={t(lab)}><select {...sel(k)}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
                ))}
              </div>
            </>
          )}
          <div className="btn-row">
            <button type="button" className="btn outline" disabled={areaBusy} onClick={loadArea}>{t("crop.areaBtn")}</button>
          </div>
          {area && <><p className="muted small">{area.error || t("crop.areaNote")}</p>{area.crops && <List items={area.crops} tone="ok" />}</>}
          <p className="muted small">{t("soil.tip")}</p>
          <h3>{t("crop.values")}</h3>
          <div className="btn-row">
            <button type="button" className="btn outline" disabled={wxBusy || !v.state} onClick={liveWeather}>{wxBusy ? t("common.analysing") : t("crop.wxBtn")}</button>
            {wxMsg && <span className="muted small">{wxMsg}</span>}
          </div>
          <div className="form-grid">
            {mode === "know" && <Field label={t("crop.N")}><NumberInput min={0} max={300} value={v.N} onChange={set("N")} /></Field>}
            {mode === "know" && <Field label={t("crop.P")}><NumberInput min={0} max={300} value={v.P} onChange={set("P")} /></Field>}
            {mode === "know" && <Field label={t("crop.K")}><NumberInput min={0} max={400} value={v.K} onChange={set("K")} /></Field>}
            <Field label={t("crop.ph")} hint={t("crop.phHint")}><NumberInput min={3} max={10} value={v.ph} onChange={set("ph")} /></Field>
            <Field label={t("crop.temp")}><NumberInput required min={0} max={55} value={v.temperature} onChange={set("temperature")} /></Field>
            <Field label={t("crop.hum")}><NumberInput required min={0} max={100} value={v.humidity} onChange={set("humidity")} /></Field>
            <Field label={t("crop.rain")}><NumberInput min={0} max={500} value={v.rainfall} onChange={set("rainfall")} /></Field>
            <Field label={t("crop.water")} hint={t("crop.waterHint")}><select {...sel("water")}><option value="">{t("lvl.none")}</option><option value="low">{t("lvl.low")}</option><option value="medium">{t("lvl.med")}</option><option value="high">{t("lvl.high")}</option></select></Field>
            <Field label={t("crop.irrig")}><select {...sel("irrigation")}><option value="">{t("lvl.none")}</option><option value="rainfed">{t("crop.rainfed")}</option><option value="irrigated">{t("crop.irrigated")}</option></select></Field>
            <Field label={t("crop.lastCrop")}><select {...sel("last_crop")}><option value="">{t("crop.lastNone")}</option>{cropList.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select></Field>
          </div>
          <div className="btn-row">
            <button className="btn primary lg" disabled={busy}>{busy ? t("common.analysing") : t("crop.btn")}</button>
            <button type="button" className="btn outline" onClick={() => { setMode("know"); setV((p) => ({ ...p, ...EXAMPLE })); }}>{t("common.example")}</button>
            <button type="button" className="btn outline" onClick={reset}>{t("common.reset")}</button>
          </div>
        </form>

        <div>
          {busy && <Spinner />}
          <Alert title={t("crop.couldNot")}>{error}</Alert>
          {!res && !busy && !error && <div className="card empty">{t("common.resultsHere")}</div>}
          {res && (
            <div className="results">
              {res.estimated && res.estimated.length > 0 && <Alert kind="warn">{t("crop.estNote")}</Alert>}
              {res.regional_applied && <Alert kind="info">{t("crop.regNote")}</Alert>}
              {res.low_confidence && <Alert kind="warn" title={t("crop.warnTitle")}>{res.notes.slice(0, 2).filter((n) => n).join(" ")}</Alert>}
              <SpeakButton text={speech} />
              {res.recommendations.map((r, i) => (
                <div className="card result" key={r.crop}>
                  <div className="result-head">
                    <h3>{i + 1}. {cap(r.crop_label)}</h3>
                    {i === 0 && <span className="badge green">{t("crop.best")}</span>}
                  </div>
                  <Bar label={t("crop.prob")} value={r.model_probability} />
                  {res.regional_applied && <Bar label={t("crop.adj")} value={r.adjusted_probability} />}
                  {r.rotation && <List items={[t("rot." + r.rotation)]} tone={r.rotation === "repeat" ? "warn" : "ok"} />}
                  {r.regional && <List items={[r.regional.text]} tone={r.regional.ok ? "ok" : "warn"} />}
                  <h4>{t("crop.why")}</h4><List items={r.reasons} tone="ok" />
                  {r.warnings.length > 0 && <><h4>{t("crop.check")}</h4><List items={r.warnings} tone="warn" /></>}
                </div>
              ))}
              <div className="card">
                <h4>{t("crop.perf")}</h4>
                <Bar label={t("crop.acc")} value={res.model_metrics.test_accuracy} />
                <Bar label={t("crop.f1")} value={res.model_metrics.test_macro_f1} />
                <p className="muted small">{t("crop.metricsNote")}</p>
                <h4>{t("crop.importance")}</h4>
                {Object.entries(res.model_metrics.feature_importance).sort((a, b) => b[1] - a[1]).map(([k, val]) => (
                  <Bar key={k} label={t(FEAT_KEY[k])} value={val} max={0.25} text={val.toFixed(3)} tone="navy" />
                ))}
                <h4>{t("crop.notes")}</h4><List items={res.notes} />
              </div>
              {hid.current && <FeedbackBox key={hid.current} module="crop_recommendation" historyId={hid.current} kind="crop" />}
            </div>
          )}
        </div>
      </div>
    </>
  );
}
'@
Save-File "frontend\src\pages\CropRecommendation.jsx" $c

$c = @'
# Copy to backend/.env . All values optional; the app works without them.
ALLOWED_ORIGINS=http://localhost:5173,http://localhost:3000
MAX_IMAGE_MB=5
DISEASE_CONFIDENCE_THRESHOLD=0.60
# Optional weather API (manual weather entry always works):
OPENWEATHER_API_KEY=
# Live mandi prices for Profit mode (free key from https://data.gov.in -> register -> My Account). If empty, farmers type the price.
DATA_GOV_API_KEY=
# WhatsApp / SMS bot through Twilio (optional). Set both to check that messages really come from Twilio.
TWILIO_AUTH_TOKEN=
BOT_PUBLIC_URL=
'@
Save-File ".env.example" $c

# ---- optional keys in backend\.env (only if the file already exists and lacks them)
$envFile = Join-Path $root "backend\.env"
if (Test-Path $envFile) {
    $cur = Get-Content $envFile -Raw
    $add = ""
    if ($cur -notmatch "DATA_GOV_API_KEY") { $add += "`nDATA_GOV_API_KEY=" }
    if ($cur -notmatch "TWILIO_AUTH_TOKEN") { $add += "`nTWILIO_AUTH_TOKEN=`nBOT_PUBLIC_URL=" }
    if ($add) { Add-Content -Path $envFile -Value $add; Write-Host "  added empty key lines to backend\.env" }
}

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "== Backend check ==" -ForegroundColor Green
$py = Join-Path $root "backend\venv\Scripts\python.exe"
if (Test-Path $py) {
    Push-Location (Join-Path $root "backend")
    & $py -m pip install -q -r requirements-dev.txt httpx
    & $py -m pytest -q
    if ($LASTEXITCODE -eq 0) { Write-Host "Backend tests PASSED" -ForegroundColor Green }
    else { Write-Host "Backend tests FAILED - see messages above" -ForegroundColor Red }
    Pop-Location
} else {
    Write-Host "backend\venv not found. Run .\setup.ps1 first, then run this script again." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "== Frontend check ==" -ForegroundColor Green
Push-Location (Join-Path $root "frontend")
if (-not (Test-Path "node_modules")) { npm install }
npm run build
if ($LASTEXITCODE -eq 0) { Write-Host "Frontend build PASSED" -ForegroundColor Green }
else { Write-Host "Frontend build FAILED - see messages above" -ForegroundColor Red }
Pop-Location

Write-Host ""
Write-Host "DONE. Old files are saved in: $backup" -ForegroundColor Green
Write-Host "Start the app:   .\run-backend.ps1   (one terminal)   and   .\run-frontend.ps1   (another terminal)"
Write-Host "New pages:       http://localhost:5173/profit   and   http://localhost:5173/schemes"
Write-Host "Bot test (Telugu message, JSON uses \u escapes so it works in any PowerShell):"
Write-Host '  Invoke-RestMethod -Method Post -Uri http://localhost:8000/api/bot/message -ContentType "application/json" -Body ''{"text":"\u0c35\u0c30\u0c3f \u0c28\u0c32\u0c4d\u0c17\u0c4a\u0c02\u0c21 2 2300"}'''
Write-Host "Live mandi prices: put DATA_GOV_API_KEY=your_free_key in backend\.env and restart the backend."
