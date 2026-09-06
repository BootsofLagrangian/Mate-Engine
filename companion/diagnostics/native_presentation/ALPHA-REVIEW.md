# Actual Windows compositor comparison

Independent reviewer: Astra face. 2026-09-06. Source GUI scope; exported package follow-up remains required.

Temporary owned WinForms magenta backdrops were placed directly behind the exact PID-owned target HWND. Only known overlap pixels were sampled, guarded by WindowFromPoint; pet samples additionally used GetWindowRgn and PtInRegion. Backdrops were disposed in finally. No pet movement/input or unrelated desktop image capture.

- Vulkan source PID40032: root HWND3935318, region box (231,158)-(576,730), four inset region corners owned by root returned black RGB(0,0,0). Prop HWND6032080, owned clear corner returned black. Both style 0x96080000.
- D3D12 source PID5032: root HWND2166738, same region box. Local points (234,161), (234,726), (572,726) were inside the region and owned by root, and returned exact magenta RGB(255,0,255). Point (572,161) was skipped because another window owned it. Prop HWND3609116 clear corner was owned by prop and returned exact magenta. Both style 0x96080000.
- PID5032 executable identity was the workspace Godot_v4.5.2-stable_win64.exe, with explicit `--path .../native --rendering-driver d3d12`. The copied live `logs/windows-d3d12-source.log` confirms D3D12 12_0, Forward+, NVIDIA GeForce RTX 4090. The old windows-presentation-development/process.log describes Vulkan and must not be attributed to PID5032.

**APPROVED actual alpha composition for these D3D12 source-GUI clear pixels.** This establishes transparency inside the active windows, not merely outside a clipped region. It does not validate all materials or the next exported executable.

Correction retained: an earlier root corner sample returned magenta with WindowFromPoint resolving to the backdrop. That only established the clipped-out region and was insufficient alpha proof. Its initial PASS claim was withdrawn before this comparison.

## Packaged normal-launch confirmation

**APPROVED for executable SHA256 `7821c11b2236636efb3f14f4dbe3f882bc4bd543e2bd1fb12e9b280417288a3e`.** Independently queried Windows PID38100: production `native/build/MateCompanion.exe`, normal command line without a rendering-driver override. Exact root HWND2625496 (`Mate Companion`) and furniture HWND5048704 (`Mate object obj_1`) both have style `0x96080000`: no caption, resize frame, minimize or maximize bits.

Root region `(231,158)-(576,730)` was checked at local `(234,161)`, `(572,161)`, `(234,726)`, `(572,726)`. All four points were inside GetWindowRgn and WindowFromPoint resolved to the root; each returned the owned backdrop's exact RGB `(255,0,255)`. Furniture's guarded clear corner was owned by HWND5048704 and also returned exact magenta. Temporary backdrops were disposed; the pet was not moved or given input.

This confirms normal-launch packaged composition, including inside the active root region. It does not approve the separately reopened seated enter/exit animation work; later binaries need their own package identity attached to acceptance.
