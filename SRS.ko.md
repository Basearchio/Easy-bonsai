🇺🇸 [English](./SRS.md) | 🇰🇷 한국어

# Bonsai 로컬 실행 자동화 배치파일 소프트웨어 요구사항 명세서 (SRS)

> **문서 정보**
> - **버전:** v1.0
> - **작성일:** 2026-07-19
> - **작성자:** Basearchio
> - **문서 상태:** 초안

---

## 1. 개요 (Introduction)

### 1.1 목적 (Purpose)
본 문서는 **PrismML-Eng/Bonsai-demo**(로컬 LLM "Bonsai" 실행 데모)를 Windows에서 손쉽게 설치·실행하기 위한 자동화 배치파일(`run_bonsai.bat`) 개발을 위한 소프트웨어 요구사항 명세서(SRS)이다.

사용자는 매번 `git clone` → `cd` → `PowerShell -ExecutionPolicy Bypass -File .\setup.ps1` 같은 명령을 손으로 치는 것이 번거롭다고 판단하여, 더블클릭 한 번으로 클론부터 모델 선택, 환경 설치, 채팅 서버 구동까지 끝나는 배치파일을 만들기로 했다. 본 문서는 그 배치파일이 왜 필요했는지, 무엇을 해야 하는지, 그리고 개발 과정에서 실제로 발생했던 문제와 해결 방식을 기록하는 것을 목적으로 한다.

### 1.2 범위 (Scope)
본 프로젝트는 단일 Windows 배치파일 **`run_bonsai.bat`**의 개발을 다룬다. 이 배치파일은 `PrismML-Eng/Bonsai-demo` GitHub 저장소를 감싸는 래퍼(wrapper)로, 저장소 자체의 로직(`setup.ps1`, `scripts/start_llama_server.ps1` 등)은 수정하지 않고 그대로 호출한다.

- **포함 범위:** 저장소 클론/업데이트, 모델 패밀리·크기 선택 UI, 환경 자동 설치 실행, HuggingFace 인증 프롬프트 무인화, 네트워크 노출 범위(로컬/LAN) 선택, 채팅 API 서버 기동.
- **제외 범위:** `Bonsai-demo` 저장소 내부 스크립트(`setup.ps1`, `start_llama_server.ps1` 등)의 로직 변경, macOS/Linux 지원, GUI(Open WebUI) 자동 설치.

### 1.3 용어 정의 (Definitions and Acronyms)
- **Bonsai / Ternary-Bonsai:** PrismML-Eng이 배포하는 로컬 LLM 패밀리. Bonsai는 1-bit, Ternary-Bonsai는 2-bit 양자화 버전.
- **mmproj:** llama.cpp의 멀티모달 프로젝터(vision projector) 파일. 27B(비전-언어) 모델에서 이미지 입력을 처리하는 데 필요.
- **GGUF:** llama.cpp가 사용하는 모델 가중치 파일 포맷.
- **CP949(EUC-KR):** 한글 Windows의 기본 ANSI 코드페이지. 본 프로젝트의 인코딩 이슈의 핵심 원인.
- **BONSAI_FAMILY / BONSAI_MODEL / BONSAI_HOST:** `Bonsai-demo` 저장소가 읽는 환경변수. 각각 모델 계열, 모델 크기, 서버 바인딩 주소를 지정.
- **dspark:** 27B 전용 스펙큘레이티브 디코딩용 드래프터 모델.

### 1.4 참고 문헌 (References)
- https://github.com/PrismML-Eng/Bonsai-demo (원본 저장소, README.md)
- https://huggingface.co/prism-ml (모델 가중치 배포처, HuggingFace API로 실제 파일 크기 확인)

---

## 2. 전체 설명 (Overall Description)

### 2.1 제품 관점 (Product Perspective)
독립 실행형 유틸리티다. `Bonsai-demo` 저장소를 대체하지 않고, 그 위에 얹혀서 반복 작업(클론, 옵션 선택, 스크립트 실행 순서)을 자동화하는 얇은 오케스트레이션 레이어다.

```
run_bonsai.bat
  ├─ git clone / pull  →  Bonsai-demo/
  ├─ 사용자 선택(콘솔 메뉴): 패밀리, 크기, LAN 노출 여부
  ├─ powershell setup.ps1        (Bonsai-demo 저장소 소유 스크립트, 무수정)
  └─ powershell start_llama_server.ps1  (Bonsai-demo 저장소 소유 스크립트, 무수정)
```

