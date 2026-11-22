import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

MODELS_DIR = BASE_DIR / "models_store"
DATA_DIR = BASE_DIR / "app" / "data"
DB_PATH = BASE_DIR / "geoyield.db"

ALLOWED_ORIGINS = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "http://localhost:5173,http://localhost:3000").split(",") if o.strip()]
MAX_IMAGE_BYTES = int(float(os.getenv("MAX_IMAGE_MB", "5")) * 1024 * 1024)
DISEASE_CONFIDENCE_THRESHOLD = float(os.getenv("DISEASE_CONFIDENCE_THRESHOLD", "0.60"))
OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY", "")
