# Deploying GeoYield AI (guide - not yet tested on a live host)

The app has two parts that are deployed separately: the FastAPI backend and the React frontend.

## 1. Backend (FastAPI) - e.g. Render, Railway or any Python host
- Root directory: backend
- Build command: pip install -r requirements.txt
- Start command: uvicorn app.main:app --host 0.0.0.0 --port $PORT
- Environment variable: ALLOWED_ORIGINS = the URL of your deployed frontend (no trailing slash)
- Trained crop and yield models (backend/models_store/*.joblib) are in the repo, so they deploy with it.

Things to know:
- The leaf-image model (disease_model.keras) is git-ignored. For image detection on a host, add tensorflow to the
  requirements and upload or retrain the .keras file (train-disease.ps1). Without it, the image tab reports "unavailable"
  and the rest of the app still works. TensorFlow needs more memory than most free tiers give.
- SQLite (geoyield.db) lives on the host disk. On free hosts the disk is reset on redeploy, so History is lost.
  For real use, move to a hosted database (see ROADMAP.md).
- Live weather runs in the browser (Open-Meteo), so it needs no server key.

## 2. Frontend (React + Vite) - e.g. Vercel or Netlify
- Root directory: frontend
- Build command: npm run build
- Output directory: dist
- Environment variable: VITE_API_URL = the URL of your deployed backend (no trailing slash)

## 3. After deploying
1. Open <backend-url>/api/status - all three models should say "trained" (image model only if you added it).
2. Open the frontend URL and run one example in each module.
3. If the page says it cannot reach the backend, check VITE_API_URL and ALLOWED_ORIGINS.

## 4. Before real farmers use it
Validate on real field data, have agriculture experts review the advice, add user accounts and a hosted database,
and run a small pilot. See ROADMAP.md.