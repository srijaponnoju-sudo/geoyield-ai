"""Checks for the soil helper (optional N/P/K, water availability, yield soil check, crop problems)."""
from app.services import crop_service, fertilizer_service, soil_service


def _crop(**kw):
    inp = dict(temperature=28.7, humidity=56, top_k=3, lang="en", state="Telangana", season="Kharif",
               N=None, P=None, K=None, ph=None, rainfall=None)
    inp.update(kw)
    return crop_service.recommend(inp)


def test_crop_works_from_soil_type_and_water_only():
    res = _crop(soil_type="Red soil", water="medium")
    assert res["model_status"] == "trained"
    assert set(res["estimated"]) == {"N", "P", "K", "ph", "rainfall"}
    assert res["low_confidence"] is True


def test_crop_levels_override_soil_type():
    res = _crop(soil_type="Red soil", n_level="high", p_level="high", k_level="high", water="high", ph=6.5)
    assert res["model_status"] == "trained" and "ph" not in res["estimated"]


def test_crop_asks_for_soil_info_when_nothing_given():
    res = _crop()
    assert res["model_status"] == "needs_input" and "soil" in res["message"].lower()


def test_typed_values_are_not_estimated():
    res = _crop(N=90, P=42, K=43, ph=6.5, rainfall=203, temperature=21, humidity=82)
    assert res["estimated"] == [] and res["recommendations"][0]["crop"] == "rice"


def test_levels_map_to_increasing_values():
    for nut, table in soil_service.LEVEL_VALUE.items():
        assert table["low"] < table["medium"] < table["high"], nut
    assert soil_service.RAIN_VALUE["low"] < soil_service.RAIN_VALUE["medium"] < soil_service.RAIN_VALUE["high"]


def test_yield_soil_check_only_for_known_crops_and_only_when_soil_given():
    assert soil_service.yield_soil_check({"crop": "Rice"}) is None
    ok = soil_service.yield_soil_check({"crop": "Rice", "soil_type": "Alluvial soil"})
    assert ok["available"] and ok["estimated"] and ok["lines"]
    assert soil_service.yield_soil_check({"crop": "Wheat", "soil_type": "Red soil"})["available"] is False


def test_fertilizer_estimates_missing_nutrients_from_levels():
    inp, est = soil_service.fill_nutrients({"soil_type": "Sandy soil", "k_level": "high"})
    assert est == ["N", "P", "K"] and inp["K"] == soil_service.LEVEL_VALUE["K"]["high"]
    res = fertilizer_service.evaluate(dict(inp, crop="rice", fertilizer="Urea", ph=None, lang="en"))
    assert res["verdict"] in ("suitable", "potentially_suitable")


def test_problem_note_flags_fertilizer_without_the_missing_nutrient():
    res = {"fertilizer_npk": [0, 0, 60]}
    note = soil_service.problem_note("n_def", res, "en")
    assert note["group"] == "nutrient" and note["missing"] == "N"
    assert soil_service.problem_note("leaf_spot", res, "en")["group"] == "disease"
    assert soil_service.problem_note("nonexistent", res, "en") is None


def test_problem_list_and_area_crops():
    assert {"n_def", "leaf_spot"} <= {p["id"] for p in soil_service.problem_list("te")}
    area = soil_service.common_crops("Telangana", "WARANGAL", "Kharif")
    assert area["scope"] == "district" and "Rice" in area["crops"]
    assert soil_service.common_crops("Telangana", "Nowhere")["scope"] == "state"