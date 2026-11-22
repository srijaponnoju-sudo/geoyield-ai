import io

from fastapi import APIRouter, File, HTTPException, Query, Response, UploadFile
from app.database import db
from app.i18n import LANGS, crop_name, norm, t
from app.schemas.schemas import CropRecommendationIn, FertilizerIn, SymptomIn, TTSIn, YieldIn
from app.services import registry, crop_service, disease_service, fertilizer_service, symptom_service, yield_service

router = APIRouter(prefix="/api")


def _save(relocalize: bool, *args) -> int | None:
    """History is saved once per real analysis; re-translating a result (language switch) is not saved again."""
    return None if relocalize else db.save_analysis(*args)


@router.get("/status")
def status():
    return {"app": "GeoYield AI", "database": "sqlite", "models": registry.status()}


@router.post("/crop/recommend")
def crop_recommend(body: CropRecommendationIn):
    inp = body.model_dump()
    lang = norm(body.lang)
    res = crop_service.recommend(inp)
    if res["model_status"] == "unavailable":
        raise HTTPException(503, res["message"])
    top = res["recommendations"][0]
    res["history_id"] = _save(body.relocalize, "crop_recommendation", inp, res,
                              t("sum_crop", lang, crop=top["crop_label"], p=round(top["model_probability"] * 100)),
                              {"model": "RandomForestClassifier", "status": "trained"})
    return res


@router.get("/yield/options")
def yield_options():
    return yield_service.options() or {"crops": [], "seasons": [], "states": [], "districts": {}}


@router.post("/yield/predict")
def yield_predict(body: YieldIn):
    inp = body.model_dump()
    lang = norm(body.lang)
    res = yield_service.predict(inp)
    if res["model_status"] == "unavailable":
        raise HTTPException(503, res["message"])
    if "error" in res:
        raise HTTPException(422, res["error"])
    res["history_id"] = _save(body.relocalize, "yield_prediction", inp, res,
                              t("sum_yield", lang, crop=inp["crop"], y=res["predicted_yield"]),
                              {"model": "sklearn regressor", "status": "trained"})
    return res


@router.post("/health/image")
async def health_image(file: UploadFile = File(...), crop: str | None = Query(None), lang: str = Query("en"),
                       relocalize: bool = Query(False)):
    data = await file.read()
    img, err = disease_service.validate_image(data, file.content_type, lang)
    if err:
        raise HTTPException(400, err)
    res = disease_service.predict(img, lang)
    if res["model_status"] == "unavailable":
        raise HTTPException(503, res["message"])
    res["history_id"] = _save(relocalize, "crop_health", {"method": "image", "crop": crop, "filename": file.filename, "lang": lang}, res,
                              t("sum_img", norm(lang), label=res["predicted_label"].replace("_", " "), p=round(res["confidence"] * 100)),
                              {"model": "Keras CNN", "status": "trained"})
    return res


@router.post("/health/symptoms")
def health_symptoms(body: SymptomIn):
    inp = body.model_dump()
    lang = norm(body.lang)
    res = symptom_service.analyze(inp)
    if not res["possible_conditions"] and res.get("message") and not (inp["symptoms"] or inp["description"]):
        raise HTTPException(422, res["message"])
    names = ", ".join(c["condition"] for c in res["possible_conditions"][:2]) or t("sum_nomatch", lang)
    inp["method"] = "symptoms"
    res["history_id"] = _save(body.relocalize, "crop_health", inp, res, t("sum_sym", lang, names=names),
                              {"model": "rule-based knowledge base", "status": "fallback"})
    return res


@router.get("/fertilizers")
def fertilizers(lang: str = Query("en")):
    lang = lang if lang in LANGS else "en"
    return {"fertilizers": fertilizer_service.list_fertilizers(),
            "crops": [{"code": c, "label": crop_name(c, lang)} for c in sorted(registry.crop_profile().keys())]}


@router.post("/fertilizer/evaluate")
def fertilizer_evaluate(body: FertilizerIn):
    inp = body.model_dump()
    lang = norm(body.lang)
    res = fertilizer_service.evaluate(inp)
    res["history_id"] = _save(body.relocalize, "fertilizer_evaluation", inp, res,
                              t("sum_fert", lang, f=inp["fertilizer"], crop=res.get("crop_label", inp["crop"]),
                                v=t("verdict_" + res["verdict"], lang)),
                              {"model": "rule-based + dataset-derived ranges", "status": "fallback"})
    return res


@router.post("/tts")
def tts(body: TTSIn):
    """Fallback voice for languages the user's PC has no voice for (uses gTTS; needs internet)."""
    lang = norm(body.lang)
    try:
        from gtts import gTTS
        buf = io.BytesIO()
        gTTS(text=body.text, lang=lang, tld="co.in" if lang == "en" else "com").write_to_fp(buf)
    except Exception:
        raise HTTPException(503, t("tts_fail", lang))
    return Response(content=buf.getvalue(), media_type="audio/mpeg")


@router.get("/history")
def history(module: str | None = Query(None), limit: int = Query(50, ge=1, le=200)):
    if module and module not in db.TABLES:
        raise HTTPException(422, f"module must be one of {list(db.TABLES)}")
    return {"items": db.list_history(module, limit)}