### 2.2 제품 기능 요약 (Product Functions)
1. **저장소 자동 클론/업데이트:** git 설치 여부 확인, 최초 실행 시 clone, 재실행 시 pull.
2. **모델 선택 UI:** 콘솔에서 번호 입력으로 패밀리(ternary/bonsai)와 크기(27B/8B/4B/1.7B) 선택, 각 조합의 예상 VRAM과 기능 차이를 안내.
3. **환경 자동 설치:** `setup.ps1` 무인 실행(Python/uv/venv 구성, GPU 감지, 모델 다운로드). HuggingFace 토큰 프롬프트는 표준입력 리다이렉트로 자동 스킵.
4. **네트워크 노출 범위 선택:** 로컬 전용(127.0.0.1) 또는 Tailscale/LAN 노출(0.0.0.0) 중 선택.
5. **채팅 서버 자동 기동:** `start_llama_server.ps1`을 호출해 포트 8080에서 API 서버 구동.
6. **연결 정보 자동 표시:** 서버 기동 직전에 `show_connection_info.ps1`을 호출해 실제 다운로드된 모델 파일명, 로컬/LAN(Tailscale 자동 감지) API 주소, 브라우저 채팅 주소를 표로 출력.
7. **컨텍스트 길이 제어:** 메뉴에서 **고정 8192**(기본)와 **자동(공식 RAM 기반)** 중 선택하며, 선택값은 `config.bat`의 `BONSAI_CTX`로 저장됨(값 = 고정 상한, 비움 = 업스트림 RAM 기반 기본값). 고정 8192는 KV 캐시를 제한해 16GB급 GPU에서 VRAM 낭비를 방지.
8. **mmproj 정밀도 선택:** 27B 선택 시 BF16/Q8_0 중 고르는 메뉴 제공, 선택되지 않은 쪽은 삭제 없이 보관해뒀다가 재전환 시 재사용.
9. **다국어 런처:** `run_bonsai.bat`(영어, 기본)과 `run_bonsai.ko.bat`(한국어) 두 벌 제공, 동작은 동일. `config.bat`(모델 설정)은 공유하되 언어는 매 실행 시 각 `.bat`이 결정.

### 2.3 사용자 특징 (User Classes and Characteristics)
- **단일 로컬 사용자(1인 개발/실험 목적):** git·PowerShell 명령을 직접 치는 것을 번거로워하며, "더블클릭 한 번"으로 끝나는 경험을 원함. HuggingFace 비공개 저장소 인증 같은 고급 시나리오는 대상 사용자 범위 밖으로 간주(해당 요구가 있는 사용자는 스크립트 대신 `setup.ps1`을 직접 사용할 것으로 가정).

### 2.4 제약 사항 (Constraints)
- **플랫폼 제약:** Windows(cmd.exe) 전용. `.bat` 특성상 OS 자동 분기는 불필요(어차피 Windows에서만 실행됨).
- **인코딩 제약:** 배치파일에 한글 문자열을 포함해야 하는데, cmd.exe의 배치파일 파싱은 **시스템 기본 코드페이지(한글 Windows = CP949)** 기준으로 동작한다. UTF-8로 저장하면 구조 자체가 깨질 수 있음(상세 원인은 4장 참조). 따라서 **본 파일은 UTF-8이 아닌 CP949로 인코딩되어야 한다.**
- **의존 스크립트 제약:** `setup.ps1` / `start_llama_server.ps1`의 옵션 체계(예: mmproj 선택 불가)를 그대로 상속한다. 저장소 쪽 스크립트를 포크/수정하지 않는 한 우회 불가능한 한계가 존재.
- **실행 정책 제약:** PowerShell 스크립트 실행을 위해 `-ExecutionPolicy Bypass`가 필요.

### 2.5 가정 및 의존성 (Assumptions and Dependencies)
- 사용자 PC에 git과 PowerShell(5.1 이상)이 설치되어 있다고 가정(git 미설치는 감지 후 안내, PowerShell은 Windows 기본 내장이므로 별도 체크 없음).
- HuggingFace의 `prism-ml/*` 모델 저장소가 **public**으로 유지된다고 가정. (README상 27B는 "출시 시 비공개 해제 예정"이라는 문구가 있었으나 현재는 토큰 없이 다운로드 가능함을 확인함. 만약 추후 다시 비공개로 전환되면 무인 다운로드가 실패할 수 있음 — 알려진 리스크.)
- winget이 설치되어 있다고 가정(Python/uv 자동 설치 경로). 없으면 `setup.ps1`이 경고만 띄우고 수동 설치를 요구.

---

## 3. 상세 요구사항 (Specific Requirements)

### 3.1 기능적 요구사항 (Functional Requirements)

