@echo off
if "%~1" NEQ "_isolated_" (
    start "Bonsai Auto Launcher" cmd /c "%~f0" _isolated_
    exit /b
)
setlocal

set REPO_URL=https://github.com/PrismML-Eng/Bonsai-demo.git
set REPO_DIR=Bonsai-demo
set CONFIG_FILE=%~dp0config.bat
set INFO_SCRIPT=%~dp0show_connection_info.ps1
set MMPROJ_SCRIPT=%~dp0resolve_mmproj.ps1
set BONSAI_CTX=8192
set BONSAI_MMPROJ=BF16
set BONSAI_LANG=en

if exist "%CONFIG_FILE%" (
    echo [INFO] Found an existing install and saved settings. Starting the server right away...
    call "%CONFIG_FILE%"
    cd "%REPO_DIR%"
    goto :start_server
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERR] git is not installed. Install it from https://git-scm.com and run this again.
    pause
    exit /b 1
)

if exist "%REPO_DIR%\.git" (
    echo [INFO] Found an already-cloned repo. Updating to the latest...
    pushd "%REPO_DIR%"
    git pull
    if errorlevel 1 (
        echo [ERR] git pull failed.
        popd
        pause
        exit /b 1
    )
    popd
) else (
    echo [INFO] Cloning the repo...
    git clone "%REPO_URL%" "%REPO_DIR%"
    if errorlevel 1 (
        echo [ERR] git clone failed.
        pause
        exit /b 1
    )
)

cd "%REPO_DIR%"

echo.
echo [CHOOSE] Pick a model family:
echo   1. ternary  (2-bit quantization, better quality, default recommendation)
echo   2. bonsai   (1-bit, lighter and faster, less VRAM)
echo   - Both families are vision-language models at the 27B size
echo   *NOTE* Both families were found to be especially unstable in Korean in real
echo          use - word-level mixing of other languages (Chinese/Japanese/English
echo          etc.) within a single sentence reproduces regardless of family
echo          (measured). English is comparatively stable.
choice /c 12 /n /m "Enter a number (1 or 2): "
if errorlevel 2 (set BONSAI_FAMILY=bonsai) else (set BONSAI_FAMILY=ternary)

echo.
echo [CHOOSE] Pick a model size - VRAM figures are minimums for a short conversation and rise with longer context
echo   *IMPORTANT* Image input and reasoning (Thinking) mode are only available on 27B. 8B/4B/1.7B are text-only.
if "%BONSAI_FAMILY%"=="ternary" (
    echo   1. 27B    - *Image+reasoning support* Best quality              ~VRAM 8GB+
    echo   2. 8B     - Balanced performance - text only                   ~VRAM 3.5GB+
    echo   3. 4B     - Lighter, fits budget GPUs - text only              ~VRAM 2.5GB+
    echo   4. 1.7B   - Lightest, for low-spec/laptops - text only         ~VRAM 1.7GB+
) else (
    echo   1. 27B    - *Image+reasoning support* Best quality              ~VRAM 5GB+
    echo   2. 8B     - Balanced performance - text only                   ~VRAM 2.5GB+
    echo   3. 4B     - Lighter, fits budget GPUs - text only              ~VRAM 2GB+
    echo   4. 1.7B   - Lightest, for low-spec/laptops - text only         ~VRAM 1.5GB+
)
choice /c 1234 /n /m "Enter a number (1-4): "
if errorlevel 4 (set BONSAI_MODEL=1.7B) else if errorlevel 3 (set BONSAI_MODEL=4B) else if errorlevel 2 (set BONSAI_MODEL=8B) else (set BONSAI_MODEL=27B)

echo.
echo [INFO] Selected: BONSAI_FAMILY=%BONSAI_FAMILY%, BONSAI_MODEL=%BONSAI_MODEL%
echo.

echo [INFO] Running setup.ps1... (public model, so the token prompt is auto-skipped)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\setup.ps1" < nul
if errorlevel 1 (
    echo [ERR] setup.ps1 failed.
    pause
    exit /b 1
)

if "%BONSAI_MODEL%"=="27B" (
    echo.
    echo [CHOOSE] Pick the mmproj image-recognition precision:
    echo   1. BF16   - More accurate, larger - about 0.87GB, default
    echo   2. Q8_0   - Smaller - about 0.59GB, slightly less accurate
    choice /c 12 /n /m "Enter a number 1 or 2: "
    if errorlevel 2 (set BONSAI_MMPROJ=Q8_0) else (set BONSAI_MMPROJ=BF16)
)

echo.
echo [CHOOSE] Context length (how many tokens the model keeps in memory):
echo   1. Fixed 8192       - Predictable, lower VRAM (default)
echo   2. Auto (official)  - Upstream RAM-tiered default; larger context, more VRAM
echo   Either is fine - you can change it anytime later via BONSAI_CTX in config.bat.
choice /c 12 /n /m "Enter a number (1 or 2): "
if errorlevel 2 (set BONSAI_CTX=) else (set BONSAI_CTX=8192)

echo.
choice /c YN /n /m "Allow access from other devices on Tailscale/LAN? (Y/N): "
if errorlevel 2 (
    set BONSAI_HOST=127.0.0.1
) else (
    set BONSAI_HOST=0.0.0.0
    echo [INFO] Binding to 0.0.0.0. You may need to allow port 8080 in Windows Firewall.
)

(
    echo set BONSAI_FAMILY=%BONSAI_FAMILY%
    echo set BONSAI_MODEL=%BONSAI_MODEL%
    echo set BONSAI_HOST=%BONSAI_HOST%
    echo set BONSAI_CTX=%BONSAI_CTX%
    echo set BONSAI_MMPROJ=%BONSAI_MMPROJ%
) > "%CONFIG_FILE%"
echo [INFO] Settings saved. The server will start immediately from now on.
echo        To change settings, delete "%CONFIG_FILE%" and run this again.
echo        Context length: BONSAI_CTX in "%CONFIG_FILE%" (8192 = fixed; empty = official RAM-tier auto).

:start_server
rem BONSAI_CTX is inherited by the child process; upstream start_llama_server.ps1
rem reads it natively (a value = fixed context; empty = its RAM-tiered default,
rem the "Auto (official)" choice). No -c passthrough needed.
if exist "%MMPROJ_SCRIPT%" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%MMPROJ_SCRIPT%"
)
echo [INFO] Starting the server (port 8080)...
if exist "%INFO_SCRIPT%" (
    start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%INFO_SCRIPT%"
)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start_llama_server.ps1"

pause
