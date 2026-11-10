# Forza Horizon 2 — macOS Apple Silicon 1-Click A-to-Z Installer & Launcher (`v1.1.1`)

A native macOS SwiftUI turnkey A-to-Z installer and launcher (`Forza Horizon 2.app`) engineered for Apple Silicon Macs (M1 / M2 / M3 / M4 / M5). Designed for non-technical users on a brand-new Mac out of the box—no Homebrew, no Xcode Command Line Tools, and no manual terminal commands required.

---

## What's New in `v1.1.1`

1. **32-Bit Installer Unpacker Wine Runtime (`Step 3/4`):**
   - Automatically resolves and uses **Wine Crossover 23.7.1-1** (Wine 8.0.1 with dynamic WoW64 memory mapping) as the unpacker engine for 32-bit `setup.exe` (Inno Setup 5.5.1), preventing the fatal Apple Wine 7.7 `Assertion failed: (end <= pages_vprot_size << pages_vprot_shift), function alloc_pages_vprot, file virtual.c, line 1032` (exit code `105`) crash.
   - Automatically detects if the game is already unpacked in `C:\FH2Game`, skips re-running `setup.exe`, moves it to `~/Games/Forza Horizon 2`, and proceeds immediately to Step 4.
2. **Zero-Dependency Brand-New Mac Setup (`Step 1/4`):**
   - Automatically checks and installs **Rosetta 2** if missing.
   - Directly downloads and extracts **Game Porting Toolkit (`Wine64` + Apple-signed `D3DMetal.framework`)** into `~/Applications/Game Porting Toolkit.app` without requiring Homebrew or Xcode Command Line Tools, while also supporting CrossOver and Highball if already installed.
3. **Bulletproof Auto-Resumable 16.8 GB Cloud Downloader (`Step 2/4`):**
   - Automatically resolves Google Drive's large-file confirmation token (`uuid` / `at`) for `FH2-Game.zip` (`1VVmQ3d_qHOj6UhPfslSgeaBfQbc3zYcf`, `18,001,002,054` bytes) and streams to `~/Games/FH2_Setup_Cache/FH2-Game.zip.part`.
   - Uses `curl -L -C - --retry 999 --retry-delay 5 --retry-all-errors --connect-timeout 15` inside an automatic token-refresh retry loop so if Wi-Fi drops, the internet disconnects, or the app is closed and reopened, the download resumes from the exact byte offset on disk without ever restarting from 0%.
4. **Bundled `7zz` Extraction & Silent 40 GB Game Unpacking (`Step 3/4`):**
   - Bundles static macOS Universal `7zz` (`Contents/Resources/bin/7zz`) to extract `FH2-Game.zip` into a bracket-free staging path (`drive_c/fg_setup`) and immediately deletes `FH2-Game.zip` to save 17 GB of disk space.
   - Neutralizes `_Redist/QuickSFV.exe` and `MD5/QuickSFV.EXE` with a silent Windows no-op executable (`noop.exe`) so the installer never hangs at 100% waiting for an MD5 checksum window.
   - Runs `setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /DIR="C:\FH2Game" /LOG` (logs copied to `~/Library/Logs/FH2Port/`) while displaying live GB and percentage progress (`du -sk`), moves the unpacked game to `~/Games/Forza Horizon 2`, deletes `drive_c/fg_setup`, and restores the bottle to `win10`.
5. **Automatic Azimuth + Apple Silicon D3D12 & Controller Configuration (`Step 4/4`):**
   - Bundles clean **Azimuth `0.9.10`** (default) and **`1.0.1`**, custom **`d3d12.dll`** (fiber `gs:[0x20]` patch + 4x MSAA cap), **`fh2pad.dll`** (`Windows.Gaming.Input.Gamepad` provider + `WineBus` `DisableHidraw=1`), **`d3dcompiler_47.dll`**, and **`ForzaHorizon2_ExtraOptions`**.
   - Pre-fills `drive_c/Azimuth/data/azimuth.ini` (UTF-16LE with BOM) with the unpacked game folder path, `antialiasing=off`, and `resolution=1440`, and launches `azimuth.exe --skip-launcher` with `D3DMETAL=1` and `ROSETTA_ADVERTISE_AVX=0`.
