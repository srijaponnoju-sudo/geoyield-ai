# Retrains the leaf-disease model with MORE images per class and more epochs. Run from the project root:  .\train-disease-full.ps1
# Needs: .\train-disease.ps1 has been run before (so TensorFlow and the PlantVillage images exist).
# Takes roughly 1-3 hours on a normal laptop CPU - leave it running. The old model is backed up first.
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$py = "$root\backend\venv\Scripts\python.exe"
$data = "$root\backend\ml\datasets\PlantVillage-Dataset\raw\color"
if (-not (Test-Path $data)) { Write-Host "PlantVillage images not found. Run .\train-disease.ps1 once first." -ForegroundColor Red; exit 1 }

$store = "$root\backend\models_store"
$bk = "$store\backup_disease"
New-Item -ItemType Directory -Force -Path $bk | Out-Null
foreach ($f in "disease_model.keras", "disease_classes.json", "disease_metrics.json") {
    if (Test-Path "$store\$f") { Copy-Item "$store\$f" $bk -Force }
}
Write-Host "Old model backed up to $bk" -ForegroundColor Green

$env:MAX_PER_CLASS = "800"   # was 150. Use "0" for ALL images (best accuracy, much slower)
$env:EPOCHS = "8"            # was 6 (training stops early if it stops improving)
Write-Host "Training with up to $($env:MAX_PER_CLASS) images per class, up to $($env:EPOCHS) epochs..." -ForegroundColor Green
Set-Location "$root\backend"
& $py ml\disease_detection\train.py $data
Set-Location $root
Write-Host "Done. Old results: backend\models_store\backup_disease\disease_metrics.json   New results: backend\models_store\disease_metrics.json" -ForegroundColor Green
Write-Host "Restart the backend (.\run-backend.ps1)." -ForegroundColor Green