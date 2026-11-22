import pandas as pd
from app.i18n import t
from app.services import registry


def _match(value, known: list[str]):
    """Match user text to a value the model was trained on (case/space-insensitive)."""
    v = str(value).strip().lower()
    for k in known:
        if k.strip().lower() == v:
            return k
    return value


def options() -> dict:
    return registry.read_json("yield_options.json")


def predict(inp: dict) -> dict:
    lang = inp.get("lang", "en")
    bundle = registry.yield_model()
    if not bundle:
        return {"model_status": "unavailable", "message": t("yield_missing", lang)}
    known = bundle.get("known_values", {})
    row = {f: inp.get(f) for f in bundle["features"]}
    missing = [f for f in bundle["features"] if row[f] in (None, "")]
    if missing:
        return {"model_status": "trained", "error": t("yield_missing_inputs", lang, list=", ".join(missing))}
    for f in ("state", "district", "season", "crop"):
        row[f] = _match(row[f], known.get(f, []))
    warns = [t("yield_unseen", lang, f=f, v=row[f]) for f in known if str(row[f]) not in known[f]]
    pred = float(bundle["pipeline"].predict(pd.DataFrame([row]))[0])
    return {
        "model_status": "trained", "predicted_yield": round(max(pred, 0), 3), "unit": bundle["unit"],
        "expected_total_production": round(max(pred, 0) * inp["area_hectares"], 2),
        "inputs_used": row, "warnings": warns,
        "metrics": registry.read_json("yield_metrics.json"),
        "disclaimer": t("yield_disclaimer", lang),
    }
