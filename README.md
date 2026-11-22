# GeoYield AI — Smart Farming. Better Yield.
**Team Vibe_coders** · AAROHAN 2.0 – Innovative Challenge · Gokaraju Rangaraju Institute of Engineering and Technology
Team Leader: K Shiva Mallesh · Members: Ponnoju Srija, M Pranav, R Rishitha Rao
Problem statement: *AI-Based Crop Yield Prediction and Optimization* (Agriculture, Smart Cities & Disaster Management)

## Problem and solution
Farmers often choose crops, diagnose crop problems and pick fertilizers from experience rather than analysis of soil, weather and crop conditions.
GeoYield AI is an AI-powered decision-support system with four independent modules:
1. **Crop Recommendation** – Scikit-learn RandomForest on soil N, P, K, pH, temperature, humidity, rainfall.
2. **Yield Prediction** – Scikit-learn regression, available once trained (PPT: "when a trained model is available").
3. **Crop Health Detection** – (a) leaf image classification with TensorFlow/Keras, (b) symptom-based screening (rule-based fallback).
4. **Fertilizer Evaluation** – checks whether the farmer's fertilizer suits the crop and soil; suggests an alternative; never gives dosages.

## Stack (as in the PPT)
React.js · Python FastAPI · Scikit-learn · TensorFlow/Keras · SQLite · VS Code, Git, GitHub

## New in this version
- **State -> District dropdowns** (all states/UTs; district lists for Telangana and Andhra Pradesh, free text for other states).
- **Reset** and **Use example** buttons on every form.
- **English / Hindi / Telugu** for the whole screen and for the backend explanations (language switch in the top bar).
- **Voice assistant** (microphone button): open pages, fill soil/weather values, submit, reset, switch language, and read results aloud.
  It only follows known commands and reads results the models already computed - it does not invent answers.
  Works in Chrome / Edge (needs internet for speech recognition). Reading aloud needs a voice installed for that language
  (Windows: Settings > Time & language > Speech).
- **Accuracy warnings** on crop recommendation: low model confidence, and inputs outside the range the model was trained on.
- Roadmap for turning this into a real product: see ROADMAP.md.

## Quick start (Windows, PowerShell, VS Code terminal)
Open the project root (the folder containing `backend` and `frontend`) in VS Code, then:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1            # one time: venv, packages, crop model training, npm install
.\run-backend.ps1      # terminal 1  -> http://localhost:8000/docs
.\run-frontend.ps1     # terminal 2  -> http://localhost:5173
```
Requirements: Python 3.10+, Node.js 18+ (LTS).

## Honest model status (also live at /api/status and on the Dashboard)
| Module | Status | How to enable |
|---|---|---|
| Crop recommendation | **Trained** (public dataset, 2,200 rows, 22 crops; ~99% hold-out accuracy - dataset is very clean, real-field accuracy will be lower) | `python ml\crop_recommendation\train.py` |
| Yield prediction | **Trained** by setup.ps1 on the bundled 'Crop Production in India' dataset (government open data, ~246k rows). Tested on the latest years: R² 0.92 | `python ml\yield_prediction\train.py` |
| Image disease detection | **Trained on demand** (needs TensorFlow + PlantVillage download, about 10-30 min) | run `.	rain-disease.ps1` from the project root |
| Symptom analysis | Rule-based fallback (possible causes, not diagnoses) | - |
| Fertilizer evaluation | Rule-based: standard fertilizer grades + crop N/P/K ranges derived from the dataset | - |

Restart the backend after training. Metrics shown in the UI are read from files written by the training scripts, never hard-coded.

## Folder structure
```
backend/app            main.py, config.py, routes/, schemas/, services/, database/, data/
backend/ml             crop_recommendation/, yield_prediction/, disease_detection/, datasets/
backend/models_store   trained models + metrics (generated)
frontend/src           components/, pages/, services/api.js, styles/
```

## API (Swagger at /docs)
GET /api/status · POST /api/crop/recommend · POST /api/yield/predict · POST /api/health/image · POST /api/health/symptoms · GET /api/fertilizers · POST /api/fertilizer/evaluate · GET /api/history

## Database
SQLite file `backend/geoyield.db` with tables farmer_inputs, crop_recommendations, yield_predictions, health_analyses, fertilizer_evaluations.

## Configuration
Optional: copy `.env.example` to `backend\.env`. The app works without it.

## Known limitations
- Crop model does not use location, soil type or season (not in the dataset); they are stored only.
- Fertilizer logic uses dataset-derived crop ranges and standard grades; verify against PJTSAU / ICAR / Soil Health Card recommendations. No dosage is produced.
- Image model recognises only its trained PlantVillage classes; low-confidence results are flagged.
- Optional weather API is not implemented; weather is entered manually.

## Put it on GitHub (PowerShell, run in the project root)
    git init
    git branch -M main
    git add .
    git commit -m "GeoYield AI - AAROHAN 2.0 (Team Vibe_coders)"
    git remote add origin https://github.com/srijaponnoju-sudo/geoyield-ai.git
    git push -u origin main
Create the empty repository `geoyield-ai` on github.com first (no README, no .gitignore). The trained image model (.keras) and the
PlantVillage download are git-ignored: anyone who clones the repo runs `.\setup.ps1` (and `.\train-disease.ps1`) to rebuild them.
