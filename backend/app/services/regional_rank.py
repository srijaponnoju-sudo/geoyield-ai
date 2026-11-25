"""Local reality check: re-weights the model's crop probabilities by how commonly each crop is grown in the
farmer's district (else state) and season, using the bundled government crop-production data.
It never removes a crop completely, because the data has gaps. It also gives crop-rotation hints."""
from functools import lru_cache
import numpy as np
import pandas as pd
from app.config import BASE_DIR
from app.services import registry
from app.services.regional_service import CROP_MAP

CSV = BASE_DIR / "ml" / "datasets" / "crop_production.csv"
LEGUMES = {"chickpea", "pigeonpeas", "mothbeans", "mungbean", "blackgram", "lentil", "kidneybeans"}
NOT_RECORDED, NEUTRAL = 0.1, 0.5


@lru_cache(maxsize=1)
def _data() -> pd.DataFrame:
    if not CSV.exists():
        return pd.DataFrame()
    d = pd.read_csv(CSV, usecols=["State_Name", "District_Name", "Season", "Crop", "Area"])
    for c in ("State_Name", "District_Name", "Season", "Crop"):
        d[c] = d[c].astype(str).str.strip().str.lower()
    rev = {n.strip().lower(): code for code, names in CROP_MAP.items() for n in (names or [])}
    d["code"] = d["Crop"].map(rev)
    return d.dropna(subset=["code"])


def _area(state, district, season) -> pd.Series:
    d = _data()
    if d.empty or not state:
        return pd.Series(dtype=float)
    rows = d[d.State_Name == state.strip().lower()]
    if district:
        dd = rows[rows.District_Name == district.strip().lower()]
        if not dd.empty:
            rows = dd
    if season:
        ss = rows[rows.Season.isin([season.strip().lower(), "whole year"])]
        if not ss.empty:
            rows = ss
    return rows.groupby("code").Area.sum()


def suitability(classes, feats, x):
    """Smooth 0..1 score of how well the soil/weather values fit each crop's typical range (never exactly zero)."""
    profile = registry.crop_profile() or {}
    s = np.zeros(len(classes))
    for j, c in enumerate(classes):
        z, k = 0.0, 0
        for f, v in zip(feats, x):
            r = profile.get(c, {}).get(f)
            if r:
                sd = max((r["p90"] - r["p10"]) / 2.56, 1e-6)
                z += ((v - r["mean"]) / sd) ** 2
                k += 1
        s[j] = np.exp(-0.5 * z / k) if k else 0.0
    total = s.sum()
    return s / total if total > 0 else s


def adjust(proba, classes, state, district=None, season=None, x=None, feats=None):
    """Returns (adjusted probabilities that sum to 1, whether the local check was applied).
    The model's probabilities are very sharp, so they are first blended with the smooth suitability score
    (60% model / 40% suitability) and then weighted by how commonly each crop is grown locally."""
    area = _area(state, district, season)
    if area.empty or area.max() <= 0:
        return proba, False
    base = np.asarray(proba, dtype=float)
    if x is not None and feats is not None:
        s = suitability(classes, feats, x)
        if s.sum() > 0:
            base = 0.6 * base + 0.4 * s
    top = float(area.max())
    w = np.empty(len(classes))
    for i, c in enumerate(classes):
        if CROP_MAP.get(c) is None:
            w[i] = NEUTRAL                                   # crop is not in the government file
        elif c in area.index:
            w[i] = 0.25 + 0.75 * (float(area[c]) / top) ** 0.5
        else:
            w[i] = NOT_RECORDED
    adj = base * w
    total = adj.sum()
    return (adj / total, True) if total > 0 else (proba, False)


def rotation(last_crop, crop):
    """Simple crop-rotation hint: 'repeat' | 'after_legume' | 'legume_next' | None."""
    if not last_crop:
        return None
    if last_crop == crop:
        return "repeat"
    if last_crop in LEGUMES and crop not in LEGUMES:
        return "after_legume"
    if last_crop not in LEGUMES and crop in LEGUMES:
        return "legume_next"
    return None