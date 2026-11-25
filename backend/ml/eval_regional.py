"""Realism check for the local (regional) adjustment. Run from the backend folder:  python ml/eval_regional.py
For 400 sample soil/weather rows placed in random states, it reports how many of the top-3 crops are actually
recorded in that state in the government data - before and after the local check.
This measures realism, NOT real-world accuracy (that needs farm results)."""
import random
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pandas as pd

from app.services import regional_rank, registry
from app.services.regional_service import CROP_MAP

bundle = registry.crop_model()
feats, classes = bundle["features"], list(bundle["model"].classes_)
rows = pd.read_csv(Path(__file__).resolve().parent / "datasets" / "Crop_recommendation.csv").sample(400, random_state=1)
proba = bundle["model"].predict_proba(rows[feats])
recorded = {s: set(g.code) for s, g in regional_rank._data().groupby("State_Name")}
states = sorted(recorded)
random.seed(1)
stats = {"before": [0, 0], "after": [0, 0]}
for p, x in zip(proba, rows[feats].values):
    st = random.choice(states)
    adj, _ = regional_rank.adjust(p, classes, st, None, None, x, feats)
    for name, arr in (("before", p), ("after", adj)):
        for i in arr.argsort()[::-1][:3]:
            if CROP_MAP.get(classes[i]) is None:
                continue
            stats[name][1] += 1
            stats[name][0] += classes[i] in recorded[st]
for k, (ok, n) in stats.items():
    print(f"{k:>6}: {ok}/{n} top-3 crops are recorded in the state = {100 * ok / n:.1f}%")