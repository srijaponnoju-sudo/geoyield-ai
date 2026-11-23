"""Automated checks for the GeoYield AI backend logic.

Run from the backend folder:   .\venv\Scripts\python.exe -m pytest -q
These call the service layer directly (no server needed) and use the trained models in models_store.
"""
import json
import re
from pathlib import Path

from app.config import DATA_DIR
from app.services import crop_service, fertilizer_service, regional_service, symptom_service, yield_service

APP_DIR = Path(__file__).resolve().parent.parent / "app"
EXAMPLE = dict(N=90, P=42, K=43, ph=6.5, temperature=21, humidity=82, rainfall=203, top_k=3, lang="en")


# ---------- crop recommendation ----------
def test_crop_example_recommends_rice_with_high_confidence():
    res = crop_service.recommend(dict(EXAMPLE))
    assert res["model_status"] == "trained"
    assert len(res["recommendations"]) == 3
    top = res["recommendations"][0]
    assert top["crop"] == "rice"
    assert top["model_probability"] > 0.5
    assert res["low_confidence"] is False


def test_crop_unusual_inputs_raise_low_confidence_warning():
    odd = dict(EXAMPLE, N=106, P=78, K=66, ph=10, temperature=36, humidity=68)
    res = crop_service.recommend(odd)
    assert res["low_confidence"] is True


def test_crop_probabilities_are_valid():
    res = crop_service.recommend(dict(EXAMPLE))
    probs = [r["model_probability"] for r in res["recommendations"]]
    assert probs == sorted(probs, reverse=True)
    assert all(0 <= p <= 1 for p in probs)


# ---------- regional check ----------
def test_regional_recorded_and_not_recorded():
    assert regional_service.check("rice", "Telangana", "Kharif")["status"] == "recorded"
    assert regional_service.check("coffee", "Telangana", None)["status"] == "not_recorded"


def test_regional_unknown_when_nothing_to_check():
    assert regional_service.check("rice", None, None)["status"] == "unknown"
    assert regional_service.check("muskmelon", "Punjab", None)["status"] == "unknown"


def test_regional_whole_year_counts_as_every_season():
    res = regional_service.check("coconut", "Andhra Pradesh", "Summer")
    assert res["status"] == "recorded" and res["in_season"] is True


def test_regional_message_in_all_languages():
    for lang in ("en", "hi", "te"):
        msg = regional_service.message("rice", "rice", "Telangana", "Kharif", lang)
        assert msg and msg["text"] and msg["ok"] is True


# ---------- yield prediction ----------
def test_yield_prediction_is_positive_and_scales_with_area():
    base = dict(state="Telangana", district="WARANGAL", season="Kharif", crop="Rice", area_hectares=1, lang="en")
    one = yield_service.predict(dict(base))
    ten = yield_service.predict(dict(base, area_hectares=10))
    assert one["model_status"] == "trained"
    assert one["predicted_yield"] > 0
    assert abs(ten["expected_total_production"] - 10 * one["predicted_yield"]) < 0.1


# ---------- fertilizer evaluation ----------
def _fert(**kw):
    inp = dict(crop="rice", fertilizer="Urea", N=10, P=45, K=40, lang="en")
    inp.update(kw)
    return fertilizer_service.evaluate(inp)


def test_fertilizer_suitable_when_it_supplies_the_missing_nutrient():
    assert _fert()["verdict"] == "suitable"


def test_fertilizer_unsuitable_when_nutrient_not_needed():
    res = _fert(fertilizer="MOP (Muriate of Potash)")
    assert res["verdict"] == "unsuitable"
    assert res["alternative"] is not None


def test_fertilizer_never_gives_a_dosage():
    text = json.dumps(_fert()).lower()
    assert "kg/ha" not in text and "dosage" not in text.replace("no dosage", "")


def test_fertilizer_unknown_crop_cannot_be_evaluated():
    assert _fert(crop="notacrop")["verdict"] == "cannot_evaluate"


# ---------- symptoms (also guards the Windows UTF-8 bug) ----------
def test_symptoms_work_in_english_hindi_and_telugu():
    for lang in ("en", "hi", "te"):
        res = symptom_service.analyze({"symptoms": ["Yellow leaves"], "description": "", "lang": lang})
        assert res["possible_conditions"], lang


def test_symptoms_empty_input_asks_to_select():
    res = symptom_service.analyze({"symptoms": [], "description": "", "lang": "en"})
    assert res["possible_conditions"] == []


def test_data_json_files_are_valid_utf8():
    for name in ("symptoms.json", "symptoms_i18n.json", "fertilizers.json"):
        json.loads((DATA_DIR / name).read_text(encoding="utf-8"))


def test_no_text_read_without_explicit_encoding():
    bad = []
    for path in APP_DIR.rglob("*.py"):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.search(r"\.read_text\(\s*\)", line):
                bad.append(f"{path.name}:{n}")
    assert not bad, "read_text() without encoding (breaks on Windows): " + ", ".join(bad)