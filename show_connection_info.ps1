$ErrorActionPreference = 'SilentlyContinue'

$Lang = if ($env:BONSAI_LANG -eq 'ko') { 'ko' } else { 'en' }

if ($Lang -eq 'ko') {
    # Started via `start /B`, sharing the parent console (chcp 949, per SRS 4.2
    # problem 1/5/6) - but on systems where consoles are delegated to Windows
    # Terminal (ConPTY) instead of a plain conhost window (Windows 11 default
    # since ~24H2, and not something this script controls on the user's PC),
    # chcp's codepage change can lag behind this background process attaching
    # to the console, so a single attempt intermittently misses it and output
    # comes out garbled. Re-assert the Win32 codepage directly (what chcp
    # itself calls) and verify it actually stuck before proceeding, instead of
    # trusting one attempt.
    Add-Type -Name Kernel32 -Namespace Bonsai -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool SetConsoleOutputCP(uint wCodePageID);
[DllImport("kernel32.dll")] public static extern uint GetConsoleOutputCP();
'@ -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt 10; $i++) {
        try {
            [Bonsai.Kernel32]::SetConsoleOutputCP(949) | Out-Null
            if ([Bonsai.Kernel32]::GetConsoleOutputCP() -eq 949) { break }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
    try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(949) } catch {}
}

$Family   = $env:BONSAI_FAMILY
$Model    = $env:BONSAI_MODEL
$HostAddr = if ($env:BONSAI_HOST) { $env:BONSAI_HOST } else { '127.0.0.1' }
$Port     = 8080

# Wait for the server to actually be ready so this prints after the load logs,
# not before them. Runs in the background alongside start_llama_server.ps1.
$MaxWaitSeconds = 300
for ($waited = 0; $waited -lt $MaxWaitSeconds; $waited++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { break }
    } catch {}
    Start-Sleep -Seconds 1
}

$DemoDir = Join-Path $PSScriptRoot 'Bonsai-demo'
if ($Family -eq 'ternary') {
    $ModelDir     = Join-Path $DemoDir "models\ternary-gguf\$Model"
    $QuantPattern = '*-Q2_0.gguf'
} else {
    $ModelDir     = Join-Path $DemoDir "models\gguf\$Model"
    $QuantPattern = '*-Q1_0.gguf'
}

$ModelFile = Get-ChildItem -Path $ModelDir -Filter $QuantPattern -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*mmproj*' -and $_.Name -notlike '*dspark*' -and $_.Name -notlike '*kv-bias*' } |
    Select-Object -First 1
$ModelId = if ($ModelFile) {
    $ModelFile.Name
} elseif ($Lang -eq 'ko') {
    '(모델 파일을 찾지 못함 - setup.ps1을 먼저 실행하세요)'
} else {
    '(model file not found - run setup.ps1 first)'
}

$HasVision = $false
if ($Model -eq '27B') {
    $Mmproj = Get-ChildItem -Path $ModelDir -Filter '*mmproj*.gguf' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Mmproj) { $HasVision = $true }
}

$LanUrl = $null
if ($HostAddr -eq '0.0.0.0') {
    $ip = $null
    $tsExe = (Get-Command tailscale -ErrorAction SilentlyContinue).Source
    if (-not $tsExe) {
        $tsCandidate = "$env:ProgramFiles\Tailscale\tailscale.exe"
        if (Test-Path $tsCandidate) { $tsExe = $tsCandidate }
    }
    if ($tsExe) {
        try { $ip = (& $tsExe ip -4 2>$null | Select-Object -First 1) } catch {}
    }
    if (-not $ip) {
        $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' -and $_.InterfaceAlias -notmatch 'Loopback' } |
            Select-Object -First 1 -ExpandProperty IPAddress
    }
    if ($ip) { $LanUrl = "http://${ip}:$Port" }
}

