"""New endpoints: profit mode, government schemes, 'was this right?' feedback, WhatsApp/SMS bot."""
import base64
import hashlib
import hmac
import os
from typing import Literal, Optional
from xml.sax.saxutils import escape

from fastapi import APIRouter, Form, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field

from app.database import db
from app.i18n import norm, t
from app.schemas.schemas import Location
from app.services import bot_service, feedback_service, prices, profit_service, schemes_service

router = APIRouter(prefix="/api")


# ---------------- profit mode ----------------
class ProfitIn(Location):
    season: str = Field(..., min_length=2, max_length=20)
    area: float = Field(..., gt=0, le=100000)
    area_unit: Literal["acre", "hectare"] = "acre"
    crops: Optional[list[str]] = Field(None, max_length=15)
    prices: dict[str, float] = Field(default_factory=dict, description="crop -> Rs per quintal typed by the farmer")
    costs: dict[str, float] = Field(default_factory=dict, description="crop -> cost per acre/hectare typed by the farmer")


@router.get("/profit/options")
def profit_options(state: str = Query(..., max_length=60), district: str | None = Query(None, max_length=60),
                   season: str | None = Query(None, max_length=20)):
    return {"candidates": profit_service.candidates(state, district, season), "all_crops": profit_service.addable_crops(),
            "live_prices_enabled": prices.has_key()}


@router.post("/profit/compare")
def profit_compare(body: ProfitIn):
    inp = body.model_dump()
    inp["state"] = body.state or ""
    lang = norm(body.lang)
    if not body.state:
        raise HTTPException(422, "state is required")
    res = profit_service.compare(inp)
    if res.get("model_status") == "unavailable":
        raise HTTPException(503, res["message"])
    if res.get("error") == "no_crops":
        raise HTTPException(422, "No crops to compare. Pick at least one crop.")
    best = res.get("best") or "-"
    res["history_id"] = None if body.relocalize else db.save_analysis(
        "profit_comparison", {k: v for k, v in inp.items() if k != "relocalize"}, res,
        t("sum_profit", lang, crop=best), {"model": "yield model x price", "status": "trained"})
    return res


# ---------------- government schemes ----------------
@router.get("/schemes")
def schemes(state: str | None = Query(None, max_length=60), crop: str | None = Query(None, max_length=60),
            season: str | None = Query(None, max_length=20), lang: str = Query("en")):
    return schemes_service.for_farmer(state, crop, season, norm(lang))


# ---------------- "Was this right?" ----------------
class FeedbackIn(BaseModel):
    module: Literal["yield_prediction", "crop_recommendation", "profit_comparison"]
    history_id: Optional[int] = Field(None, ge=1)
    correct: bool
    actual_yield: Optional[float] = Field(None, ge=0, le=500, description="real yield, tonnes per hectare")
    actual_crop: Optional[str] = Field(None, max_length=60)
    actual_price: Optional[float] = Field(None, ge=0, le=10000000)
    comment: Optional[str] = Field(None, max_length=500)


@router.post("/feedback")
def feedback(body: FeedbackIn):
    return feedback_service.submit(body.module, body.history_id, body.correct, body.actual_yield,
                                   body.actual_crop, body.actual_price, body.comment)


@router.get("/feedback/summary")
def feedback_summary():
    return feedback_service.summary()


@router.get("/feedback/export")
def feedback_export():
    return Response(content=feedback_service.export_csv(), media_type="text/csv",
                    headers={"Content-Disposition": "attachment; filename=geoyield_feedback.csv"})


# ---------------- WhatsApp / SMS bot ----------------
class BotIn(BaseModel):
    text: str = Field(..., max_length=500)
    phone: str = Field("", max_length=30)


@router.post("/bot/message")
def bot_message(body: BotIn):
    """Same brain as the Twilio hook, as plain JSON (for testing without Twilio)."""
    return bot_service.handle(body.text, body.phone)


def twilio_signature(token: str, url: str, params: dict) -> str:
    data = url + "".join(k + params[k] for k in sorted(params))
    return base64.b64encode(hmac.new(token.encode(), data.encode(), hashlib.sha1).digest()).decode()


@router.post("/bot/twilio")
async def bot_twilio(request: Request, From: str = Form(""), Body: str = Form("")):
    """Twilio webhook (WhatsApp and SMS use the same format). Replies with TwiML."""
    token, public = os.getenv("TWILIO_AUTH_TOKEN", ""), os.getenv("BOT_PUBLIC_URL", "").rstrip("/")
    if token and public:  # check the message really comes from Twilio
        form = dict((await request.form()).items())
        sent = request.headers.get("X-Twilio-Signature", "")
        if not hmac.compare_digest(sent, twilio_signature(token, public + "/api/bot/twilio", form)):
            raise HTTPException(403, "bad signature")
    reply = bot_service.handle(Body, From)["reply"][:1500]
    xml = f'<?xml version="1.0" encoding="UTF-8"?><Response><Message>{escape(reply)}</Message></Response>'
    return Response(content=xml, media_type="application/xml")
