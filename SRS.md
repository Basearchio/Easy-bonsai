🇺🇸 English | 🇰🇷 [한국어](./SRS.ko.md)

# Bonsai Local-Run Automation Batch File — Software Requirements Specification (SRS)

> **Document Info**
> - **Version:** v1.0
> - **Date:** 2026-07-19
> - **Author:** Basearchio
> - **Status:** Draft

---

## 1. Introduction

### 1.1 Purpose
This document is the Software Requirements Specification (SRS) for an automation batch file (`run_bonsai.bat`) that makes it easy to install and run **PrismML-Eng/Bonsai-demo** (a local-LLM "Bonsai" demo) on Windows.

The author found it tedious to manually type commands like `git clone` → `cd` → `PowerShell -ExecutionPolicy Bypass -File .\setup.ps1` every time, and decided to build a batch file that goes from cloning through model selection, environment setup, and starting the chat server with a single double-click. This document records why the batch file was needed, what it needs to do, and the problems actually encountered — and how they were solved — during development.

### 1.2 Scope
This project covers the development of a single Windows batch file, **`run_bonsai.bat`**. It is a wrapper around the `PrismML-Eng/Bonsai-demo` GitHub repository — it calls the repository's own logic (`setup.ps1`, `scripts/start_llama_server.ps1`, etc.) as-is, without modification.

- **In scope:** Repo clone/update, model family/size selection UI, unattended environment setup, unattended HuggingFace auth prompt handling, network exposure scope (local/LAN) selection, chat API server startup.
- **Out of scope:** Modifying the logic of `Bonsai-demo`'s internal scripts (`setup.ps1`, `start_llama_server.ps1`, etc.), macOS/Linux support, automated GUI (Open WebUI) installation.

### 1.3 Definitions and Acronyms
- **Bonsai / Ternary-Bonsai:** Local LLM families distributed by PrismML-Eng. Bonsai is a 1-bit quantized version, Ternary-Bonsai is 2-bit.
- **mmproj:** llama.cpp's multimodal projector (vision projector) file. Needed for image input on the 27B (vision-language) models.
- **GGUF:** The model weight file format used by llama.cpp.
- **CP949 (EUC-KR):** The default ANSI codepage on Korean Windows. The root cause of this project's core encoding issue.
- **BONSAI_FAMILY / BONSAI_MODEL / BONSAI_HOST:** Environment variables read by the `Bonsai-demo` repo, specifying model family, model size, and server bind address respectively.
- **dspark:** The 27B-only drafter model used for speculative decoding.

### 1.4 References
- https://github.com/PrismML-Eng/Bonsai-demo (upstream repo, README.md)
- https://huggingface.co/prism-ml (model weight distribution, actual file sizes checked via the HuggingFace API)

---

## 2. Overall Description

### 2.1 Product Perspective
A standalone utility. It does not replace the `Bonsai-demo` repository — it sits on top of it as a thin orchestration layer that automates the repetitive parts (cloning, choosing options, running scripts in the right order).

```
run_bonsai.bat
  ├─ git clone / pull  →  Bonsai-demo/
  ├─ User choices (console menu): family, size, LAN exposure
  ├─ powershell setup.ps1        (owned by Bonsai-demo repo, unmodified)
  └─ powershell start_llama_server.ps1  (owned by Bonsai-demo repo, unmodified)
```

