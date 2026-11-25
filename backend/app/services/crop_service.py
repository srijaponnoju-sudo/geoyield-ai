import pandas as pd
from app.i18n import t, crop_name
from app.services import registry, regional_service, soil_service

UNITS = {"temperature": "°C", "humidity": "%", "rainfall": "mm"}


def recommend(inp: dict) -> dict:
    lang = inp.get("lang", "en")
    bundle = registry.crop_model()
    if not bundle:
        return {"model_status": "unavailable", "message": t("crop_model_missing", lang)}
    inp, estimated = soil_service.fill_crop_inputs(inp)
    missing = [f for f in ("N", "P", "K", "ph", "temperature", "humidity", "rainfall") if inp.get(f) is None]
    if missing:
        return {"model_status": "needs_input",
                "message": soil_service.NEED_SOIL if set(missing) & {"N", "P", "K"} else "Missing: " + ", ".join(missing)}
    feats = bundle["features"]
    X = pd.DataFrame([{f: inp[f] for f in feats}])
    proba = bundle["model"].predict_proba(X)[0]
    classes = bundle["model"].classes_
    profile = registry.crop_profile()
    order = proba.argsort()[::-1][: inp.get("top_k", 3)]
    recs = []
    for i in order:
        crop = classes[i]
        label = crop_name(crop, lang)
        reasons, warnings = [], []
        for f in feats:
            r = profile.get(crop, {}).get(f)
            if not r:
                continue
            v, unit = inp[f], UNITS.get(f, "")
            span = f"{r['p10']}–{r['p90']}{unit}"
            key = "crop_in" if r["p10"] <= v <= r["p90"] else "crop_out"
            (reasons if key == "crop_in" else warnings).append(
                t(key, lang, name=t("f_" + f, lang), v=v, unit=unit, crop=label, span=span))
        regional = regional_service.message(crop, label, inp.get("state"), inp.get("season"), lang)
        recs.append({"crop": crop, "crop_label": label, "model_probability": round(float(proba[i]), 4),
                     "reasons": reasons, "warnings": warnings, "regional": regional})

    notes = [t("note_prob", lang)]
    ranges = registry.read_json("crop_feature_ranges.json")
    odd = [t("f_" + f, lang) for f in feats if ranges and not (ranges[f]["min"] <= inp[f] <= ranges[f]["max"])]
    top_p = recs[0]["model_probability"]
    if odd:
        notes.insert(0, t("note_extrap", lang, fields=", ".join(odd)))
    if top_p < 0.5:
        notes.insert(0, t("note_lowconf", lang, p=round(top_p * 100)))
    given = any(inp.get(k) for k in ("state", "district", "village", "soil_type", "season"))
    notes.append(t("note_ignored" if given else "note_notgiven", lang))
    notes.append(t("note_confirm", lang))
    return {
        "model_status": "trained", "recommendations": recs,
        "model_metrics": registry.read_json("crop_recommendation_metrics.json"),
        "notes": notes, "low_confidence": top_p < 0.5 or bool(odd) or bool(estimated), "estimated": estimated,
    }
