# One-time setup. Run from the project root:  .\setup.ps1
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "== Backend setup ==" -ForegroundColor Green
Set-Location "$root\backend"
if (-not (Test-Path "venv")) { python -m venv venv }
& "$root\backend\venv\Scripts\python.exe" -m pip install --upgrade pip
& "$root\backend\venv\Scripts\python.exe" -m pip install -r requirements.txt
Write-Host "Training crop recommendation model..." -ForegroundColor Green
& "$root\backend\venv\Scripts\python.exe" ml\crop_recommendation\train.py

Write-Host "Training yield prediction model (bundled dataset)..." -ForegroundColor Green
& "$root\backend\venv\Scripts\python.exe" ml\yield_prediction\train.py

Write-Host "== Frontend setup ==" -ForegroundColor Green
Set-Location "$root\frontend"
npm install

Set-Location $root
Write-Host "Setup finished. Now run .\run-backend.ps1 in one terminal and .\run-frontend.ps1 in another." -ForegroundColor Green
