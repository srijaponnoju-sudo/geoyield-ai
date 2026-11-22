"""Train the crop yield regression model (Scikit-learn).

Dataset: "Crop Production in India" (State_Name, District_Name, Crop_Year, Season, Crop, Area, Production),
originally from the Government of India open data portal (data.gov.in). A copy is bundled at
backend/ml/datasets/crop_production.csv.   Run:   python ml/yield_prediction/train.py

Target = Production / Area. Crops whose production is NOT in tonnes (Coconut = nuts; Cotton(lint), Jute, Mesta = bales)
are excluded so that the output unit is genuinely tonnes per hectare.
The test set is the most recent two years (time-based split), so no future data leaks into training.
District is encoded with a TargetEncoder fitted inside the pipeline on training data only.
"""
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OrdinalEncoder, TargetEncoder

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "ml" / "datasets" / "crop_production.csv"
OUT = ROOT / "models_store"
CAT = ["state", "season", "crop"]
FEATURES = ["state", "district", "season", "crop", "area_hectares"]
NOT_TONNES = {"coconut", "cotton(lint)", "jute", "mesta"}


def main() -> None:
    if not CSV.exists():
        raise SystemExit(f"Dataset not found: {CSV}")
    df = pd.read_csv(CSV)
    df.columns = [c.strip() for c in df.columns]
    df = df.rename(columns={"State_Name": "state", "District_Name": "district", "Season": "season",
                            "Crop": "crop", "Area": "area_hectares"})
    for c in ["state", "district", "season", "crop"]:
        df[c] = df[c].astype(str).str.strip()
    rows_raw = len(df)
    df = df.dropna(subset=["Production", "area_hectares", "Crop_Year"])
    df = df[(df["area_hectares"] > 0) & (df["Production"] >= 0) & (~df["crop"].str.lower().isin(NOT_TONNES))]
    df["yield"] = df["Production"] / df["area_hectares"]
    df = df[df["yield"] <= df["yield"].quantile(0.995)]  # remove data-entry outliers

    cutoff = int(df["Crop_Year"].max()) - 1
    train, test = df[df["Crop_Year"] < cutoff], df[df["Crop_Year"] >= cutoff]
    pre = ColumnTransformer(
        [("cat", OrdinalEncoder(handle_unknown="use_encoded_value", unknown_value=-1), CAT),
         ("dist", TargetEncoder(random_state=42), ["district"])],
        remainder="passthrough")
    pipe = Pipeline([("pre", pre), ("reg", HistGradientBoostingRegressor(
        random_state=42, categorical_features=[0, 1, 2], max_iter=300))])
    pipe.fit(train[FEATURES], train["yield"])
    p = pipe.predict(test[FEATURES])

    base = test["crop"].map(train.groupby("crop")["yield"].mean()).fillna(train["yield"].mean())
    metrics = {
        "dataset": CSV.name, "rows_in_file": int(rows_raw), "train_rows": int(len(train)), "test_rows": int(len(test)),
        "split": f"time-based: train years < {cutoff}, test years >= {cutoff}",
        "MAE": round(float(mean_absolute_error(test["yield"], p)), 4),
        "RMSE": round(float(np.sqrt(mean_squared_error(test["yield"], p))), 4),
        "R2": round(float(r2_score(test["yield"], p)), 4),
        "baseline_crop_average_MAE": round(float(mean_absolute_error(test["yield"], base)), 4),
        "baseline_crop_average_R2": round(float(r2_score(test["yield"], base)), 4),
        "unit": "tonnes per hectare",
        "note": "Uses state, district, season, crop and area only (no weather columns exist in this dataset).",
    }
    OUT.mkdir(exist_ok=True)
    joblib.dump({"pipeline": pipe, "features": FEATURES, "unit": metrics["unit"],
                 "known_values": {c: sorted(train[c].unique().tolist()) for c in ["state", "district", "season", "crop"]}},
                OUT / "yield_model.joblib")
    (OUT / "yield_metrics.json").write_text(json.dumps(metrics, indent=2))
    # option lists for the frontend dropdowns (crops / seasons the model really knows)
    (OUT / "yield_options.json").write_text(json.dumps({
        "crops": sorted(train["crop"].unique().tolist()), "seasons": sorted(train["season"].unique().tolist()),
        "states": sorted(train["state"].unique().tolist()),
        "districts": {s: sorted(g["district"].unique().tolist()) for s, g in train.groupby("state")}}, indent=1))
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
