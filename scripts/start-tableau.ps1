param(
  [string]$ProjectId = 'groupe3inssettp',
  [string]$Table = 'groupe3inssettp.movenow.positions',
  [string]$Location = 'europe-west9',
  [string]$Subscription = 'g3-movenow-positions-bq',
  [string]$DeadLetterSubscription = '',
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js est requis.' }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm est requis.' }
if ($Table -notmatch '^[^.]+\.[^.]+\.[^.]+$') { throw 'Table doit avoir la forme PROJET.DATASET.TABLE.' }

$env:SOURCE = 'bigquery'
$env:GOOGLE_CLOUD_PROJECT = $ProjectId
$env:BQ_TABLE = $Table
$env:BQ_LOCATION = $Location
$env:PORT = "$Port"
$env:SUBSCRIPTION = $Subscription
$env:DEAD_LETTER_SUBSCRIPTION = $DeadLetterSubscription

$tableauDir = Join-Path $PSScriptRoot '..\movenow\tableau'
Push-Location $tableauDir
try {
  if (-not (Test-Path 'node_modules')) {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm ci a échoué.' }
  }
  Write-Host "Tableau MoveNow : http://localhost:$Port (Ctrl+C pour arrêter)"
  node server.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Le tableau MoveNow a quitté avec une erreur.' }
}
finally {
  Pop-Location
}
