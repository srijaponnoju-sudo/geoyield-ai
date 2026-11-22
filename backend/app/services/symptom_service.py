import json
from app.config import DATA_DIR
from app.i18n import t, norm


def analyze(inp: dict) -> dict:
    lang = norm(inp.get("lang"))
    kb = json.loads((DATA_DIR / "symptoms.json").read_text())["conditions"]
    tr = json.loads((DATA_DIR / "symptoms_i18n.json").read_text())
    text = " ".join(inp.get("symptoms", []) + [inp.get("description") or ""]).lower()
    if not text.strip():
        return {"method": t("sym_method", lang), "possible_conditions": [], "message": t("sym_select", lang)}
    found = []
    for c in kb:
        # match English keywords, and Hindi/Telugu keywords so free text in any language works
        kws = list(c["keywords"]) + tr["hi"][c["id"]]["keywords"] + tr["te"][c["id"]]["keywords"]
        hits = [k for k in kws if k.lower() in text]
        if not hits:
            continue
        loc = tr.get(lang, {}).get(c["id"], {})
        found.append({
            "id": c["id"], "condition": loc.get("name", c["name"]), "kind": c["kind"],
            "supporting_symptoms": hits, "match_score": round(len(hits) / len(kws), 2),
            "recommended_next_steps": loc.get("next_steps", c["next_steps"]),
            "preventive_measures": loc.get("prevention", c["prevention"]),
        })
    found.sort(key=lambda x: (len(x["supporting_symptoms"]), x["match_score"]), reverse=True)
    return {
        "method": t("sym_method", lang), "possible_conditions": found[:4],
        "message": None if found else t("sym_nomatch", lang), "disclaimer": t("sym_disclaimer", lang),
    }