### 2.2 Product Functions
1. **Automatic repo clone/update:** Checks whether git is installed; clones on first run, pulls on re-run.
2. **Model selection UI:** Console number-entry to pick family (ternary/bonsai) and size (27B/8B/4B/1.7B), with expected VRAM and feature differences shown for each combination.
3. **Automated environment setup:** Runs `setup.ps1` unattended (Python/uv/venv setup, GPU detection, model download). The HuggingFace token prompt is auto-skipped via stdin redirection.
4. **Network exposure selection:** Choose local-only (127.0.0.1) or Tailscale/LAN exposure (0.0.0.0).
5. **Automatic chat server startup:** Calls `start_llama_server.ps1` to bring up the API server on port 8080.
6. **Automatic connection info display:** Right before the server starts, calls `show_connection_info.ps1` to print a table with the actual downloaded model filename, local/LAN (Tailscale auto-detected) API address, and browser chat URL.
7. **Context length control:** A menu offers **Fixed 8192** (default) or **Auto (official RAM-tier)**; the choice is stored as `BONSAI_CTX` in `config.bat` (a value = fixed cap, empty = upstream's RAM-tiered default). Fixed 8192 caps the KV cache to avoid wasting VRAM on 16GB-class GPUs.
8. **mmproj precision selection:** For 27B, offers a BF16/Q8_0 menu; the unselected variant is kept (not deleted) for reuse if switched back later.
9. **Multi-language launchers:** Two launchers are provided, `run_bonsai.bat` (English, default) and `run_bonsai.ko.bat` (Korean), with identical behavior. They share `config.bat` (model settings), but each `.bat` determines the language on every run.

### 2.3 User Classes and Characteristics
- **Single local user (solo dev/experimentation):** Finds typing git/PowerShell commands tedious and wants a "one double-click" experience. Advanced scenarios like HuggingFace private-repo auth are considered out of scope for the target user (assumption: a user who needs that would use `setup.ps1` directly instead of this script).

### 2.4 Constraints
- **Platform constraint:** Windows (cmd.exe) only. Given `.bat`'s nature, OS auto-branching is unnecessary (it only ever runs on Windows anyway).
- **Encoding constraint:** The batch file needs to contain Korean strings, but cmd.exe parses batch files based on the **system default codepage** (CP949 on Korean Windows). Saving as UTF-8 can corrupt the file's structure itself (see Chapter 4 for details). **This file must therefore be encoded as CP949, not UTF-8.**
- **Dependent-script constraint:** Inherits the option set of `setup.ps1` / `start_llama_server.ps1` as-is (e.g., no native mmproj selection). There's an inherent limit to what can be worked around without forking/modifying the repo's own scripts.
- **Execution-policy constraint:** `-ExecutionPolicy Bypass` is required to run the PowerShell scripts.

### 2.5 Assumptions and Dependencies
- Assumes git and PowerShell (5.1+) are installed on the user's PC (missing git is detected and reported; PowerShell ships with Windows so it isn't separately checked).
- Assumes HuggingFace's `prism-ml/*` model repos remain **public**. (The upstream README once said 27B would be "made public at launch"; currently confirmed downloadable without a token. If it's made private again later, unattended download could fail — a known risk.)
- Assumes winget is installed (used for the Python/uv auto-install path). If absent, `setup.ps1` only warns and requires manual installation.

---

## 3. Specific Requirements

### 3.1 Functional Requirements

