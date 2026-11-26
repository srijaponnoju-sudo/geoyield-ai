from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import ALLOWED_ORIGINS
from app.database import db
from app.routes.api import router
from app.routes.extras import router as extras_router
from app.routes.upgrade import router as upgrade_router
from app.services import bot_service, feedback_service


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_db()
    feedback_service.ensure_tables()  # profit history + feedback tables
    bot_service.ensure_tables()       # bot language memory
    yield


app = FastAPI(title="GeoYield AI API", description="Smart Farming. Better Yield. - Team Vibe_coders, AAROHAN 2.0",
              version="1.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=ALLOWED_ORIGINS, allow_methods=["*"], allow_headers=["*"])
app.include_router(router)
app.include_router(extras_router)
app.include_router(upgrade_router)


@app.get("/")
def root():
    return {"app": "GeoYield AI", "docs": "/docs", "status": "/api/status"}
