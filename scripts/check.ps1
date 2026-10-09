# Runs the four gates in order and stops at the first failure.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

function Gate($name, [scriptblock]$cmd) {
    Write-Host "== $name" -ForegroundColor Cyan
    & $cmd
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: $name" -ForegroundColor Red; exit 1 }
}

New-Item -ItemType Directory -Force build | Out-Null
Gate "rojo build" { rojo build -o build/game.rbxl }
Gate "tests"      { lune run tests/run }
Gate "selene"     { selene src tests }
Gate "stylua"     { stylua --check src tests }
Write-Host "All gates passed" -ForegroundColor Green
