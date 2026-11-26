"""'Was this right?' feedback. Saves what really happened, so we can measure REAL accuracy later.

Tables are created here (CREATE IF NOT EXISTS), so no change to the existing database code is needed.
One feedback row per (module, history_id): sending again updates the same row.
"""
import csv
import io
import json
from datetime import datetime, timezone

from app.database import db

MODULES = ("yield_prediction", "crop_recommendation", "profit_comparison")

# profit comparisons are saved in history like the other modules
db.TABLES.setdefault("profit_comparison", "profit_comparisons")

SCHEMA = """
CREATE TABLE IF NOT EXISTS profit_comparisons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    farmer_input_id INTEGER REFERENCES farmer_inputs(id),
    result_json TEXT NOT NULL, summary TEXT, model_info TEXT, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module TEXT NOT NULL, history_id INTEGER, correct INTEGER NOT NULL,
    state TEXT, district TEXT, crop TEXT, season TEXT,
    predicted_value REAL, predicted_text TEXT,
    actual_yield REAL, actual_crop TEXT, actual_price REAL, comment TEXT,
    created_at TEXT NOT NULL
);
"""


def ensure_tables() -> None:
    with db.connect() as c:
        c.executescript(SCHEMA)


def _snapshot(module: str, history_id: int | None) -> dict:
    """What the app predicted (and for which farm), read from saved history."""
    if not history_id or module not in db.TABLES:
        return {}
    try:
        with db.connect() as c:
            r = c.execute(f"SELECT h.result_json, f.input_json FROM {db.TABLES[module]} h "
                          f"JOIN farmer_inputs f ON f.id = h.farmer_input_id WHERE h.id = ?", (history_id,)).fetchone()
        if not r:
            return {}
        res, inp = json.loads(r["result_json"]), json.loads(r["input_json"])
    except Exception:
        return {}
    snap = {"state": inp.get("state"), "district": inp.get("district"), "season": inp.get("season"),
            "crop": inp.get("crop")}
    if module == "yield_prediction":
        snap["predicted_value"] = res.get("predicted_yield")
    elif module == "crop_recommendation":
        recs = res.get("recommendations") or []
        snap["predicted_text"] = recs[0]["crop"] if recs else None
        snap["crop"] = snap["predicted_text"]
    elif module == "profit_comparison":
        snap["predicted_text"] = res.get("best")
        snap["crop"] = res.get("best")
    return snap


def submit(module: str, history_id: int | None, correct: bool, actual_yield=None, actual_crop=None,
           actual_price=None, comment=None) -> dict:
    snap = _snapshot(module, history_id)
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    vals = (int(correct), snap.get("state"), snap.get("district"), snap.get("crop"), snap.get("season"),
            snap.get("predicted_value"), snap.get("predicted_text"), actual_yield, actual_crop, actual_price,
            (comment or "").strip() or None)
    with db.connect() as c:
        old = c.execute("SELECT id FROM feedback WHERE module=? AND history_id=?", (module, history_id)).fetchone() \
            if history_id else None
        if old:
            c.execute("UPDATE feedback SET correct=?, state=?, district=?, crop=?, season=?, predicted_value=?, "
                      "predicted_text=?, actual_yield=?, actual_crop=?, actual_price=?, comment=?, created_at=? "
                      "WHERE id=?", (*vals, now, old["id"]))
            return {"id": old["id"], "updated": True}
        cur = c.execute("INSERT INTO feedback (module, history_id, correct, state, district, crop, season, "
                        "predicted_value, predicted_text, actual_yield, actual_crop, actual_price, comment, created_at) "
                        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (module, history_id, *vals, now))
        return {"id": cur.lastrowid, "updated": False}


def summary() -> dict:
    by = {}
    with db.connect() as c:
        for m in MODULES:
            n, right = c.execute("SELECT COUNT(*), COALESCE(SUM(correct),0) FROM feedback WHERE module=?", (m,)).fetchone()
            by[m] = {"count": n, "right": int(right), "wrong": n - int(right),
                     "percent_right": round(100 * right / n, 1) if n else None}
        rows = c.execute("SELECT predicted_value, actual_yield FROM feedback WHERE module='yield_prediction' "
                         "AND predicted_value IS NOT NULL AND actual_yield IS NOT NULL AND actual_yield > 0").fetchall()
    yerr = None
    if rows:
        errs = [abs(r["predicted_value"] - r["actual_yield"]) for r in rows]
        pct = [e / r["actual_yield"] * 100 for e, r in zip(errs, rows)]
        yerr = {"count": len(rows), "mae_t_per_ha": round(sum(errs) / len(errs), 3),
                "mean_pct_error": round(sum(pct) / len(pct), 1),
                "within_20_percent": round(100 * sum(1 for p in pct if p <= 20) / len(pct), 1)}
    return {"total": sum(v["count"] for v in by.values()), "by_module": by, "yield_error": yerr}


def export_csv() -> str:
    with db.connect() as c:
        rows = c.execute("SELECT * FROM feedback ORDER BY id").fetchall()
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(rows[0].keys() if rows else ["id", "module", "history_id", "correct"])
    for r in rows:
        w.writerow(list(r))
    return buf.getvalue()
