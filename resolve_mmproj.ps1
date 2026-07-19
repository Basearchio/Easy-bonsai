$ErrorActionPreference = 'SilentlyContinue'

$Family = $env:BONSAI_FAMILY
$Model  = $env:BONSAI_MODEL
$Want   = if ($env:BONSAI_MMPROJ) { $env:BONSAI_MMPROJ } else { 'BF16' }

if ($Model -ne '27B') { exit 0 }

$DemoDir  = Join-Path $PSScriptRoot 'Bonsai-demo'
$ModelDir = if ($Family -eq 'ternary') { Join-Path $DemoDir "models\ternary-gguf\$Model" } else { Join-Path $DemoDir "models\gguf\$Model" }
$AltDir   = Join-Path $ModelDir 'mmproj_alt'

if (-not (Test-Path $ModelDir)) { exit 0 }
New-Item -ItemType Directory -Path $AltDir -Force | Out-Null

# Bring the wanted variant back if a previous choice archived it.
Get-ChildItem -Path $AltDir -Filter "*mmproj*$Want*.gguf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $ModelDir -Force
}

# Archive any other mmproj variant so start_llama_server.ps1's
# `Get-ChildItem *mmproj*.gguf | Select-Object -First 1` only sees the wanted one.
Get-ChildItem -Path $ModelDir -Filter '*mmproj*.gguf' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*$Want*" } |
    ForEach-Object { Move-Item -Path $_.FullName -Destination $AltDir -Force }
