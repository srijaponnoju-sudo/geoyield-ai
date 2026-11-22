import io
import json
from PIL import Image, UnidentifiedImageError
from app.config import MAX_IMAGE_BYTES, MODELS_DIR, DISEASE_CONFIDENCE_THRESHOLD
from app.i18n import t, disease_guidance
from app.services import registry

_model = None


def _load():
    global _model
    if _model is None:
        import tensorflow as tf  # imported lazily so the API runs without TensorFlow
        _model = tf.keras.models.load_model(MODELS_DIR / "disease_model.keras")
    return _model


def validate_image(data: bytes, content_type: str | None, lang: str = "en"):
    if len(data) > MAX_IMAGE_BYTES:
        return None, t("img_big", lang, mb=MAX_IMAGE_BYTES // (1024 * 1024))
    if content_type not in ("image/jpeg", "image/png"):
        return None, t("img_type", lang)
    try:
        img = Image.open(io.BytesIO(data)); img.verify()
        img = Image.open(io.BytesIO(data)).convert("RGB")
    except (UnidentifiedImageError, OSError):
        return None, t("img_invalid", lang)
    if min(img.size) < 64:
        return None, t("img_small", lang)
    return img, None


def predict(img: Image.Image, lang: str = "en") -> dict:
    if not registry.disease_model_ready():
        return {"model_status": "unavailable", "message": t("img_unavailable", lang)}
    import numpy as np
    classes = json.loads((MODELS_DIR / "disease_classes.json").read_text())
    size = registry.read_json("disease_metrics.json").get("image_size", 224)
    x = np.asarray(img.resize((size, size)), dtype="float32")[None]
    probs = _load().predict(x, verbose=0)[0]
    top = probs.argsort()[::-1][:3]
    best = float(probs[top[0]])
    res = {
        "model_status": "trained",
        "top_predictions": [{"label": classes[i], "confidence": round(float(probs[i]), 4)} for i in top],
        "predicted_label": classes[top[0]], "confidence": round(best, 4),
        "supported_classes": classes, "guidance": disease_guidance(classes[top[0]], lang),
        "disclaimer": t("img_disclaimer", lang),
    }
    if best < DISEASE_CONFIDENCE_THRESHOLD:
        res["low_confidence"] = True
        res["warning"] = t("img_lowconf", lang)
    return res
