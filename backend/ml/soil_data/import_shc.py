"""Builds backend/app/data/district_soil.csv from Soil Health Card CSV files you download
(for example "Soil Health Data: District and Village wise Soil Health Information for Telangana" on dataful.in).

Usage (from the backend folder):
    python ml/soil_data/import_shc.py "C:\\path\\telangana.csv" [--state Telangana]

Standard Soil Health Card classes (kg/ha): N <280 low, 280-560 medium, >560 high; P <10 low, 10-25 medium, >25 high;
K <120 low, 120-280 medium, >280 high. The script finds the columns by name, takes the MEDIAN value of each district
and turns it into Low / Medium / High. If a column already holds the words Low/Medium/High it uses the most common one.
It prints what it found and writes nothing if it cannot find districts and at least one nutrient.
"""
import argparse
import re
import sys
from pathlib import Path

import pandas as pd

OUT = Path(__file__).resolve().parents[2] / "app" / "data" / "district_soil.csv"
LIMITS = {"n": (280, 560), "p": (10, 25), "k": (120, 280)}


def _norm(c) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(c).lower()).strip()


def find(cols, test):
    return next((c for c in cols if test(_norm(c))), None)


def to_level(series: pd.Series, nut: str):
    num = pd.to_numeric(series, errors="coerce")
    if num.notna().mean() >= 0.5:
        v = float(num.median())
        lo, hi = LIMITS[nut]
        return "low" if v < lo else ("medium" if v <= hi else "high")
    words = series.astype(str).str.lower().str.extract(r"(low|medium|high)", expand=False).dropna()
    return words.mode().iloc[0] if not words.empty else ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--state", default=None, help="needed only if the file has no state column")
    args = ap.parse_args()
    frames = []
    for f in args.files:
        d = pd.read_csv(f, dtype=str, encoding="utf-8-sig", low_memory=False)
        cols = list(d.columns)
        c_state = find(cols, lambda s: "state" in s)
        c_dist = find(cols, lambda s: "district" in s)
        c = {
            "n": find(cols, lambda s: "nitrogen" in s or s in ("n", "avail n") or s.startswith("n ")),
            "p": find(cols, lambda s: "phosph" in s or s in ("p", "p2o5") or s.startswith("p ")),
            "k": find(cols, lambda s: "potass" in s or s in ("k", "k2o") or s.startswith("k ")),
            "ph": find(cols, lambda s: re.search(r"\bph\b", s) is not None),
        }
        print(f"{Path(f).name}: district={c_dist!r} state={c_state!r} N={c['n']!r} P={c['p']!r} K={c['k']!r} pH={c['ph']!r}")
        if not c_dist or not any(c[k] for k in "npk"):
            print("  -> could not find a district column and at least one of N/P/K. Skipped.")
            continue
        if not c_state and not args.state:
            print("  -> no state column: add  --state <name>. Skipped.")
            continue
        d["_state"] = d[c_state].str.strip() if c_state else args.state
        d["_district"] = d[c_dist].str.strip()
        d = d[d["_district"].notna() & (d["_district"] != "")]
        frames.append((d, c))
    rows = []
    for d, c in frames:
        for (st, di), g in d.groupby(["_state", "_district"]):
            row = {"state": st, "district": di}
            for nut in "npk":
                row[nut + "_level"] = to_level(g[c[nut]], nut) if c[nut] else ""
            ph = pd.to_numeric(g[c["ph"]], errors="coerce").median() if c["ph"] else float("nan")
            row["ph"] = "" if pd.isna(ph) else round(float(ph), 2)
            rows.append(row)
    if not rows:
        print("Nothing imported. The file was not changed.")
        sys.exit(1)
    new = pd.DataFrame(rows, columns=["state", "district", "n_level", "p_level", "k_level", "ph"])
    if OUT.exists():
        old = pd.read_csv(OUT, dtype=str).fillna("")
        key = set(zip(new.state.str.lower(), new.district.str.lower()))
        old = old[[(s.lower(), d.lower()) not in key for s, d in zip(old.state, old.district)]]
        new = pd.concat([old, new], ignore_index=True)
    new.to_csv(OUT, index=False)
    print(f"Wrote {len(new)} districts to {OUT}")


if __name__ == "__main__":
    main()