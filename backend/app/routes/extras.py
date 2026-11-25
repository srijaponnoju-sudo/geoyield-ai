from fastapi import APIRouter, Query
from app.i18n import norm
from app.services import soil_service

router = APIRouter(prefix="/api")


@router.get("/problems")
def problems(lang: str = Query("en")):
    return {"problems": soil_service.problem_list(norm(lang))}


@router.get("/area/crops")
def area_crops(state: str = Query(..., max_length=60), district: str | None = Query(None, max_length=60),
               season: str | None = Query(None, max_length=20)):
    return soil_service.common_crops(state, district, season)