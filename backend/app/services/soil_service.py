"""Helpers that let farmers use GeoYield AI without lab numbers.

- Low / Medium / High levels and soil-type "typical" levels are converted to the model's own scale
  (about the 17th / 50th / 83rd percentile of the crop-recommendation training data).
- Soil-type tendencies are general agronomy rules of thumb, NOT measured data, so results that use them
  are flagged as estimates.
"""
from functools import lru_cache
import json
import pandas as pd
from app.config import BASE_DIR, DATA_DIR
from app.i18n import crop_name, norm, t
from app.services import registry
from app.services.regional_service import CROP_MAP

NEED_SOIL = ("Please give some soil information: choose a soil type, or Low/Medium/High for N, P and K, or enter "
             "the values. If you know nothing about your soil, use 'Crops commonly grown in my area'.")

LEVEL_VALUE = {
    "N": {"low": 14.0, "medium": 37.0, "high": 95.0},
    "P": {"low": 21.0, "medium": 51.0, "high": 75.0},
    "K": {"low": 18.0, "medium": 32.0, "high": 53.0},
}
RAIN_VALUE = {"low": 53.0, "medium": 95.0, "high": 160.0}

# typical tendencies by soil type (rule of thumb) - keys are lower-case soil type names used by the app
SOIL = {
    "red soil": {"N": "low", "P": "low", "K": "low", "ph": 6.0},
    "black soil (regur)": {"N": "low", "P": "low", "K": "high", "ph": 7.5},
    "alluvial soil": {"N": "low", "P": "medium", "K": "medium", "ph": 7.0},
    "sandy soil": {"N": "low", "P": "low", "K": "low", "ph": 6.5},
    "loamy soil": {"N": "medium", "P": "medium", "K": "medium", "ph": 6.8},
    "clay soil": {"N": "medium", "P": "medium", "K": "high", "ph": 7.2},
    "laterite soil": {"N": "low", "P": "low", "K": "low", "ph": 5.5},
}


def _lvl(x):
    x = (x or "").strip().lower()
    return x if x in ("low", "medium", "high") else None


def fill_nutrients(inp: dict, with_ph: bool = False) -> tuple[dict, list]:
    """Fill missing N/P/K (and optionally pH) from the chosen Low/Medium/High level, else the soil type's typical level.
    Returns (new input dict, list of fields that were estimated)."""
    out, est = dict(inp), []
    defaults = SOIL.get((inp.get("soil_type") or "").strip().lower())
    for nut in ("N", "P", "K"):
        if out.get(nut) is not None:
            continue
        level = _lvl(out.get(nut.lower() + "_level")) or (defaults[nut] if defaults else None)
        if level:
            out[nut] = LEVEL_VALUE[nut][level]
            est.append(nut)
    if with_ph and out.get("ph") is None and defaults:
        out["ph"] = defaults["ph"]
        est.append("ph")
    return out, est


def fill_crop_inputs(inp: dict) -> tuple[dict, list]:
    """Crop recommendation: also estimate rainfall from the 'water availability' choice."""
    out, est = fill_nutrients(inp, with_ph=True)
    if out.get("rainfall") is None and _lvl(out.get("water")):
        out["rainfall"] = RAIN_VALUE[_lvl(out["water"])]
        est.append("rainfall")
    return out, est


# ---------- yield: soil suitability (does not change the yield number) ----------
@lru_cache(maxsize=1)
def _reverse_crops() -> dict:
    rev = {}
    for code, names in CROP_MAP.items():
        for n in names or []:
            rev[n.strip().lower()] = code
    return rev


def yield_soil_check(inp: dict, lang: str = "en") -> dict | None:
    has_any = inp.get("soil_type") or any(inp.get(k) is not None or inp.get(k.lower() + "_level") for k in ("N", "P", "K"))
    if not has_any:
        return None
    vals, est = fill_nutrients(inp, with_ph=True)
    code = _reverse_crops().get((inp.get("crop") or "").strip().lower())
    profile = registry.crop_profile() or {}
    if not code or code not in profile:
        return {"available": False, "lines": [], "ok": False, "estimated": bool(est)}
    lang = norm(lang)
    lines, ok = [], True
    for f in ("N", "P", "K", "ph"):
        r, v = profile[code].get(f), vals.get(f)
        if not r or v is None:
            continue
        inside = r["p10"] <= v <= r["p90"]
        ok = ok and inside
        lines.append(t("crop_in" if inside else "crop_out", lang, name=t("f_" + f, lang), v=v, unit="",
                       crop=crop_name(code, lang), span=f"{r['p10']}-{r['p90']}"))
    return {"available": bool(lines), "lines": lines, "ok": ok and bool(lines), "estimated": bool(est)}


# ---------- crop problems (for the fertilizer check) ----------
def _kb():
    kb = json.loads((DATA_DIR / "symptoms.json").read_text(encoding="utf-8"))["conditions"]
    tr = json.loads((DATA_DIR / "symptoms_i18n.json").read_text(encoding="utf-8"))
    return kb, tr


def problem_list(lang: str = "en") -> list[dict]:
    kb, tr = _kb()
    lang = norm(lang)
    return [{"id": c["id"], "name": tr.get(lang, {}).get(c["id"], {}).get("name", c["name"]), "kind": c["kind"]} for c in kb]


GROUPS = {"nutrient": "nutrient", "disease": "disease", "disease/pest": "disease", "pest": "pest",
          "abiotic": "abiotic", "disease/abiotic": "abiotic"}
DEFICIENCY = {"n_def": "N", "p_def": "P", "k_def": "K"}


def problem_note(problem_id: str, res: dict, lang: str = "en") -> dict | None:
    kb, tr = _kb()
    lang = norm(lang)
    c = next((x for x in kb if x["id"] == problem_id), None)
    if not c:
        return None
    nut = DEFICIENCY.get(problem_id)
    npk = res.get("fertilizer_npk")
    missing = nut if (nut and npk and len(npk) == 3 and not npk["NPK".index(nut)]) else None
    return {"id": c["id"], "name": tr.get(lang, {}).get(c["id"], {}).get("name", c["name"]),
            "group": GROUPS.get(c["kind"], "disease"), "missing": missing}


# ---------- "I know nothing about my soil": crops commonly grown in the area ----------
@lru_cache(maxsize=1)
def _prod() -> pd.DataFrame:
    d = pd.read_csv(BASE_DIR / "ml" / "datasets" / "crop_production.csv",
                    usecols=["State_Name", "District_Name", "Season", "Crop", "Area"])
    for c in ("State_Name", "District_Name", "Season", "Crop"):
        d[c] = d[c].astype(str).str.strip()
    return d


def common_crops(state: str, district: str | None = None, season: str | None = None, limit: int = 6) -> dict:
    rows = _prod()
    rows = rows[rows.State_Name.str.lower() == state.strip().lower()]
    scope = "state"
    if district:
        dd = rows[rows.District_Name.str.lower() == district.strip().lower()]
        if not dd.empty:
            rows, scope = dd, "district"
    if season:
        ss = rows[rows.Season.str.lower().isin([season.strip().lower(), "whole year"])]
        if not ss.empty:
            rows = ss
    top = rows.groupby("Crop").Area.sum().sort_values(ascending=False)
    return {"scope": scope, "crops": [c for c in top.index if not c.lower().startswith("other")][:limit]}