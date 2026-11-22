# Trains the leaf-disease image model. Run from the project root:  .\train-disease.ps1
# Needs: internet, Git installed (https://git-scm.com), about 1-2 GB free disk, ~10-30 minutes on a normal laptop CPU.
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$py = "$root\backend\venv\Scripts\python.exe"
$data = "$root\backend\ml\datasets\PlantVillage-Dataset"

Write-Host "1/3 Installing TensorFlow (first time only, large download)..." -ForegroundColor Green
& $py -m pip install tensorflow scikit-learn

if (-not (Test-Path "$data\raw\color")) {
    Write-Host "2/3 Downloading PlantVillage colour images (only the raw/color folder)..." -ForegroundColor Green
    if (Test-Path $data) { Remove-Item -Recurse -Force $data }
    git clone --depth 1 --filter=blob:none --sparse https://github.com/spMohanty/PlantVillage-Dataset.git $data
    Set-Location $data
    git sparse-checkout set raw/color
    Set-Location $root
} else {
    Write-Host "2/3 PlantVillage already downloaded." -ForegroundColor Green
}

Write-Host "3/3 Training (150 images per class, up to 6 epochs). Please wait..." -ForegroundColor Green
Set-Location "$root\backend"
& $py ml\disease_detection\train.py "$data\raw\color"
Write-Host "Done. Restart the backend (.\run-backend.ps1). Dashboard should show 'disease detection: trained'." -ForegroundColor Green
