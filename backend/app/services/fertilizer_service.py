"""Evaluates a farmer-selected fertilizer against soil status and crop nutrient ranges.

Crop nutrient ranges come from the trained dataset profile (10th-90th percentile of N, P, K for that crop),
fertilizer grades from data/fertilizers.json. No dosage is ever produced (needs verified local recommendations).
"""
import json
from app.config import DATA_DIR
from app.i18n import t, crop_name
from app.services import registry

NUTS = ["N", "P", "K"]


def _db() -> list[dict]:
    return json.loads((DATA_DIR / "fertilizers.json").read_text(encoding="utf-8"))["fertilizers"]


def list_fertilizers() -> list[dict]:
    return _db()


def _status(soil: float, rng: dict) -> str:
    return "low" if soil < rng["p10"] else "high" if soil > rng["p90"] else "adequate"


def evaluate(inp: dict) -> dict:
    lang = inp.get("lang", "en")
    nut = lambda n: t("n_" + n, lang)  # noqa: E731
    names = lambda ns: ", ".join(nut(n) for n in ns)  # noqa: E731
    profile = registry.crop_profile()
    crop = next((c for c in profile if c.lower() == inp["crop"].strip().lower()), None)
    if not crop:
        return {"verdict": "cannot_evaluate",
                "explanation": t("fert_cannot_crop", lang, crop=inp["crop"], list=", ".join(sorted(profile)) or "-")}
    label = crop_name(crop, lang)
    fert = next((f for f in _db() if f["name"].lower() == inp["fertilizer"].strip().lower()), None)
    if fert:
        npk, source = fert["npk"], t("fert_src_db", lang)
    elif inp.get("custom_npk"):
        npk, source = inp["custom_npk"], t("fert_src_user", lang)
    else:
        return {"verdict": "cannot_evaluate", "explanation": t("fert_cannot_fert", lang, f=inp["fertilizer"])}
    missing = [n for n in NUTS if inp.get(n) is None]
    if missing:
        return {"verdict": "cannot_evaluate", "explanation": t("fert_cannot_soil", lang, list=", ".join(missing))}

    ranges = profile[crop]
    soil = {n: _status(inp[n], ranges[n]) for n in NUTS}
    supplies = {n: npk[i] > 0 for i, n in enumerate(NUTS)}
    needed = [n for n in NUTS if soil[n] == "low"]
    excess = [n for n in NUTS if soil[n] == "high"]
    covered = [n for n in needed if supplies[n]]
    harmful = [n for n in excess if supplies[n]]

    reasons = [t("fert_soil_line", lang, nut=nut(n), status=t("s_" + soil[n], lang), crop=label,
                 lo=ranges[n]["p10"], hi=ranges[n]["p90"]) for n in NUTS]
    if not needed:
        verdict = "unsuitable"
        reasons.append(t("fert_none_needed", lang))
    elif harmful and len(harmful) >= len(covered):
        verdict = "unsuitable"
        reasons.append(t("fert_harmful", lang, list=names(harmful)))
    elif len(covered) == len(needed) and not harmful:
        verdict = "suitable"
        reasons.append(t("fert_covers", lang, list=names(covered)))
    elif covered:
        verdict = "potentially_suitable"
        missed = [n for n in needed if not supplies[n]]
        if missed:
            reasons.append(t("fert_missed", lang, list=names(missed)))
        if harmful:
            reasons.append(t("fert_also_high", lang, list=names(harmful)))
    else:
        verdict = "unsuitable"
        reasons.append(t("fert_missed", lang, list=names(needed)))

    ph_note = None
    if inp.get("ph") is not None:
        r = ranges["ph"]
        if not (r["p10"] <= inp["ph"] <= r["p90"]):
            ph_note = t("fert_ph", lang, ph=inp["ph"], crop=label, lo=r["p10"], hi=r["p90"])

    alt = None
    if verdict in ("unsuitable", "potentially_suitable") and needed:
        best, best_score = None, -1e9
        for f in _db():
            sup = {n: f["npk"][i] > 0 for i, n in enumerate(NUTS)}
            score = (sum(2 for n in needed if sup[n]) - sum(3 for n in excess if sup[n])
                     - sum(1 for n in NUTS if sup[n] and soil[n] == "adequate"))
            if score > best_score:
                best, best_score = f, score
        if best and best["name"] != (fert or {}).get("name") and best_score > 0:
            alt = {"fertilizer": best["name"], "npk": best["npk"],
                   "why": t("fert_alt_why", lang, list=names([n for n in needed if best["npk"][NUTS.index(n)] > 0]))}

    return {
        "verdict": verdict, "crop": crop, "crop_label": label,
        "fertilizer": fert["name"] if fert else inp["fertilizer"],
        "fertilizer_npk": npk, "npk_source": source, "soil_status": soil,
        "reasons": reasons, "ph_note": ph_note, "alternative": alt,
        "guidance": [t("fert_g1", lang), t("fert_g2", lang)], "method": t("fert_method", lang),
    }