| Req ID | Category | Requirement | Details | Priority |
| :--- | :--- | :--- | :--- | :--- |
| **REQ-001** | Repo management | Automatic clone/update | Reports and exits if git is missing. Branches into first-run (clone) vs. re-run (pull) based on whether `Bonsai-demo\.git` exists. | **High** |
| **REQ-002** | Model selection | Family selection menu | Console choice of 1 (ternary, default recommendation) / 2 (bonsai). Notes that 27B is a vision-language model in both families. | **High** |
| **REQ-003** | Model selection | Size selection menu | Choose among 27B/8B/4B/1.7B. Shows different VRAM figures depending on the chosen family, and highlights with `*IMPORTANT*` that image input and reasoning (Thinking) mode are **27B-only**. | **High** |
| **REQ-004** | Environment setup | Unattended provisioning | Runs `setup.ps1` with stdin redirected from `nul` to auto-skip the HuggingFace token prompt. Python/uv/venv install, GPU detection, and model (GGUF) download are delegated to `setup.ps1`. | **High** |
| **REQ-005** | Networking | Exposure scope selection | If Y, sets `BONSAI_HOST=0.0.0.0` (Tailscale/LAN access allowed, with a firewall-allow note); if N (default), sets `BONSAI_HOST=127.0.0.1` (local only). | **Medium** |
| **REQ-006** | Server startup | Automatic chat API server startup | Calls `scripts\start_llama_server.ps1` to start the server on port 8080 (foreground; closing the window stops the server). | **High** |
| **REQ-007** | Error handling | Abort on per-stage failure | Checks `errorlevel` after the git/setup stages; on failure, prints the cause, `pause`s, and exits (does not proceed to the next stage). | **High** |
| **REQ-008** | User guidance | Automatic connection-info display | Runs `show_connection_info.ps1` in the background via `start "" /B`, concurrently with `start_llama_server.ps1` (foreground), polling `/health` until it returns 200 (up to 300s) before printing the table — so it appears *after* the load logs, not before. Model filename/vision support is determined by scanning the `models\` folder; IP is dynamically detected each run via Tailscale (preferred) or LAN IPv4 (fallback). The table's footer includes "closing the window stops the server" and "Ctrl+C to stop" notes. | **Medium** |
| **REQ-009** | Resource management | Context length cap | Menu picks **Fixed 8192** (default) or **Auto (official RAM-tier)**, stored as `BONSAI_CTX` in `config.bat`. Passes `-c %BONSAI_CTX%` only when a fixed value is set (empty leaves upstream's RAM-tiered default, which reads `BONSAI_CTX` natively); Fixed 8192 shrinks the large KV cache the repo script would otherwise allocate (see Problem 7). | **Medium** |
| **REQ-010** | Model selection | mmproj precision selection | Shows a BF16/Q8_0 menu when 27B is chosen. `resolve_mmproj.ps1`, run at `:start_server`, keeps only the chosen variant in the model folder and moves the rest to `mmproj_alt\` (not deleted — switchable without re-download). Re-selectable anytime via `BONSAI_MMPROJ` in `config.bat` (see Problem 9). | **Low** |
| **REQ-011** | Localization | English/Korean launcher split | Provides `run_bonsai.bat` (English, ASCII, default) and `run_bonsai.ko.bat` (Korean, CP949) as separate files. The shared PowerShell script (`show_connection_info.ps1`) branches its output text on a `BONSAI_LANG` environment variable (set to its own language by each `.bat`, not persisted in `config.bat`). Model settings in `config.bat` are shared between both launchers (see Problem 11). | **Low** |

### 3.2 External Interface Requirements

#### 3.2.1 User Interface
- Console-based UI. Three `choice`-driven number-entry menus (family selection, size selection, LAN exposure).
- All prompts are in Korean. VRAM/feature notes are shown as a table right before each choice.

#### 3.2.2 Hardware Interfaces
- GPU VRAM requirements (minimums for a short conversation, estimated from actual HuggingFace GGUF file sizes plus README-measured overhead):

| Model size | Ternary (2-bit) | Bonsai (1-bit) |
| :--- | :--- | :--- |
| 27B | ~8GB+ | ~5GB+ |
| 8B | ~3.5GB+ | ~2.5GB+ |
| 4B | ~2.5GB+ | ~2GB+ |
| 1.7B | ~1.7GB+ | ~1.5GB+ |

- As context grows (up to 100K+), required VRAM can increase up to 2-3x beyond the figures above (measured in the upstream README: 27B Ternary at 4K context = 7.8GB → at 100K = 13.7GB).

#### 3.2.3 Software Interfaces
- **git:** Repo clone/pull.
- **PowerShell 5.1+:** Runs `setup.ps1` and `scripts\start_llama_server.ps1` (`-ExecutionPolicy Bypass`).
- **winget / uv / Python 3.11-3.13:** Auto-installed internally by `setup.ps1`, which also sets up `.venv`.
- **HuggingFace Hub API (`hf` CLI):** Downloads model GGUF files.
- **llama-server (llama.cpp build):** The actual inference server binary, auto-selected to match the detected GPU type (CUDA/HIP/Vulkan/CPU).

#### 3.2.4 Communications Interfaces
- Model download: HuggingFace over HTTPS.
- Local API server: HTTP, default `127.0.0.1:8080`. If the user chooses LAN exposure, binds to `0.0.0.0:8080` (reachable from external interfaces such as a Tailscale IP; inbound firewall allow is a separate manual step).

### 3.3 Nonfunctional Requirements

#### 3.3.1 Performance
- No real-time requirement. Total time is dominated by network speed (multi-GB model downloads) and GPU build/driver state.

#### 3.3.2 Security
- The HuggingFace token prompt is auto-skipped **on the assumption the repos are public**. If private-model support is ever needed, this automation becomes a failure point (a known trade-off — see section 2.5).
- Explicitly warns the user that choosing `BONSAI_HOST=0.0.0.0` exposes an unauthenticated API server on the network.

#### 3.3.3 Reliability & Availability
- Each stage (git, setup.ps1) is checked via `errorlevel`; on failure, execution stops immediately rather than proceeding.
- Batch-file encoding reliability was the central issue — see section 4.2 for detailed troubleshooting.

---

## 4. Other Requirements

### 4.1 Maintenance Policy
- **`run_bonsai.ko.bat` is encoded as CP949.** Editing it directly with a generic text editor (which saves as UTF-8) can corrupt Korean parsing again, so follow this procedure: draft in UTF-8 → convert with `iconv -f UTF-8 -t CP949//TRANSLIT` → apply CRLF line endings → overwrite. `run_bonsai.bat` (English) is plain ASCII, so it has no such constraint and can be edited directly with Edit/Write.
- **There are now two launchers (`run_bonsai.bat` English / `run_bonsai.ko.bat` Korean), so any logic change must be applied to both.** See "Problem 11" in section 4.2 for the background.