| 요구사항 ID | 분류 | 요구사항 명칭 | 상세 설명 | 우선순위 |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-001** | 저장소 관리 | 자동 클론/업데이트 | git 미설치 시 안내 후 종료. `Bonsai-demo\.git` 존재 여부로 최초 실행(clone) / 재실행(pull)을 분기한다. | **High** |
| **REQ-002** | 모델 선택 | 패밀리 선택 메뉴 | 콘솔에서 1(ternary, 기본 추천)/2(bonsai) 선택. 27B는 두 패밀리 모두 비전-언어 모델임을 안내. | **High** |
| **REQ-003** | 모델 선택 | 크기 선택 메뉴 | 27B/8B/4B/1.7B 중 선택. 선택된 패밀리에 따라 다른 VRAM 수치를 표시하고, 이미지 입력·추론(Thinking) 모드가 **27B 전용**임을 `*중요*` 표시로 강조. | **High** |
| **REQ-004** | 환경 설치 | 무인 환경 구축 | `setup.ps1`을 표준입력 리다이렉트(`< nul`)로 실행하여 HuggingFace 토큰 입력 프롬프트를 자동 스킵. Python/uv/venv 설치, GPU 감지, 모델(GGUF) 다운로드는 `setup.ps1`에 위임. | **High** |
| **REQ-005** | 네트워크 | 노출 범위 선택 | Y 선택 시 `BONSAI_HOST=0.0.0.0`(Tailscale/LAN 접근 허용, 방화벽 허용 필요 안내), N(기본) 선택 시 `BONSAI_HOST=127.0.0.1`(로컬 전용). | **Medium** |
| **REQ-006** | 서버 구동 | 채팅 API 서버 자동 기동 | `scripts\start_llama_server.ps1`을 호출해 포트 8080에서 서버 기동(포그라운드, 창을 닫으면 서버 종료). | **High** |
| **REQ-007** | 오류 처리 | 단계별 실패 중단 | git/setup 단계에서 `errorlevel` 체크 후 실패 시 원인 출력 + `pause` + 종료(다음 단계로 넘어가지 않음). | **High** |
| **REQ-008** | 사용자 안내 | 연결 정보 자동 표시 | `show_connection_info.ps1`을 `start "" /B`로 백그라운드 실행해 `start_llama_server.ps1`(포그라운드)과 동시에 돌리고, `/health`가 200을 반환할 때까지 폴링(최대 300초)한 뒤에 표를 출력 — 로딩 로그 *뒤에* 표가 뜨도록 함. 모델 파일명·비전 지원 여부는 `models\` 폴더 스캔, IP는 Tailscale(우선)/LAN IPv4(대체)를 매 실행 시 동적 감지. 표 아래에 "창을 닫으면 서버 종료", "Ctrl+C로 종료" 안내 포함. | **Medium** |
| **REQ-009** | 리소스 관리 | 컨텍스트 길이 제한 | 메뉴에서 **고정 8192**(기본)와 **자동(공식 RAM 기반)** 중 선택해 `config.bat`의 `BONSAI_CTX`로 저장. 고정값이 설정된 경우에만 `-c %BONSAI_CTX%`를 넘기고(비우면 `BONSAI_CTX`를 직접 읽는 업스트림 RAM 기반 기본값이 적용됨), 고정 8192는 저장소 스크립트가 할당하는 큰 KV 캐시를 줄임(문제 7 참조). | **Medium** |
| **REQ-010** | 모델 선택 | mmproj 정밀도 선택 | 27B 선택 시 BF16/Q8_0 메뉴 표시. `resolve_mmproj.ps1`이 `:start_server`에서 선택된 쪽만 모델 폴더에 남기고 나머지는 `mmproj_alt\`로 이동(삭제 아님, 재다운로드 없이 전환 가능). `config.bat`의 `BONSAI_MMPROJ`로 언제든 재선택(문제 9 참조). | **Low** |
| **REQ-011** | 다국어 지원 | 영어/한국어 런처 이원화 | `run_bonsai.bat`(영어, ASCII, 기본)과 `run_bonsai.ko.bat`(한국어, CP949)을 별도 파일로 제공. 공용 스크립트(`show_connection_info.ps1`)는 `BONSAI_LANG` 환경변수(각 `.bat`이 자신의 언어로 설정, `config.bat`엔 미저장)로 출력 문구만 분기. `config.bat`의 모델 설정은 두 런처가 공유(문제 11 참조). | **Low** |

### 3.2 외부 인터페이스 요구사항 (External Interface Requirements)

#### 3.2.1 사용자 인터페이스 (User Interface)
- 콘솔 기반 UI. `choice` 명령으로 번호 입력을 받는 메뉴 3종(패밀리 선택, 크기 선택, LAN 노출 여부).
- 모든 안내 문구는 한글. VRAM·기능 안내는 선택 직전에 표로 제시.

#### 3.2.2 하드웨어 인터페이스 (Hardware Interfaces)
- GPU VRAM 요구량(짧은 대화 기준 최소치, HuggingFace 실제 GGUF 파일 크기 + README 실측 오버헤드 기반 추정):

| 모델 크기 | Ternary(2-bit) | Bonsai(1-bit) |
| :--- | :--- | :--- |
| 27B | 약 8GB~ | 약 5GB~ |
| 8B | 약 3.5GB~ | 약 2.5GB~ |
| 4B | 약 2.5GB~ | 약 2GB~ |
| 1.7B | 약 1.7GB~ | 약 1.5GB~ |

- 컨텍스트가 길어질수록(최대 100K+) 요구 VRAM은 위 수치보다 최대 2~3배까지 증가할 수 있음(README 실측: 27B Ternary 기준 4K=7.8GB → 100K=13.7GB).

#### 3.2.3 소프트웨어 인터페이스 (Software Interfaces)
- **git:** 저장소 clone/pull.
- **PowerShell 5.1+:** `setup.ps1`, `scripts\start_llama_server.ps1` 실행(`-ExecutionPolicy Bypass`).
- **winget / uv / Python 3.11~3.13:** `setup.ps1`이 내부적으로 자동 설치 및 `.venv` 구성.
- **HuggingFace Hub API(`hf` CLI):** 모델 GGUF 파일 다운로드.
- **llama-server(llama.cpp 빌드):** 실제 추론 서버 바이너리, GPU 종류(CUDA/HIP/Vulkan/CPU)에 맞게 자동 선택.

#### 3.2.4 통신 인터페이스 (Communications Interfaces)
- 모델 다운로드: HuggingFace(HTTPS).
- 로컬 API 서버: HTTP, 기본 `127.0.0.1:8080`. 사용자가 LAN 노출을 선택하면 `0.0.0.0:8080`으로 바인딩(Tailscale IP 등 외부 인터페이스에서 접근 가능해짐. 단, 방화벽 인바운드 허용은 별도 필요).

### 3.3 비기능적 요구사항 (Nonfunctional Requirements)

#### 3.3.1 성능 (Performance)
- 실시간성 요구 없음. 전체 소요 시간은 네트워크 속도(모델 다운로드, 수 GB)와 GPU 빌드/드라이버 상태에 지배됨.

#### 3.3.2 보안성 (Security)
- HuggingFace 토큰 프롬프트는 **공개 저장소 전제 하에** 자동 스킵 처리. 향후 비공개 모델 대응이 필요해지면 이 자동화가 실패 지점이 될 수 있음(알려진 트레이드오프, 2.5절 참조).
- `BONSAI_HOST=0.0.0.0` 선택 시 인증 없는 API 서버가 네트워크에 노출됨을 사용자에게 명시적으로 경고.

#### 3.3.3 신뢰성 및 가용성 (Reliability & Availability)
- 각 단계(git, setup.ps1)마다 `errorlevel` 검사로 실패 시 다음 단계로 진행하지 않고 즉시 중단.
- 배치파일 자체의 인코딩 신뢰성이 핵심 이슈였음 — 상세 트러블슈팅은 4.2절 참조.

---

## 4. 기타 요구사항 (Other Requirements)

### 4.1 유지보수 정책
- **`run_bonsai.ko.bat`은 CP949로 인코딩되어 있다.** 향후 수정 시 일반 텍스트 에디터(UTF-8 저장)로 직접 편집하면 한글 파싱이 다시 깨질 수 있으므로, UTF-8 초안을 작성한 뒤 `iconv -f UTF-8 -t CP949//TRANSLIT`로 변환 + CRLF 줄바꿈 적용 후 덮어쓰는 절차를 지킬 것. `run_bonsai.bat`(영어)은 순수 ASCII라 이 제약이 없고 Edit/Write로 직접 수정해도 안전함.
- **런처가 두 벌(`run_bonsai.bat` 영어 / `run_bonsai.ko.bat` 한국어)이므로, 로직을 바꿀 때는 양쪽 다 반영해야 한다.** 자세한 배경은 4.2절 "문제 11" 참조.

