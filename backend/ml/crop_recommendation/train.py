"""Train the crop recommendation model (Scikit-learn RandomForest).

Dataset: "Crop Recommendation Dataset" (N, P, K, temperature, humidity, ph, rainfall -> label, 2200 rows,
22 crops), a public dataset widely distributed on Kaggle / GitHub mirrors. Place the CSV at
backend/ml/datasets/Crop_recommendation.csv, then run:   python ml/crop_recommendation/train.py
Everything printed/saved here is computed from the data - nothing is hard-coded.
"""
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import StratifiedKFold, cross_val_score, train_test_split

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "ml" / "datasets" / "Crop_recommendation.csv"
OUT = ROOT / "models_store"
FEATURES = ["N", "P", "K", "temperature", "humidity", "ph", "rainfall"]


def main() -> None:
    if not CSV.exists():
        raise SystemExit(f"Dataset not found: {CSV}")
    df = pd.read_csv(CSV)
    df = df.dropna().drop_duplicates()
    X, y = df[FEATURES], df["label"]

    # Hold-out split is made BEFORE fitting anything, so there is no leakage.
    X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)
    model = RandomForestClassifier(n_estimators=300, random_state=42, n_jobs=-1)
    cv = cross_val_score(model, X_tr, y_tr, cv=StratifiedKFold(5, shuffle=True, random_state=42))
    model.fit(X_tr, y_tr)
    pred = model.predict(X_te)

    metrics = {
        "dataset": CSV.name, "rows_used": int(len(df)), "n_classes": int(y.nunique()),
        "test_accuracy": round(float(accuracy_score(y_te, pred)), 4),
        "test_macro_f1": round(float(f1_score(y_te, pred, average="macro")), 4),
        "cv5_accuracy_mean": round(float(cv.mean()), 4), "cv5_accuracy_std": round(float(cv.std()), 4),
        "feature_importance": {f: round(float(i), 4) for f, i in zip(FEATURES, model.feature_importances_)},
        "note": "Metrics are on a stratified 20% hold-out. The dataset is largely synthetic/clean, so real-field accuracy will be lower.",
    }
    # Per-crop ranges (10th-90th percentile) used only to EXPLAIN recommendations.
    g = df.groupby("label")[FEATURES]
    profile = {
        crop: {f: {"p10": round(float(np.percentile(d[f], 10)), 2), "p90": round(float(np.percentile(d[f], 90)), 2),
                   "mean": round(float(d[f].mean()), 2)} for f in FEATURES}
        for crop, d in g
    }
    OUT.mkdir(exist_ok=True)
    ranges = {f: {"min": round(float(df[f].min()), 3), "max": round(float(df[f].max()), 3)} for f in FEATURES}
    (OUT / "crop_feature_ranges.json").write_text(json.dumps(ranges, indent=2))
    joblib.dump({"model": model, "features": FEATURES}, OUT / "crop_recommendation.joblib")
    (OUT / "crop_recommendation_metrics.json").write_text(json.dumps(metrics, indent=2))
    (OUT / "crop_profile.json").write_text(json.dumps(profile, indent=2))
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