# Context length actually loaded by the server, read straight from its /props
# endpoint - no need to recompute upstream's RAM tier, and it stays correct even
# if upstream changes how the default is chosen. Falls back to BONSAI_CTX only if
# the query fails. $CtxAuto marks that no value was pinned (Auto = upstream chose).
$CtxValue = $null
try {
    $props = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/props" -TimeoutSec 5 -ErrorAction Stop
    $CtxValue = $props.default_generation_settings.n_ctx
} catch {}
if (-not $CtxValue) { $CtxValue = $env:BONSAI_CTX }
$CtxAuto = -not $env:BONSAI_CTX

# First Auto run: BONSAI_CTX is empty in config.bat. Pin the server's actual
# context back into it (not a value we computed - the one the server loaded), so
# the next launch shows a concrete number to hand-edit instead of a blank field.
# Only touches an empty BONSAI_CTX line; a fixed or already-pinned value is left
# alone, and the user can re-empty it to go back to the official auto default.
if ($CtxAuto -and $CtxValue) {
    $ConfigFile = Join-Path $PSScriptRoot 'config.bat'
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content -Raw -Path $ConfigFile
            if ($cfg -match '(?m)^\s*set BONSAI_CTX=\s*$') {
                $cfg = $cfg -replace '(?m)^\s*set BONSAI_CTX=\s*$', "set BONSAI_CTX=$CtxValue"
                Set-Content -Path $ConfigFile -Value $cfg -NoNewline -Encoding ascii
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
if ($Lang -eq 'ko') {
    Write-Host "  연결 정보 (서버 준비 완료)" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  모델 ID       : $ModelId"
    if ($HasVision) {
        Write-Host "  기능          : 이미지 입력 지원(비전)"
    }
    Write-Host "  API (로컬)    : http://127.0.0.1:$Port/v1"
    if ($LanUrl) {
        Write-Host "  API (LAN/원격): $LanUrl/v1"
        Write-Host "  브라우저 채팅 : $LanUrl"
    } else {
        Write-Host "  브라우저 채팅 : http://127.0.0.1:$Port"
    }
    Write-Host "  API Key       : 필요 없음 (인증 없음)"
    Write-Host "  컨텍스트 길이 : $CtxValue 토큰$(if ($CtxAuto) { ' (자동, 공식 기본값)' }) (config.bat의 BONSAI_CTX로 변경 가능)"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  * 위 브라우저 채팅 주소를 Ctrl + 마우스 왼쪽 클릭하면 바로 열립니다." -ForegroundColor Yellow
    Write-Host "  * 이 창을 열어둬야 서버가 계속 유지됩니다. 창을 닫으면 서버도 종료됩니다." -ForegroundColor Yellow
    Write-Host "  * 다 쓰셨으면 이 창에서 Ctrl+C 를 눌러 서버를 종료하세요." -ForegroundColor Yellow
} else {
    Write-Host "  Connection Info (server ready)" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  Model ID      : $ModelId"
    if ($HasVision) {
        Write-Host "  Feature       : Image input supported (vision)"
    }
    Write-Host "  API (local)   : http://127.0.0.1:$Port/v1"
    if ($LanUrl) {
        Write-Host "  API (LAN/remote): $LanUrl/v1"
        Write-Host "  Browser chat  : $LanUrl"
    } else {
        Write-Host "  Browser chat  : http://127.0.0.1:$Port"
    }
    Write-Host "  API Key       : Not required (no auth)"
    Write-Host "  Context length: $CtxValue tokens$(if ($CtxAuto) { ' (auto, official default)' }) (change via BONSAI_CTX in config.bat)"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  * Ctrl + left-click the Browser chat link above to open it directly." -ForegroundColor Yellow
    Write-Host "  * Keep this window open to keep the server running. Closing it stops the server." -ForegroundColor Yellow
    Write-Host "  * When you're done, press Ctrl+C in this window to stop the server." -ForegroundColor Yellow
}
Write-Host ""
