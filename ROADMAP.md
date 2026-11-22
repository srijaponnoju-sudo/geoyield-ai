# GeoYield AI - how to grow this into a real product

## What the hackathon version already does
Four independent modules (crop recommendation, yield prediction, crop health, fertilizer evaluation), SQLite history,
English / Hindi / Telugu, voice assistant, honest model-status reporting.

## Phase 1 - make the current features more accurate (1-3 months)
- Replace the rule-based fertilizer crop ranges with official PJTSAU / ICAR / Soil Health Card recommendations, reviewed by an agronomist.
- Add real weather (IMD / OpenWeather) for the farmer's village instead of manual typing, and use it in crop and yield models.
- Train yield and crop models on local data (district-wise soil and weather) rather than only national datasets.
- Fine-tune the leaf model on real field photos taken by farmers (PlantVillage is lab-style).
- Add more crops and diseases, with agronomist-approved treatment advice (no chemical doses without expert sign-off).
- Have native speakers review and extend Hindi / Telugu text; add Tamil, Kannada, Marathi.

## Phase 2 - reach farmers where they are (3-6 months)
- WhatsApp bot and phone (IVR) access in local languages; offline-capable mobile app (PWA / Flutter).
- Login with farmer profiles, multiple plots, and a season-wise crop diary.
- Soil Health Card import (QR / number) so soil values fill in automatically.
- SMS / WhatsApp alerts: weather warnings, pest outbreaks, sowing windows.

## Phase 3 - connect to the wider farming ecosystem (6-12 months)
- Mandi prices (Agmarknet / eNAM) and "which crop earns more" comparison.
- Government schemes: PM-KISAN, crop insurance (PMFBY), subsidy eligibility.
- Satellite crop-health maps (Sentinel-2 / ISRO Bhuvan NDVI) and drought / flood early warnings (fits the PPT's disaster-management domain).
- IoT soil sensors and drone images for large farms; agri-input shop and FPO marketplace links.

## Phase 4 - trust, safety, scale
- Field pilots with farmers and extension officers; measure real yield and cost savings.
- Model monitoring (accuracy drift), versioning, audit logs; PostgreSQL + cloud hosting; Docker + CI/CD.
- Privacy and consent for farmer data; explainability for every recommendation; human-expert escalation (KVK helpline).
