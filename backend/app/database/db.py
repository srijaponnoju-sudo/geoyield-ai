"""SQLite storage for farmer inputs and every module's analysis history."""
import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from app.config import DB_PATH

TABLES = {
    "crop_recommendation": "crop_recommendations",
    "yield_prediction": "yield_predictions",
    "crop_health": "health_analyses",
    "fertilizer_evaluation": "fertilizer_evaluations",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS farmer_inputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module TEXT NOT NULL,
    state TEXT, district TEXT, village TEXT,
    input_json TEXT NOT NULL,
    created_at TEXT NOT NULL
);
""" + "".join(
    f"""
CREATE TABLE IF NOT EXISTS {t} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    farmer_input_id INTEGER REFERENCES farmer_inputs(id),
    result_json TEXT NOT NULL,
    summary TEXT,
    model_info TEXT,
    created_at TEXT NOT NULL
);
""" for t in TABLES.values()
)


@contextmanager
def connect():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with connect() as c:
        c.executescript(SCHEMA)


def save_analysis(module: str, inputs: dict, result: dict, summary: str, model_info: dict) -> int:
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with connect() as c:
        cur = c.execute(
            "INSERT INTO farmer_inputs (module,state,district,village,input_json,created_at) VALUES (?,?,?,?,?,?)",
            (module, inputs.get("state"), inputs.get("district"), inputs.get("village"),
             json.dumps(inputs, default=str), now),
        )
        fid = cur.lastrowid
        cur = c.execute(
            f"INSERT INTO {TABLES[module]} (farmer_input_id,result_json,summary,model_info,created_at) VALUES (?,?,?,?,?)",
            (fid, json.dumps(result, default=str), summary, json.dumps(model_info, default=str), now),
        )
        return cur.lastrowid


def list_history(module: str | None = None, limit: int = 50) -> list[dict]:
    mods = [module] if module else list(TABLES)
    rows: list[dict] = []
    with connect() as c:
        for m in mods:
            q = f"""SELECT h.id, h.summary, h.result_json, h.model_info, h.created_at, f.input_json
                    FROM {TABLES[m]} h JOIN farmer_inputs f ON f.id = h.farmer_input_id
                    ORDER BY h.id DESC LIMIT ?"""
            for r in c.execute(q, (limit,)):
                rows.append({
                    "module": m, "id": r["id"], "summary": r["summary"],
                    "inputs": json.loads(r["input_json"]), "result": json.loads(r["result_json"]),
                    "model_info": json.loads(r["model_info"] or "{}"), "created_at": r["created_at"],
                })
    rows.sort(key=lambda x: x["created_at"], reverse=True)
    return rows[:limit]
