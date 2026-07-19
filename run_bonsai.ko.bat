@echo off
if "%~1" NEQ "_isolated_" (
    start "Bonsai Auto Launcher" cmd /c "%~f0" _isolated_
    exit /b
)
chcp 949 >nul
setlocal

set REPO_URL=https://github.com/PrismML-Eng/Bonsai-demo.git
set REPO_DIR=Bonsai-demo
set CONFIG_FILE=%~dp0config.bat
set INFO_SCRIPT=%~dp0show_connection_info.ps1
set MMPROJ_SCRIPT=%~dp0resolve_mmproj.ps1
set BONSAI_CTX=8192
set BONSAI_MMPROJ=BF16
set BONSAI_LANG=ko

if exist "%CONFIG_FILE%" (
    echo [INFO] 기존 설치와 저장된 설정을 감지했습니다. 바로 서버를 시작합니다...
    call "%CONFIG_FILE%"
    cd "%REPO_DIR%"
    goto :start_server
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERR] git이 설치되어 있지 않습니다. https://git-scm.com 에서 설치 후 다시 실행하세요.
    pause
    exit /b 1
)

if exist "%REPO_DIR%\.git" (
    echo [INFO] 이미 클론된 저장소를 발견했습니다. 최신 상태로 업데이트합니다...
    pushd "%REPO_DIR%"
    git pull
    if errorlevel 1 (
        echo [ERR] git pull 실패.
        popd
        pause
        exit /b 1
    )
    popd
) else (
    echo [INFO] 저장소를 클론합니다...
    git clone "%REPO_URL%" "%REPO_DIR%"
    if errorlevel 1 (
        echo [ERR] git clone 실패.
        pause
        exit /b 1
    )
)

cd "%REPO_DIR%"

echo.
echo [선택] 모델 패밀리를 고르세요:
echo   1. ternary  (2-bit 양자화, 품질 더 좋음, 기본 추천)
echo   2. bonsai   (1-bit, 더 가볍고 빠름, VRAM 적게 씀)
echo   - 27B 사이즈는 두 패밀리 다 이미지 입력을 지원하는 비전-언어 모델입니다
echo   *주의* 두 패밀리 모두 한국어 답변이 실사용에서 특히 불안정했습니다 - 한 문장
echo          안에서 단어 단위로 다른 언어(중국어/일본어/영어 등)가 섞이는 현상이
echo          공통적으로 재현됩니다(패밀리 선택과 무관, 실측 확인). 영어로 질문하면
echo          상대적으로 안정적입니다.
choice /c 12 /n /m "번호 입력 (1 또는 2): "
if errorlevel 2 (set BONSAI_FAMILY=bonsai) else (set BONSAI_FAMILY=ternary)

echo.
echo [선택] 모델 크기를 고르세요 - VRAM은 짧은 대화 기준 최소치이며 컨텍스트가 길어질수록 더 필요합니다
echo   *중요* 이미지 입력과 추론(Thinking) 모드는 27B에서만 가능합니다. 8B/4B/1.7B는 텍스트 전용입니다.
if "%BONSAI_FAMILY%"=="ternary" (
    echo   1. 27B    - *이미지+추론 지원* 최고 품질                 약 VRAM 8GB~
    echo   2. 8B     - 균형잡힌 성능 - 텍스트 전용                  약 VRAM 3.5GB~
    echo   3. 4B     - 가벼운 편, 보급형 GPU에 적합 - 텍스트 전용   약 VRAM 2.5GB~
    echo   4. 1.7B   - 가장 가벼움, 저사양/노트북용 - 텍스트 전용   약 VRAM 1.7GB~
) else (
    echo   1. 27B    - *이미지+추론 지원* 최고 품질                 약 VRAM 5GB~
    echo   2. 8B     - 균형잡힌 성능 - 텍스트 전용                  약 VRAM 2.5GB~
    echo   3. 4B     - 가벼운 편, 보급형 GPU에 적합 - 텍스트 전용   약 VRAM 2GB~
    echo   4. 1.7B   - 가장 가벼움, 저사양/노트북용 - 텍스트 전용   약 VRAM 1.5GB~
)
choice /c 1234 /n /m "번호 입력 (1-4): "
if errorlevel 4 (set BONSAI_MODEL=1.7B) else if errorlevel 3 (set BONSAI_MODEL=4B) else if errorlevel 2 (set BONSAI_MODEL=8B) else (set BONSAI_MODEL=27B)

echo.
echo [INFO] 선택한 설정: BONSAI_FAMILY=%BONSAI_FAMILY%, BONSAI_MODEL=%BONSAI_MODEL%
echo.

echo [INFO] setup.ps1 실행 중... (공개 모델이라 토큰 입력 프롬프트는 자동으로 건너뜁니다)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\setup.ps1" < nul
if errorlevel 1 (
    echo [ERR] setup.ps1 실행 실패.
    pause
    exit /b 1
)

if "%BONSAI_MODEL%"=="27B" (
    echo.
    echo [선택] 이미지 인식 mmproj 정밀도를 고르세요:
    echo   1. BF16   - 더 정확함, 용량 더 큼 - 약 0.87GB, 기본
    echo   2. Q8_0   - 용량 더 작음 - 약 0.59GB, 정확도 약간 낮음
    choice /c 12 /n /m "번호 입력 1 또는 2: "
    if errorlevel 2 (set BONSAI_MMPROJ=Q8_0) else (set BONSAI_MMPROJ=BF16)
)

echo.
choice /c YN /n /m "Tailscale/LAN의 다른 기기에서도 접속 가능하게 열까요? (Y/N): "
if errorlevel 2 (
    set BONSAI_HOST=127.0.0.1
) else (
    set BONSAI_HOST=0.0.0.0
    echo [INFO] 0.0.0.0으로 바인딩합니다. Windows 방화벽에서 8080 포트 허용이 필요할 수 있습니다.
)

(
    echo set BONSAI_FAMILY=%BONSAI_FAMILY%
    echo set BONSAI_MODEL=%BONSAI_MODEL%
    echo set BONSAI_HOST=%BONSAI_HOST%
    echo set BONSAI_CTX=%BONSAI_CTX%
    echo set BONSAI_MMPROJ=%BONSAI_MMPROJ%
) > "%CONFIG_FILE%"
echo [INFO] 설정을 저장했습니다. 다음 실행부터는 바로 서버가 시작됩니다.
echo        설정을 바꾸고 싶으면 "%CONFIG_FILE%" 파일을 삭제하고 다시 실행하세요.
echo        컨텍스트 길이(기본 8192)만 바꾸고 싶으면 "%CONFIG_FILE%"의 BONSAI_CTX 값만 수정하세요.

:start_server
if exist "%MMPROJ_SCRIPT%" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%MMPROJ_SCRIPT%"
)
echo [INFO] 서버를 시작합니다 (포트 8080, repeat-penalty 1.2 적용)...
if exist "%INFO_SCRIPT%" (
    start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%INFO_SCRIPT%"
)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\start_llama_server.ps1" -c %BONSAI_CTX% --repeat-penalty 1.2

pause
