### 4.2 개발 이력 및 트러블슈팅 기록

**배경 — 왜 만들게 되었나**
사용자가 `Bonsai-demo` 저장소를 매번 `git clone` → `cd` → PowerShell 스크립트 실행 순서로 수동 설치하는 것을 번거로워하여, 더블클릭 한 번으로 끝나는 배치파일을 요청. 이후 대화 과정에서 "하드코딩된 기본값 대신 실행 중 선택", "VRAM 정보 표시", "Tailscale/LAN 노출 여부 선택" 등 요구사항이 점진적으로 추가됨.

**문제 1 — 배치파일 구조 파싱 붕괴 (2건, 순차 발생)**
- **증상:** 실행 시 `'REPO_DIR"' is not recognized`, `'errorlevel' is not recognized`, `'HOST' is not recognized` 등 스크립트 내부 변수/키워드 조각들이 개별 명령어로 실행 시도되며 실패. 최종적으로 `cd`가 제대로 되지 않아 마지막 PowerShell 호출이 엉뚱한 폴더에서 `.ps1` 파일을 찾지 못함.
- **원인:** 배치파일이 UTF-8로 저장되어 있었는데, cmd.exe는 배치파일을 읽을 때 **시스템 기본 코드페이지**(한글 Windows = CP949)를 기준으로 파싱한다. CP949는 2바이트 조합 규칙을 갖는 DBCS 인코딩인데, UTF-8 한글은 3바이트 시퀀스라서 CP949 파서가 이를 읽으면 바이트 정렬이 어긋난다(desync). 그 결과 한글 뒤에 바로 이어지는 ASCII 구조 문자(따옴표 `"`, 괄호 `(` `)`)가 "가짜 2바이트 문자"의 일부로 씹혀 사라지고, `if/else (...)` 블록이 닫히지 않은 채로 취급되어 이후 여러 줄이 통째로 오염됨.
- **1차 시도(실패):** 스크립트 맨 위에 `chcp 65001`(UTF-8 콘솔 모드) 추가 → 효과 없음. cmd.exe가 배치파일 자체의 소스를 줄 단위로 읽어 들이는 동작은 `chcp`로 즉시 바뀌지 않기 때문(콘솔 출력 코드페이지와 배치파일 파싱은 별개 문제).
- **최종 해결:** 배치파일을 UTF-8이 아니라 **CP949로 직접 인코딩**하여 저장(`iconv -f UTF-8 -t CP949//TRANSLIT` + CRLF 줄바꿈 강제). PowerShell로 CP949 디코딩해 실제 내용이 깨지지 않음을 검증. 이후 구조적 파싱 오류는 재발하지 않음.
- **부가 문제:** 구조는 정상화됐지만 콘솔에 출력되는 한글이 여전히 깨져 보임(글자 자체의 표시 문제, 파싱과는 별개) → 스크립트 최상단에 **`chcp 949`**(파일 인코딩과 동일한 코드페이지로 콘솔 출력 전환)를 추가하여 해결.
- **재발 방지 조치:** Edit/Write 같은 일반 파일 편집 도구는 UTF-8로 저장하므로, 이 파일을 다시 그런 도구로 직접 수정하면 동일한 문제가 재발함. 이후 모든 수정은 "UTF-8 초안 작성 → iconv로 CP949 변환 → 덮어쓰기" 파이프라인으로 처리하기로 함(4.1절에도 명시).

