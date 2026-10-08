param(
  [string]$ProjectId = 'groupe3inssettp',
  [string]$Topic = 'g3-movenow-positions',
  [string]$Table = 'groupe3inssettp.movenow.positions',
  [string]$Location = 'europe-west9',
  [ValidateRange(1, 100)][int]$Rate = 2,
  [ValidateRange(1, 600)][int]$Duration = 5,
  [ValidateRange(0, 1000)][int]$Invalid = 0,
  [ValidateRange(10, 600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

foreach ($command in @('node', 'npm', 'bq')) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    throw "Commande introuvable : $command"
  }
}
if ($env:PUBSUB_EMULATOR_HOST) {
  throw 'PUBSUB_EMULATOR_HOST est défini : le producteur viserait un émulateur local, pas GCP.'
}
if ($Invalid -gt ($Rate * $Duration)) {
  throw 'Invalid ne peut pas dépasser le nombre de messages du lot.'
}
if ($Table -notmatch '^[^.]+\.[^.]+\.[^.]+$') {
  throw 'Table doit avoir la forme PROJET.DATASET.TABLE.'
}

$producerDir = Join-Path $PSScriptRoot '..\movenow\producteur'
$batch = 'demo-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
$outputDir = Join-Path $producerDir 'lots'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Push-Location $producerDir
try {
  if (-not (Test-Path 'node_modules')) {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'npm ci a échoué.' }
  }

  node producteur.mjs --project $ProjectId --topic $Topic --rate $Rate --duration $Duration --invalid $Invalid --batch $batch --out $outputDir
  if ($LASTEXITCODE -ne 0) { throw 'La publication Pub/Sub a échoué. Vérifiez ADC et roles/pubsub.publisher.' }
}
finally {
  Pop-Location
}

$expected = $Rate * $Duration - $Invalid
$escapedBatch = $batch.Replace("'", "''")
$query = @"
SELECT COUNT(DISTINCT event_id) AS received, COUNT(*) AS row_count
FROM ``$Table``
WHERE event_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND STARTS_WITH(event_id, '$escapedBatch-')
"@
$query = ($query -split '\r?\n' | ForEach-Object { $_.Trim() }) -join ' '

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
do {
  $result = bq --quiet --project_id=$ProjectId --location=$Location --format=json query --nouse_legacy_sql $query
  if ($LASTEXITCODE -ne 0) { throw 'La requête BigQuery a échoué. Vérifiez la table et les droits de lecture.' }
  $row = @($result | ConvertFrom-Json)[0]
  $received = [int]$row.received
  Write-Host "$received / $expected événements valides reçus dans $Table"
  if ($received -ge $expected) {
    Write-Host "Lot $batch terminé. Lignes : $($row.row_count). Liste des événements : $(Join-Path $outputDir "$batch.jsonl")"
    if ($Invalid -gt 0) {
      Write-Host "$Invalid message(s) invalide(s) publié(s). Leur transfert en dead-letter n'est pas vérifié ici : il intervient après les tentatives de livraison et peut apparaître plus tard dans Monitoring."
    }
    exit 0
  }
  Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)

throw "Délai dépassé pour le lot $batch. Vérifiez la subscription BigQuery et le backlog Pub/Sub."
