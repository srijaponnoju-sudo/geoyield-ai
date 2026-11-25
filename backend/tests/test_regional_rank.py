"""Checks for the local reality check, crop rotation hints and the Soil Health Card district hook."""
import numpy as np

from app.services import crop_service, regional_rank, soil_service


def test_adjust_sums_to_one_and_penalises_unrecorded_crops():
    classes = np.array(["rice", "coffee", "maize"])
    adj, applied = regional_rank.adjust(np.array([0.3, 0.4, 0.3]), classes, "Telangana", None, "Kharif")
    assert applied and abs(adj.sum() - 1) < 1e-9
    assert adj[1] < 0.4 and adj[0] > 0.3          # coffee is not recorded in Telangana, rice is


def test_adjust_does_nothing_without_a_state():
    p = np.array([0.5, 0.5])
    adj, applied = regional_rank.adjust(p, np.array(["rice", "coffee"]), None)
    assert not applied and list(adj) == [0.5, 0.5]


def test_rotation_hints():
    assert regional_rank.rotation("rice", "rice") == "repeat"
    assert regional_rank.rotation("chickpea", "rice") == "after_legume"
    assert regional_rank.rotation("rice", "chickpea") == "legume_next"
    assert regional_rank.rotation(None, "rice") is None


def test_recommend_reports_local_check_and_rotation():
    res = crop_service.recommend(dict(temperature=28.7, humidity=56, top_k=3, lang="en", state="Telangana", season="Kharif",
                                      N=90, P=42, K=43, ph=6.5, rainfall=100, last_crop="rice"))
    assert res["regional_applied"] is True
    assert all("adjusted_probability" in r for r in res["recommendations"])
    probs = [r["adjusted_probability"] for r in res["recommendations"]]
    assert probs == sorted(probs, reverse=True)


def test_irrigation_raises_low_rainfall_and_is_marked_estimated():
    inp, est = soil_service.fill_crop_inputs(dict(N=50, P=40, K=40, ph=6.5, rainfall=20, irrigation="irrigated"))
    assert inp["rainfall"] == soil_service.RAIN_VALUE["medium"] and "rainfall" in est
    inp2, _ = soil_service.fill_crop_inputs(dict(N=50, P=40, K=40, ph=6.5, rainfall=20, irrigation="rainfed"))
    assert inp2["rainfall"] == 20


def test_district_soil_file_is_used_before_soil_type_rule(monkeypatch):
    table = {("telangana", "warangal"): {"n_level": "high", "p_level": "", "k_level": "low", "ph": "7.9"}}
    monkeypatch.setattr(soil_service, "_district_table", lambda: table)
    inp, est = soil_service.fill_nutrients({"state": "Telangana", "district": "Warangal", "soil_type": "Red soil"}, with_ph=True)
    assert inp["N"] == soil_service.LEVEL_VALUE["N"]["high"]          # from the district file
    assert inp["P"] == soil_service.LEVEL_VALUE["P"]["low"]           # district level blank -> soil-type rule
    assert inp["K"] == soil_service.LEVEL_VALUE["K"]["low"] and inp["ph"] == 7.9