**문제 2 — HuggingFace 토큰 프롬프트로 인한 무인 실행 중단**
- **증상:** `setup.ps1` 실행 중 `Optional HuggingFace token for any still-private repo (press Enter to skip)` 프롬프트에서 자동화가 멈춤.
- **검토:** 다운로드 대상 저장소(`prism-ml/*-gguf`)가 모두 public이므로 토큰 없이 Enter로 넘겨도 무방함을 확인. 다만 이 프롬프트 외에 다른 대화형 입력 지점이 더 있는지 `setup.ps1`(411줄 전체) 및 `start_llama_server.ps1`, `run_llama.ps1`, `build_cuda_windows.ps1`을 `Read-Host`/`pause`/`ReadKey` 기준으로 전수 검색 → 해당 토큰 프롬프트 **단 1건**만 존재함을 확인.
- **의사결정:** "비공개 저장소 대응이 필요할 정도로 숙련된 사용자라면 애초에 이 자동화 스크립트 대신 `setup.ps1`을 직접 쓸 것"이라는 판단 하에, `setup.ps1` 호출부에 표준입력 리다이렉트(`< nul`)를 추가하여 해당 프롬프트를 무조건 자동 스킵하도록 결정.

**문제 3 — 모델 크기별 VRAM 수치의 근거 부재**
- README에는 27B와 8B 일부에 대한 실측 메모리 표만 존재하고 4B/1.7B는 수치가 없었음.
- HuggingFace API(`/api/models/{repo}/tree/main`)로 각 GGUF 양자화 파일(Q1_0/Q2_0)의 실제 바이트 크기를 직접 조회하고, README의 27B/8B 실측 표에서 관찰되는 "가중치 크기 + 약 1.2~1.5GiB 오버헤드(짧은 컨텍스트 기준)" 패턴을 적용해 4B/1.7B 수치를 추정. (8B 추정치가 README의 8B 실측치와 거의 일치해 방법론을 교차 검증함.)

**문제 4 — 27B 전용 기능 범위 오인 가능성**
- 처음엔 "27B만 이미지 지원"으로 단순화했으나, 실제로는 README상 27B가 "신세대" 모델로 도구 호출/MCP, 추론(Thinking) 모드, 262K 롱 컨텍스트, 스펙큘레이티브 디코딩(dspark 드래프터)까지 독점하고 8B/4B/1.7B는 "구세대 텍스트 전용" 모델로 명시되어 있음을 재확인.
- 사용자 판단에 따라 이 중 **이미지 입력**과 **추론(Thinking) 모드** 두 가지만 사용자 의사결정에 중요하다고 보고, 배치파일의 크기 선택 메뉴에 `*중요*` 문구로 강조 표시.

**문제 5 — `chcp 949`가 공유 콘솔을 오염시켜 다른 프로세스의 UTF-8 출력까지 깨뜨림**
- **증상:** `run_bonsai.bat`을 VSCode 통합 터미널 등 다른 프로세스와 공유하는 콘솔에서 실행하면, 스크립트가 종료된 뒤에도 한글/이모지를 포함한 이후의 모든 UTF-8 출력이 깨진 문자로 렌더링됨.
- **원인:** `chcp`는 프로세스 단위가 아니라 **콘솔(conhost/pseudoconsole) 단위** 설정이다. 배치파일이 파싱·표시 문제를 해결하기 위해 `chcp 949`를 실행하면(문제 1 참조) 그 콘솔을 공유하는 다른 모든 프로세스의 출력 렌더링도 함께 949로 바뀌어버린다. 배치파일 자체는 정상 동작하지만, 공유 터미널을 사용하는 다른 작업(예: 같은 창에서 진행 중이던 AI 코딩 어시스턴트 세션)에 부수효과로 번짐.
- **대응:** 발생 시 `chcp 65001`로 즉시 복구 가능(콘솔 재시작 불필요). 재발 방지를 위해 이 스크립트는 앞으로 격리된 새 콘솔 창(`start cmd /c run_bonsai.bat`)에서만 실행하기로 함 — 공유 중인 터미널의 코드페이지에 영향을 주지 않도록.

**문제 6 — `start /B`로 띄운 백그라운드 PowerShell의 콘솔 출력 인코딩이 어긋남**
- **증상:** `show_connection_info.ps1`을 연결 정보 표가 로딩 로그 뒤에 뜨도록 `start "" /B`로 백그라운드 실행했더니, 같은 콘솔(`chcp 949` 적용됨)에서 실행 중인데도 한글 부분만 깨져서 출력됨. 직접(포그라운드) 실행했을 때는 문제없었음.
- **원인:** `start /B`로 띄운 프로세스가 부모 콘솔을 공유하긴 하지만, PowerShell의 `[Console]::OutputEncoding`이 그 시점의 실제 콘솔 코드페이지(949)를 항상 정확히 물려받지는 않음.
- **해결:** 스크립트 최상단에서 `[Console]::OutputEncoding`을 `GetEncoding(949)`로 명시적으로 강제 설정. 이후 정상 출력 확인.