### 4.2 Development History and Troubleshooting Log

**Background — why this was built**
The user found it tedious to manually install the `Bonsai-demo` repo every time via `git clone` → `cd` → running the PowerShell script, and asked for a batch file that finishes with a single double-click. Requirements were added incrementally over the course of the conversation: "choose at runtime instead of hardcoding defaults," "show VRAM info," "choose whether to expose on Tailscale/LAN," etc.

**Problem 1 — Batch-file structural parsing collapse (2 incidents, in sequence)**
- **Symptom:** On execution: `'REPO_DIR"' is not recognized`, `'errorlevel' is not recognized`, `'HOST' is not recognized`, and other fragments of internal variables/keywords being attempted as standalone commands. Ultimately `cd` didn't work correctly, so the final PowerShell call couldn't find the `.ps1` file because it was in the wrong folder.
- **Cause:** The batch file was saved as UTF-8, but cmd.exe parses batch files based on the **system default codepage** (CP949 on Korean Windows). CP949 is a DBCS encoding with 2-byte combination rules, while UTF-8 Korean is a 3-byte sequence — so when the CP949 parser reads it, byte alignment desyncs. As a result, ASCII structural characters immediately following Korean text (quotes `"`, parens `(` `)`) get swallowed as part of a "fake 2-byte character," and `if/else (...)` blocks are treated as never having closed, corrupting several subsequent lines wholesale.
- **First attempt (failed):** Added `chcp 65001` (UTF-8 console mode) at the top of the script → no effect. cmd.exe's line-by-line reading of the batch file's own source isn't changed by `chcp` (console output codepage and batch-file parsing are separate concerns).
- **Final fix:** Saved the batch file encoded directly as **CP949, not UTF-8** (`iconv -f UTF-8 -t CP949//TRANSLIT` + forced CRLF line endings). Verified via PowerShell CP949 decoding that the content wasn't corrupted. Structural parsing errors did not recur afterward.
- **Secondary issue:** Structure was fixed, but Korean text printed to the console still looked garbled (a display issue, separate from parsing) → fixed by adding **`chcp 949`** at the top of the script (switches console output to the same codepage as the file's encoding).
- **Prevention measure:** Since generic file-editing tools (Edit/Write) save as UTF-8, directly re-editing this file with such tools would reintroduce the same problem. Decided that all future edits go through a "draft in UTF-8 → convert to CP949 with iconv → overwrite" pipeline (also documented in section 4.1).

**Problem 2 — Unattended execution blocked by the HuggingFace token prompt**
- **Symptom:** Automation stalls at the `Optional HuggingFace token for any still-private repo (press Enter to skip)` prompt during `setup.ps1`.
- **Investigation:** Confirmed the target repos (`prism-ml/*-gguf`) are all public, so pressing Enter with no token is fine. Also did an exhaustive search across the full 411-line `setup.ps1` plus `start_llama_server.ps1`, `run_llama.ps1`, and `build_cuda_windows.ps1` for any other interactive input points (`Read-Host`/`pause`/`ReadKey`) → confirmed this token prompt is the **only** one.
- **Decision:** Reasoned that "a user sophisticated enough to need private-repo support would use `setup.ps1` directly instead of this automation script anyway," so added stdin redirection (`< nul`) to the `setup.ps1` call to unconditionally auto-skip that prompt.

**Problem 3 — No basis for the per-size VRAM figures**
- The README only had measured memory tables for 27B and part of 8B; 4B/1.7B had no figures.
- Directly queried the actual byte size of each GGUF quant file (Q1_0/Q2_0) via the HuggingFace API (`/api/models/{repo}/tree/main`), and applied the pattern observed in the README's 27B/8B measured tables ("weight size + ~1.2-1.5GiB overhead at short context") to estimate 4B/1.7B figures. (The 8B estimate nearly matched the README's measured 8B figure, cross-validating the methodology.)

