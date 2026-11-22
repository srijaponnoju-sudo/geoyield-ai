"""Loads models once and reports honestly whether each is trained, unavailable, or a fallback."""
import json
from functools import lru_cache
import joblib
from app.config import MODELS_DIR


@lru_cache(maxsize=1)
def crop_model():
    p = MODELS_DIR / "crop_recommendation.joblib"
    return joblib.load(p) if p.exists() else None


@lru_cache(maxsize=1)
def crop_profile() -> dict:
    p = MODELS_DIR / "crop_profile.json"
    return json.loads(p.read_text()) if p.exists() else {}


def read_json(name: str) -> dict:
    p = MODELS_DIR / name
    return json.loads(p.read_text()) if p.exists() else {}


def yield_model():
    p = MODELS_DIR / "yield_model.joblib"
    return joblib.load(p) if p.exists() else None


def disease_model_ready() -> bool:
    return (MODELS_DIR / "disease_model.keras").exists() and (MODELS_DIR / "disease_classes.json").exists()


def status() -> dict:
    return {
        "crop_recommendation": {
            "status": "trained" if crop_model() else "unavailable",
            "metrics": read_json("crop_recommendation_metrics.json") or None,
        },
        "yield_prediction": {
            "status": "trained" if yield_model() else "unavailable",
            "metrics": read_json("yield_metrics.json") or None,
        },
        "disease_detection": {
            "status": "trained" if disease_model_ready() else "unavailable",
            "metrics": read_json("disease_metrics.json") or None,
        },
        "symptom_analysis": {"status": "fallback (rule-based knowledge base, not a trained model)"},
        "fertilizer_evaluation": {"status": "rule-based on reference grades + dataset-derived crop nutrient ranges"},
    }
