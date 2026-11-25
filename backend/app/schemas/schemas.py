from typing import Optional
from pydantic import BaseModel, Field


class Location(BaseModel):
    lang: str = Field("en", max_length=5, description="en | hi | te")
    relocalize: bool = Field(False, description="re-run only to translate an existing result; not saved again")
    state: Optional[str] = Field(None, max_length=60)
    district: Optional[str] = Field(None, max_length=60)
    village: Optional[str] = Field(None, max_length=60)


class CropRecommendationIn(Location):
    soil_type: Optional[str] = Field(None, max_length=40)
    season: Optional[str] = Field(None, max_length=20)
    N: Optional[float] = Field(None, ge=0, le=300, description="Nitrogen")
    P: Optional[float] = Field(None, ge=0, le=300, description="Phosphorus")
    K: Optional[float] = Field(None, ge=0, le=400, description="Potassium")
    ph: Optional[float] = Field(None, ge=3, le=10)
    n_level: Optional[str] = Field(None, max_length=10)
    p_level: Optional[str] = Field(None, max_length=10)
    k_level: Optional[str] = Field(None, max_length=10)
    water: Optional[str] = Field(None, max_length=10, description="low | medium | high")
    temperature: float = Field(..., ge=0, le=55, description="deg C")
    humidity: float = Field(..., ge=0, le=100, description="%")
    rainfall: Optional[float] = Field(None, ge=0, le=500, description="mm")
    top_k: int = Field(3, ge=1, le=5)


class YieldIn(Location):
    crop: str = Field(..., min_length=2, max_length=60)
    season: str = Field(..., min_length=2, max_length=20)  # must match a trained season
    area_hectares: float = Field(..., gt=0, le=100000)
    soil_type: Optional[str] = None
    rainfall: Optional[float] = Field(None, ge=0, le=5000)
    N: Optional[float] = Field(None, ge=0, le=300)
    P: Optional[float] = Field(None, ge=0, le=300)
    K: Optional[float] = Field(None, ge=0, le=400)
    ph: Optional[float] = Field(None, ge=3, le=10)
    n_level: Optional[str] = Field(None, max_length=10)
    p_level: Optional[str] = Field(None, max_length=10)
    k_level: Optional[str] = Field(None, max_length=10)
    temperature: Optional[float] = Field(None, ge=0, le=55)
    humidity: Optional[float] = Field(None, ge=0, le=100)


class SymptomIn(Location):
    crop: Optional[str] = Field(None, max_length=60)
    symptoms: list[str] = Field(default_factory=list, max_length=20)
    description: Optional[str] = Field(None, max_length=1000)


class FertilizerIn(Location):
    crop: str = Field(..., min_length=2, max_length=60)
    soil_type: Optional[str] = None
    ph: Optional[float] = Field(None, ge=3, le=10)
    N: Optional[float] = Field(None, ge=0, le=300)
    P: Optional[float] = Field(None, ge=0, le=300)
    K: Optional[float] = Field(None, ge=0, le=400)
    n_level: Optional[str] = Field(None, max_length=10)
    p_level: Optional[str] = Field(None, max_length=10)
    k_level: Optional[str] = Field(None, max_length=10)
    problem: Optional[str] = Field(None, max_length=40)
    fertilizer: str = Field(..., min_length=2, max_length=60)
    custom_npk: Optional[list[float]] = Field(None, min_length=3, max_length=3,
                                              description="[N,P,K] % if the fertilizer is not in the database")


class TTSIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=1000)
    lang: str = Field("en", max_length=5)