**Problem 4 — Possible misunderstanding of 27B-exclusive feature scope**
- Initially simplified to "only 27B supports images," but re-confirmed from the README that 27B is actually the "new generation" model that exclusively has tool calling/MCP, reasoning (Thinking) mode, 262K long context, and speculative decoding (dspark drafter), while 8B/4B/1.7B are explicitly "previous-generation, text-only" models.
- Per the user's judgment, decided only **image input** and **reasoning (Thinking) mode** matter for the user's decision-making among these, and highlighted them with a `*IMPORTANT*` marker in the batch file's size-selection menu.

**Problem 5 — `chcp 949` pollutes a shared console, corrupting other processes' UTF-8 output**
- **Symptom:** Running `run_bonsai.bat` in a console shared with other processes (e.g., the VS Code integrated terminal) causes all subsequent UTF-8 output — Korean text, emoji — to render as garbled characters even after the script exits.
- **Cause:** `chcp` is a **console (conhost/pseudoconsole)-level** setting, not a per-process one. When the batch file runs `chcp 949` to fix parsing/display issues (see Problem 1), it also flips the output rendering codepage to 949 for every other process sharing that console. The batch file itself works fine, but this bleeds as a side effect into other work using the shared terminal (e.g., an AI coding-assistant session running in the same window).
- **Response:** Recoverable immediately with `chcp 65001` when it happens (no console restart needed). To prevent recurrence, decided this script should only ever be run in an isolated new console window (`start cmd /c run_bonsai.bat`) going forward — so it never touches the codepage of a terminal that's shared with other work.

**Problem 6 — Console output encoding mismatch for a background PowerShell launched via `start /B`**
- **Symptom:** Ran `show_connection_info.ps1` in the background via `start "" /B` so the connection-info table appears after the load logs; even though it runs in the same console (which has `chcp 949` applied), only the Korean portions came out garbled. Running it directly in the foreground had no problem.
- **Cause:** A process launched via `start /B` does share the parent console, but PowerShell's `[Console]::OutputEncoding` doesn't always accurately pick up the console's actual codepage (949) at that point.
- **Fix:** Explicitly forced `[Console]::OutputEncoding` to `GetEncoding(949)` at the top of the script. Confirmed correct output afterward.