**문제 7 — 27B 실행 시 VRAM을 필요 이상으로(16GB+) 사용**
- **증상:** 1-bit 27B(가중치+mmproj 합쳐 5GB 남짓)를 돌리는데도 실제 VRAM 사용량이 16GB 가까이 나옴.
- **원인:** `start_llama_server.ps1`이 27B에 `-ngl 99`(GPU 레이어 강제)와 `-c 0`(컨텍스트 auto-fit)을 동시에 사용하는데, `-ngl`이 사용자 강제값이라 auto-fit 로직이 `n_gpu_layers already set by user to 99, abort`로 포기하고 모델의 최대 학습 컨텍스트(262144)를 `n_parallel=4` 슬롯 전부에 그대로 할당함. 실제 대화 길이와 무관하게 이 KV 캐시가 VRAM 대부분을 차지함.
- **해결:** `run_bonsai.bat`에 `BONSAI_CTX`(기본 8192) 환경변수를 추가하고, `start_llama_server.ps1` 호출 시 `-c %BONSAI_CTX%`를 추가 인자로 넘겨서 덮어씀. llama.cpp가 `-c`를 여러 번 받으면 "마지막 값만 사용"한다는 점을 활용 — 저장소 스크립트 자체는 수정하지 않음(SRS 1.2 범위 준수). `config.bat`에도 `BONSAI_CTX` 줄을 저장/노출해서 사용자가 직접 조절할 수 있게 함.
- **효과 확인(통제 조건, 채팅 전 유휴 상태 기준):** 4개 슬롯 모두 `n_ctx = 8192`로 로드됨을 로그로 확인. 대기 VRAM 약 1.4GB에서, `BONSAI_CTX=262144`(수정 전 기본값)일 때 약 14.1GB까지, `BONSAI_CTX=8192`(현재 기본값)일 때 약 10.5GB까지 상승 — 약 3.6GB 절약.
- **후속 — 업스트림 RAM 기반 기본값(이슈 #114 → PR #120, 업스트림 병합):** 이후 `start_llama_server.ps1`이 raw `-c 0` 대신 `$env:BONSAI_CTX`를 직접 읽는 RAM 기반 기본값으로 바뀜(변수명 동일). 이 장비(시스템 RAM 61GB)에서 해당 tier는 **65536**으로 결정됨. 동일 조건으로 재측정(Ternary-Bonsai-27B Q2_0, `-ngl 99`, mmproj 로드, 유휴 기준선 1220 MiB): **고정 8192 → 10410 MiB 사용, RAM tier 65536 → 14079 MiB 사용 — +3669 MiB(약 3.6GB), 토큰당 약 65.5 KB의 순수 KV 캐시.** 깨끗한 기준선에서는 둘 다 16303 MiB 천장 아래로 들어가지만, tier는 **여유 VRAM이 아니라 시스템 RAM**을 기준으로 잡기 때문에 16GB 카드에서는 유휴 기준선이 높거나 긴 프롬프트가 들어오면 OOM이 날 수 있음. 업스트림이 이제 `BONSAI_CTX`를 직접 읽으므로, 런처는 고정값을 고른 경우에만 `-c`를 전달함. 컨텍스트 메뉴는 **고정 8192**(기본)와 **자동(공식 RAM 기반)**(BONSAI_CTX를 비움) 중 선택하게 함.

**문제 8 — 한국어 실사용 시 답변 품질 저하(언어 혼입) — bonsai/ternary 공통**
- **증상:** bonsai(1-bit) 27B에서 한국어로 물으면 답변에 중국어/영어 단어가 섞여 나오거나("常见的" 등), 간단한 어휘를 잘못 해석하는 오답(예: "빨라"를 "빨간색"으로 오인)이 재현됨.
- **1차 원인 추정(수정됨):** 처음엔 "1-bit 양자화 특유의 트레이드오프"로 보고 ternary(2-bit) 전환을 권장했으나, 같은 이미지·질문을 ternary(2-bit) 27B로 재현했더니 **동일한 현상이 그대로 발생**함(예: "서리하고美しい场景", "항목들이Displayed 되어 있습니다", "이름更改" 등 문장 내부 단어 단위 언어 혼입). 즉 원인은 1-bit 양자화 고유의 문제가 아니라 **패밀리와 무관하게 한국어 자체가 이 모델들의 약점**인 것으로 정정함.
- **대응:** 근본적으로 모델 자체의 한계라 배치파일에서 고칠 수 없음. 패밀리 선택 메뉴(`run_bonsai.bat`)와 README.md FAQ의 경고를 "ternary로 바꾸면 해결"에서 "**패밀리 무관, 영어 사용을 권장**"으로 정정함.

**미해결 이슈(기록만 하고 기능 구현은 보류) — CUDA 런타임 DLL 매 실행 재다운로드**
- `setup.ps1`의 GPU 바이너리 다운로드 로직(스크립트 내 CUDA 분기)은 메인 llama.cpp 바이너리엔 `.llama_release` 스탬프로 존재 여부 체크가 있지만, 바로 옆의 CUDA 런타임 DLL(cudart) 다운로드 블록엔 그 체크가 없어 이미 받아둔 상태에서도 매번 재다운로드함(몇 초~몇십 초 낭비, 기능 오류는 아님).
- `config.bat`만 지우고 모델을 바꿔 재설치할 때도 매번 이 낭비가 재현됨.
- **검토 결과(수정 보류):** 이 로직은 `Bonsai-demo` 저장소 소유 파일(`setup.ps1`) 안에 있어 SRS 1.2 제외 범위(저장소 내부 스크립트 무수정)에 해당함. 직접 패치하면 다음 `git pull` 때 "로컬 수정 때문에 병합 불가"로 pull 자체가 실패해 재실행 자동화가 막힐 위험이 있음. 안전하게 하려면 매 실행마다 "pull 전 원복 → pull → 패치 재적용" 절차가 필요한데, 절약되는 시간 대비 복잡도가 커서 사용자 판단 하에 수정하지 않기로 함.

**문제 9 — mmproj 양자화 선택 불가 (해결됨)**
- **증상:** 27B의 mmproj(비전 프로젝터)는 HuggingFace 저장소에 `BF16`(~0.87GiB)과 `Q8_0`(~0.59GiB) 두 버전이 존재하는데, `setup.ps1`의 다운로드 패턴이 와일드카드 `*mmproj*.gguf`라서 두 버전을 전부 받고, `start_llama_server.ps1`은 `Get-ChildItem *mmproj*.gguf | Select-Object -First 1`로 알파벳순 첫 번째(BF16)를 무조건 선택함. 즉 저장소 구조상 선택 기능 자체가 없었음.
- **해결:** `resolve_mmproj.ps1`을 새로 만들어 `run_bonsai.bat`이 `start_llama_server.ps1` 호출 직전(:start_server)에 실행하도록 연결. `BONSAI_MMPROJ`(기본 BF16, 27B 크기 선택 시 메뉴로 물어봄)에 맞는 파일만 모델 폴더에 남기고, 나머지는 같은 폴더 안 `mmproj_alt\`로 옮겨서 글롭에서 제외시킴(삭제가 아니라 이동이라 재다운로드 없이 되돌릴 수 있음). `config.bat`의 `BONSAI_MMPROJ` 값만 바꾸고 재실행하면 언제든 전환 가능. `Bonsai-demo` 저장소 스크립트는 무수정.
- **검증:** BONSAI_MMPROJ=Q8_0으로 재실행 → 로그에 `loaded multimodal model, 'Bonsai-27B-mmproj-Q8_0.gguf'` 확인, mmproj 메모리 추정치 1161MB→873MB로 감소. BF16으로 재전환 시 재다운로드 없이 정상 복원됨을 확인.

**문제 10 — mmproj 메뉴 추가 직후 최초 실행이 파싱 오류로 깨짐 (해결됨)**
- **증상:** 문제 9의 메뉴를 처음 넣고 실제 최초 실행(클론→메뉴→setup.ps1→...) 전체를 테스트해보니, setup.ps1이 끝난 직후 `정밀도를은(는) 예상되지 않았습니다`라는 cmd 파싱 에러가 뜨고 그 뒤로 LAN 선택/서버 기동이 정상 진행되지 않음. `config.bat`가 이미 있는 재실행 경로에서는 이 구간을 안 거치므로 재실행 테스트만으로는 못 잡았던 버그.
- **원인:** 새로 추가한 `if "%BONSAI_MODEL%"=="27B" ( ... )` 여러 줄짜리 블록 안의 `echo` 텍스트에 `이미지 인식(mmproj)`, `(약 0.87GB, 기본)`처럼 **괄호 문자를 그대로 넣음**. cmd.exe는 여러 줄 블록을 파싱할 때 `echo` 인자 안이라도 `(`/`)`를 실제 블록 구조로 오인해서 깊이 계산이 어긋남 — 이 파일의 다른 메뉴들은 전부 블록 내부 echo에 괄호를 안 썼는데 이번에만 실수로 들어감(문제 1의 CP949 desync와는 다른, "여러 줄 블록 안 괄호 문자" 계열의 별도 함정).
- **해결:** 해당 블록의 `echo`/`choice` 문구에서 괄호를 전부 제거(`인식(mmproj)` → `인식 mmproj`, `(약 0.87GB, 기본)` → `- 약 0.87GB, 기본` 등). 블록 밖(top-level) echo의 괄호는 문제없음을 재확인(예: `*주의*` 경고 문구, LAN 안내 문구는 계속 정상 동작).
- **교훈:** 앞으로 여러 줄 `( ... )` 블록 안에 새 echo를 추가할 때는 재실행(config.bat 존재) 경로뿐 아니라 **최초 실행 전체 경로**도 반드시 테스트할 것 — 두 경로가 지나는 코드가 다르다.

**문제 11 — 문서(README/SRS) 영문화 후, 런처 자체의 다국어 지원 여부 결정**
- **배경:** README.md/SRS.md를 영문 기본 + 한국어 버전(`*.ko.md`)으로 이중화한 뒤, "그럼 배치파일 자체도 두 개 만들어야 하나?"라는 질문이 나옴. 4.1절에 명시된 대로 애초에 "다국어 지원 계획 없음"이었던 결정을 재검토.
- **검토:** `.bat` 파일에 한글을 넣으려면 파일 전체가 CP949여야 하고 `chcp 949`도 필요함(문제 1 참조) — 즉 하나의 배치파일 안에서 런타임에 언어를 스위칭하는 건 이 CP949 제약과 잘 안 맞음. 반대로 순수 영어 텍스트는 어떤 코드페이지에서도 깨지지 않으므로, 영어 버전은 CP949/chcp 관련 코드가 아예 필요 없어짐(비한국어 로케일 Windows에서 `chcp 949` 자체가 실패할 수 있는 리스크도 같이 해소됨).
- **결정:** 문서와 같은 방식으로 파일을 분리하기로 함 — `run_bonsai.bat`(영어, 기본, 순수 ASCII, CP949/chcp 불필요) + `run_bonsai.ko.bat`(한국어, 기존 CP949 파일을 그대로 이름만 변경). `show_connection_info.ps1`/`resolve_mmproj.ps1`은 `.ps1`이라 CP949 제약이 없으므로 파일을 나누지 않고, 새 환경변수 `BONSAI_LANG`(각 `.bat`이 자신의 언어로 하드코딩해서 설정, `config.bat`에는 저장하지 않음)으로 내부 분기 처리 — 두 벌 유지보수 부담을 최소화.
- **주의:** `config.bat`(패밀리/크기/호스트/컨텍스트/mmproj)은 두 런처가 공유한다. 언어는 `config.bat`에 저장되지 않고 매번 실행한 `.bat` 파일이 결정하므로, 어느 언어로 실행하든 저장된 모델 설정에는 영향 없음.
- **검증:** 두 런처 모두 `config.bat`가 있는 재실행 경로로 실제 서버까지 기동해 확인 — 영어 런처는 영어 연결 정보 표, 한국어 런처는 한국어 표가 정상 출력됨(`server is listening`까지 도달).

**문제 12 — 연결 정보 표의 간헐적 한글 깨짐, Windows 11의 콘솔 위임(Windows Terminal/ConPTY)과 연관**
- **증상:** `show_connection_info.ps1`(문제 6 수정 이미 적용됨)이 출력하는 연결 정보 표가 매번은 아니고 가끔씩 한글이 깨져서 나옴.
- **조사:** 이 PC의 레지스트리 `HKCU\Console`의 `DelegationConsole`/`DelegationTerminal` 값이 둘 다 미설정("Windows가 알아서 결정")인데, Windows 11 24H2 이상에서는 이 경우 콘솔 앱이 레거시 conhost 창이 아니라 기본적으로 Windows Terminal(ConPTY)로 열림 — 문제 5에서 만든 "격리된 새 콘솔"(`start cmd /c ...`)도 예외가 아님. `start "" /B`로 잠시 뒤에 붙는 백그라운드 프로세스로 `chcp`/`SetConsoleOutputCP`가 전파되는 것(문제 6이 다루는 바로 그 경로)은 ConPTY 위에서 원래 불안정한 걸로 알려져 있음. 별도로, 문제 6의 수정 코드는 `[Console]::OutputEncoding` 대입을 재시도 없는 빈 `try {} catch {}`로만 감싸놓아서, 코드페이지가 실제로 전파되기 전에 이 한 번의 시도가 실행되면 조용히 잘못된 인코딩으로 넘어갔음.
- **다른 파일 감사:** 프로젝트의 모든 `.bat`/`.ps1`(업스트림 무수정 파일인 `Bonsai-demo/setup.ps1`, `scripts/start_llama_server.ps1`, `scripts/build_cuda_windows.ps1` 포함)을 같은 유형의 위험이 있는지 점검함. `resolve_mmproj.ps1`은 아무것도 출력하지 않음. `run_bonsai.bat`은 순수 ASCII. `run_bonsai.ko.bat`의 한글은 `chcp 949`를 실행한 바로 그 프로세스가 동기적으로 파싱하는 정적 파일 내용이라(문제 1의 해결책 — 다른 메커니즘) 이번 문제 같은 프로세스 간 경합의 대상이 아님. 업스트림 스크립트들의 비-ASCII 바이트는 전부 출력되지 않는 `#` 주석 안에만 있고, 실제로 출력되는 `-ForegroundColor Red` `[ERR]` 줄들은 전부 순수 ASCII라서 빨갛게 뜰 순 있어도 인코딩 때문에 깨질 수는 없음. 실제 한글 텍스트가 새 프로세스의 콘솔 attach를 거치는 파일은 `show_connection_info.ps1`이 유일했고, 이번 문제의 유일한 위험 지점이었음을 확인.
- **해결:** 한 번만 시도하던 `[Console]::OutputEncoding` 대입을, `chcp`가 내부적으로 호출하는 것과 같은 Win32 `SetConsoleOutputCP(949)` API를 직접 호출하고 `GetConsoleOutputCP()`로 실제 적용 여부를 확인하는 재시도 루프(최대 10회, 100ms 간격)로 교체. 그 뒤에 기존과 동일하게 `[Console]::OutputEncoding` 대입도 유지함.
- **검증:** 수정된 스크립트가 PowerShell 파서 검사를 통과함, 런처 정상 흐름에서 회귀 없음 확인.
