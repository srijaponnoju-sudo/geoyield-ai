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
