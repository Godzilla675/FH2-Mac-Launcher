# Forza Horizon 2 — macOS Apple Silicon Installer & Launcher

A turnkey, native macOS SwiftUI installer and launcher app (`Forza Horizon 2.app`) that allows users to install and play **Forza Horizon 2 (Xbox One v1.0.0.64)** on Apple Silicon Macs (M1 / M2 / M3 / M4 / M5) for **100% free** using Apple's `D3DMetal` (Game Porting Toolkit / Highball) or CrossOver.

## Features

- **100% Free Wine + D3DMetal Engine Strategy**:
  - Automatically detects **CrossOver.app**, **Highball**, or **Game Porting Toolkit.app** (`gcenx/wine/game-porting-toolkit`).
  - Includes a one-click **"Set Up Free Runtime"** button that silently provisions Rosetta 2 and the free Wine64 + Apple `D3DMetal.framework` graphics runtime in the background with live progress updates—never opening Terminal.app and never invalidating Apple's `anchor apple` signature on `D3DMetal.framework` / `libd3dshared.dylib`.
- **All-in-One Bundled Payload (`Contents/Resources/payload/`)**:
  - **`d3d12.dll` & `fh2pad.dll`**: Compiled from [`fladnaG86/FH2-Port-AppleSilicon`](https://github.com/fladnaG86/FH2-Port-AppleSilicon) (`OpenExistingHeapFromAddress` emulation, 8x→4x MSAA showroom cap, `D3D12_APPEND_ALIGNED_ELEMENT` per-slot layout fix, inline `gs:[0x20]` fiber read patch, `NtFlushProcessWriteBuffers` `mprotect` serialization, `NtAllocateVirtualMemoryEx` high-range placement, and `Windows.Gaming.Input.Gamepad` DualSense/Xbox/Keyboard merger).
  - **`d3dcompiler_47.dll`**: Microsoft's native 64-bit shader compiler (extracted from Firefox 62.0 win64) so Azimuth's GPU detile shaders compile cleanly.
  - **Azimuth (`0.9.10` Default & `1.0.1`)**: Both builds pre-bundled and selectable via the UI.
  - **Optional DLC & QoL Mod (`ForzaHorizon2_ExtraOptions` v0.4.4)**: Bundled from [`RokkuDayo/ForzaHorizon2_ExtraOptions`](https://github.com/RokkuDayo/ForzaHorizon2_ExtraOptions) with a one-click UI switch to unlock all DLC cars and skip intro videos.
