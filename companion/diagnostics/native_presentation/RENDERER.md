# Native alpha presentation: Vulkan / D3D12 — 2026-09-06

## What the failing evidence actually establishes

The furniture Window produces an RGBA viewport image with zero-alpha clear
pixels, but the corresponding native desktop pixels appear black. The first
apparent root-window success was **not valid alpha evidence**: Mate's root uses
`mouse_passthrough_polygon`, and Godot's Windows implementation applies a native
window region. A point outside that region exposes the backdrop even when the
swapchain itself is opaque. `WindowFromPoint` returning the backdrop there does
not distinguish clipping from alpha composition.

The independent native check was therefore tightened to sample a clear pixel
**inside the actual Win32 region**, over an owned, known-color backdrop. The
root agent and face reviewer report that these root pixels are black too. The
working diagnosis is a Vulkan native-presentation failure affecting root and
furniture windows, not a subwindow-only missing flag. The exact driver/compositor
fault is not established by these observations. Viewport PNG alpha, native region
clipping, and final desktop alpha composition are separate checks.

## Godot 4.5.2 source findings

The inspected source is pinned to `4.5.2-stable`, matching the executable version.

* `create_sub_window()` already calls `DwmEnableBlurBehindWindow` for a transparent
  window before `RenderingDevice::screen_create()`. Toggling the transparent flag
  after `show()` repeats essentially that same DWM operation. Both paths use
  `OS::is_layered_allowed()`; the source does not reveal an omitted subwindow-only
  per-pixel-alpha setup. [Windows display server, lines 1609–1680](https://github.com/godotengine/godot/blob/4.5.2-stable/platform/windows/display_server_windows.cpp#L1609),
  [transparent flag handler, lines 2641–2667](https://github.com/godotengine/godot/blob/4.5.2-stable/platform/windows/display_server_windows.cpp#L2641).
* Vulkan chooses a supported composite-alpha mode in the order premultiplied,
  postmultiplied, inherited, opaque when per-pixel transparency is allowed.
  This is shared by root and additional windows. No source observation proves
  which mode this machine's driver actually returned; do not label `INHERIT` as
  a measured cause. VSync chooses a presentation mode independently, so a VSync
  change could exercise another driver path but is not a demonstrated alpha fix.
  [Vulkan swapchain selection, lines 3245–3295](https://github.com/godotengine/godot/blob/4.5.2-stable/drivers/vulkan/rendering_device_driver_vulkan.cpp#L3245).
* D3D12 provides a materially different native path: with transparency allowed it
  requests `DXGI_ALPHA_MODE_PREMULTIPLIED`, and a `DCOMP_ENABLED` build creates a
  composition swapchain and attaches it through `DCompositionCreateDevice`,
  `CreateTargetForHwnd`, `SetContent` and `Commit`.
  [D3D12 swapchain and composition, lines 2820–2875](https://github.com/godotengine/godot/blob/4.5.2-stable/drivers/d3d12/rendering_device_driver_d3d12.cpp#L2820).

The official issue tracker contains a closely matching Windows 11 / NVIDIA /
Godot 4.5 Vulkan report where switching to D3D12 restores transparency. This is
supporting precedent, not proof that our machine has the identical underlying
bug. That report also mentions a click-through difference, so input routing must
be included in the native A/B check. [Godot issue #111513](https://github.com/godotengine/godot/issues/111513).

## Minimal process-local A/B

Keep Forward+ and launch the owned test executable with:

```text
MateCompanion.exe --rendering-method forward_plus --rendering-driver d3d12
```

This changes the graphics driver, while retaining the RenderingDevice/Forward+
renderer used by the avatar materials. It does not select Compatibility or
change global NVIDIA settings. Godot documents both Vulkan and D3D12 as drivers
for the same Forward+ renderer. Actual MToon shader compilation, lighting,
outline appearance and antialiasing still require visual verification.
[Godot 4.5 renderer architecture](https://docs.godotengine.org/en/4.5/tutorials/rendering/renderers.html).

Feasibility inspection found `DCompositionCreateDevice` and `D3D12GetInterface`
symbols in both the installed Windows Godot executable and the current exported
Mate executable. System `D3D12.dll`, `D3D12Core.dll` and `dcomp.dll` are present.
Godot's source supports the system D3D12 loader when an app-local Agility SDK is
unavailable; its shader path includes the built-in SPIR-V/NIR/DXIL conversion.
Absence of an app-local `dxcompiler.dll` alone does not establish a missing
dependency. The actual launch log is authoritative for selected driver and GPU.
[D3D12 loader](https://github.com/godotengine/godot/blob/4.5.2-stable/drivers/d3d12/rendering_context_driver_d3d12.cpp#L102),
[shader conversion includes](https://github.com/godotengine/godot/blob/4.5.2-stable/drivers/d3d12/rendering_device_driver_d3d12.cpp#L60).

The renderer switch is accepted only after native pixels inside the window
region show the owned backdrop through transparent areas, visible furniture and
avatar pixels remain rendered, and object/root input routing still works. The
root agent owns that A/B execution and its final acceptance record. No engine
binary patch or runtime source change was made by this source investigation.