**Problem 7 — 27B uses more VRAM than necessary (16GB+)**
- **Symptom:** Even running a 1-bit 27B model (weights + mmproj together just over 5GB), actual VRAM usage came out close to 16GB.
- **Cause:** `start_llama_server.ps1` uses `-ngl 99` (force all layers onto GPU) together with `-c 0` (auto-fit context) for 27B. Because `-ngl` is a user-forced value, the auto-fit logic gives up with `n_gpu_layers already set by user to 99, abort` and instead allocates the model's full trained context (262144) across all `n_parallel=4` slots as-is. This KV cache consumes most of the VRAM regardless of actual conversation length.
- **Fix:** Added a `BONSAI_CTX` environment variable (default 8192) to `run_bonsai.bat`, and passed `-c %BONSAI_CTX%` as an extra argument on the `start_llama_server.ps1` call to override it — relying on the fact that llama.cpp uses "last value wins" when `-c` is given multiple times. The repo script itself was not modified (staying within SRS 1.2 scope). Also saved/exposed a `BONSAI_CTX` line in `config.bat` so the user can adjust it directly.
- **Verified effect (controlled conditions, idle before any chat):** Log confirmed all 4 slots loaded with `n_ctx = 8192`. From an idle baseline of ~1.4GB, VRAM rose to ~14.1GB with `BONSAI_CTX=262144` (the pre-fix default) versus ~10.5GB with `BONSAI_CTX=8192` (the current default) — a savings of roughly 3.6GB.
- **Follow-up — upstream RAM-tiered default (issue #114 → PR #120, merged upstream):** `start_llama_server.ps1` later replaced the raw `-c 0` with a RAM-tiered default that reads `$env:BONSAI_CTX` natively (same variable name). On this machine (61GB system RAM) that tier resolves to **65536**. Re-measured under matched conditions (Ternary-Bonsai-27B Q2_0, `-ngl 99`, mmproj loaded, idle baseline 1220 MiB): **Fixed 8192 → 10410 MiB used; RAM-tier 65536 → 14079 MiB used — +3669 MiB (~3.6GB), ~65.5 KB/token of pure KV cache.** Both fit under the 16303 MiB ceiling at this clean baseline, but the tier keys off **system RAM, not free VRAM**, so on a 16GB card a higher idle baseline or a long prompt can OOM. Since upstream now reads `BONSAI_CTX` directly, the launcher passes `-c` only when a fixed value is chosen; the context menu offers **Fixed 8192** (default) or **Auto (official RAM-tier)** (leaves `BONSAI_CTX` empty).

**Problem 8 — Degraded answer quality in real Korean usage (language mixing) — common to both bonsai and ternary**
- **Symptom:** Asking bonsai (1-bit) 27B in Korean reproducibly gets answers with Chinese/English words mixed in (e.g., "常见的"), or wrong answers from misreading simple vocabulary (e.g., mistaking "빨라" [it's fast] for "빨간색" [red]).
- **Initial (incorrect) root-cause guess, later corrected:** Initially attributed this to "a trade-off specific to 1-bit quantization" and recommended switching to ternary (2-bit). But reproducing the same image and question on ternary (2-bit) 27B showed **the exact same phenomenon** (e.g., word-level language mixing mid-sentence such as "서리하고美しい场景", "항목들이Displayed 되어 있습니다", "이름更改"). Corrected the conclusion: the cause isn't specific to 1-bit quantization — **Korean itself is a weak point for these models regardless of family.**
- **Response:** This is fundamentally a model limitation that can't be fixed at the batch-file level. Corrected the warning in the family-selection menu (`run_bonsai.bat`) and the README.md FAQ from "switch to ternary to fix it" to "**happens regardless of family — English is recommended**."

**Unresolved issue (recorded only, fix deferred) — CUDA runtime DLLs re-downloaded on every run**
- `setup.ps1`'s GPU-binary download logic (the CUDA branch) has a `.llama_release`-stamp existence check for the main llama.cpp binaries, but the adjacent CUDA runtime DLL (cudart) download block has no such check, so it re-downloads every time even when already present (wastes seconds to tens of seconds; not a functional bug).
- This waste recurs every time the user deletes `config.bat` and reinstalls with a different model.
- **Review outcome (fix deferred):** This logic lives inside a file owned by the `Bonsai-demo` repo (`setup.ps1`), which falls under SRS 1.2's out-of-scope clause (no modifying the repo's internal scripts). Patching it directly risks the next `git pull` failing with "local modifications prevent merge," which would block the re-run automation entirely. Doing it safely would require a "revert before pull → pull → reapply the patch" procedure on every run, which is too much added complexity relative to the time saved — decided, per the user's judgment, not to fix it.

**Problem 9 — No way to choose mmproj quantization (Resolved)**
- **Symptom:** 27B's mmproj (vision projector) has two versions on the HuggingFace repo, `BF16` (~0.87GiB) and `Q8_0` (~0.59GiB), but `setup.ps1`'s download pattern is the wildcard `*mmproj*.gguf`, so it downloads both, and `start_llama_server.ps1` unconditionally picks the alphabetically-first one (BF16) via `Get-ChildItem *mmproj*.gguf | Select-Object -First 1`. In other words, there was simply no selection capability given the repo's structure.
- **Fix:** Created a new `resolve_mmproj.ps1` and wired `run_bonsai.bat` to run it right before calling `start_llama_server.ps1` (at `:start_server`). It keeps only the file matching `BONSAI_MMPROJ` (default BF16; asked via menu when 27B is selected) in the model folder, and moves the rest into a `mmproj_alt\` subfolder within the same directory so the glob excludes them (moved, not deleted — reversible without re-downloading). Switchable anytime just by changing `BONSAI_MMPROJ` in `config.bat` and re-running. The `Bonsai-demo` repo scripts were not modified.
- **Verified:** Re-running with BONSAI_MMPROJ=Q8_0 → log confirmed `loaded multimodal model, 'Bonsai-27B-mmproj-Q8_0.gguf'`, and the mmproj memory estimate dropped from 1161MB to 873MB. Switching back to BF16 restored correctly with no re-download.

**Problem 10 — The very first run broke with a parse error right after the mmproj menu was added (Resolved)**
- **Symptom:** After first adding the Problem 9 menu, testing the actual first-run path end-to-end (clone → menus → setup.ps1 → ...) showed a cmd parse error — literally "was unexpected at this time" for a stray word — right after setup.ps1 finished, and the subsequent LAN-choice/server-startup steps didn't proceed correctly. Since the re-run path (where `config.bat` already exists) skips this section entirely, re-run testing alone couldn't have caught this bug.
- **Cause:** The newly added `if "%BONSAI_MODEL%"=="27B" ( ... )` multi-line block had `echo` text containing literal parentheses, like `이미지 인식(mmproj)` and `(약 0.87GB, 기본)`. When cmd.exe parses a multi-line block, it can misinterpret `(`/`)` characters as real block structure even when they're just inside an `echo` argument's text, throwing off its depth tracking — none of this file's other menus had parentheses inside block-internal `echo` text; this was a one-off mistake this time (a different pitfall from Problem 1's CP949 desync — this one is in the "literal parentheses inside a multi-line block" category).
- **Fix:** Removed all parentheses from that block's `echo`/`choice` text (e.g., `인식(mmproj)` → `인식 mmproj`, `(약 0.87GB, 기본)` → `- 약 0.87GB, 기본`). Re-confirmed that parentheses in top-level (outside any block) `echo` text are fine — e.g., the `*NOTE*` warning text and the LAN-info text continue to work correctly.
- **Lesson:** Going forward, whenever a new `echo` is added inside a multi-line `( ... )` block, both the re-run path (config.bat exists) **and the full first-run path** must be tested — they exercise different code.

**Problem 11 — After translating the docs (README/SRS) to English, deciding whether the launcher itself should be localized**
- **Background:** After splitting README.md/SRS.md into an English default plus Korean versions (`*.ko.md`), the question came up: "should the batch file itself become two files too?" This prompted revisiting the decision in section 4.1 that had originally said "no multi-language support planned."
- **Analysis:** Putting Korean text in a `.bat` file requires the whole file to be CP949-encoded and needs `chcp 949` (see Problem 1) — i.e., switching languages at runtime within a single batch file doesn't sit well with that CP949 constraint. Conversely, pure English text never gets corrupted regardless of codepage, so an English-only version needs none of the CP949/chcp machinery at all (which also removes the risk of `chcp 949` itself failing on a non-Korean-locale Windows install).
- **Decision:** Split the file the same way as the docs — `run_bonsai.bat` (English, default, plain ASCII, no CP949/chcp needed) plus `run_bonsai.ko.bat` (Korean, the existing CP949 file, just renamed). `show_connection_info.ps1` / `resolve_mmproj.ps1` are `.ps1` files with no CP949 constraint, so instead of splitting those, added a new `BONSAI_LANG` environment variable (hardcoded to its own language by each `.bat`, not stored in `config.bat`) and branched internally — minimizing the dual-maintenance burden.
- **Note:** `config.bat` (family/size/host/context/mmproj) is shared between the two launchers. The language is never stored in `config.bat` — whichever `.bat` file you run determines it each time — so switching languages never affects the saved model settings.
- **Verified:** Ran both launchers through the config-exists (re-run) path all the way to a live server — the English launcher printed an English connection-info table and the Korean launcher printed a Korean one, both reaching `server is listening`.

**Problem 12 — Intermittent Korean garbling in the connection-info block, tied to Windows 11's console delegation to Windows Terminal (ConPTY)**
- **Symptom:** The connection-info table printed by `show_connection_info.ps1` (Problem 6's fix already applied) still occasionally rendered with garbled Korean — not on every run, only sometimes.
- **Investigation:** This machine's `HKCU\Console` registry values `DelegationConsole`/`DelegationTerminal` are both unset ("let Windows decide"), which on Windows 11 24H2+ defaults console apps to opening inside Windows Terminal via ConPTY rather than a legacy conhost window — including the "isolated new console" (`start cmd /c ...`) from Problem 5's fix. `chcp`/`SetConsoleOutputCP` propagating to a background process that attaches to the console moments later (`start "" /B`, the exact case Problem 6 covers) is a known-flaky path under ConPTY. Separately, Problem 6's fix wrapped the `[Console]::OutputEncoding` assignment in a bare `try {} catch {}` with no retry — if that single attempt ran before the codepage had actually propagated, it silently fell back to the wrong encoding.
- **Audit of other files:** Checked every `.bat`/`.ps1` in the project, including the upstream, unmodified `Bonsai-demo/setup.ps1`, `scripts/start_llama_server.ps1`, and `scripts/build_cuda_windows.ps1`, for the same class of risk. `resolve_mmproj.ps1` prints nothing at all. `run_bonsai.bat` is pure ASCII. `run_bonsai.ko.bat`'s Korean text is static file content parsed synchronously by the same process that ran `chcp 949` (Problem 1's fix — a different mechanism, not subject to this cross-process race). The upstream scripts' only non-ASCII bytes sit inside `#` comments that are never printed; every actual `-ForegroundColor Red` `[ERR]` line in them is plain ASCII, so it can legitimately show red without ever being encoding-garbled. `show_connection_info.ps1` was the only file with real Korean text crossing a new-process console attach, confirming it was the sole risk point.
- **Fix:** Replaced the single-attempt `[Console]::OutputEncoding` assignment with a loop that calls the Win32 `SetConsoleOutputCP(949)` API directly (the same call `chcp` itself makes) and verifies via `GetConsoleOutputCP()` that it actually took effect, retrying up to 10 times (100ms apart) before falling through to the `[Console]::OutputEncoding` assignment as before.
- **Verified:** PowerShell parser check passed on the updated script; no regression in the normal launcher flow.
