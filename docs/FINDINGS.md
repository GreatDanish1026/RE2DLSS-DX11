# RE2DLSS-DX11 findings

Resident Evil 2, Steam beta branch `dx11_non-rt` (build 11055033), DirectX 11
(`re2_config.ini`: `TargetPlatform=DirectX11`, `PCDXver=DirectX11`).

Goal: DLSS (and FSR) in place of the game's TAA, as RE2DLSS does for the DirectX 12 build. No
frame generation, no Ray Reconstruction (this build has no ray tracing).

## 0.0.1 probe

`src/main.cpp` is the frame capture tool rewritten for D3D11: bindings are tracked per device
context and shader stage at all times (D3D11 state persists), deferred contexts' work is moved
into the stream of the context that executes it (FinishCommandList / ExecuteCommandList both
arrive as execute_secondary_command_list), and constant buffers are dumped from the CPU's last
write (Map/Unmap, UpdateSubresource) for shaders in `DumpShaders`.

## Capture 1 (2026-11-13: 3840x2160, Image Quality 100%, RenoDX was on)

Everything runs on the immediate context (no deferred command lists). 766 passes a frame.
The post chain matches the DX12 build's (RE2DLSS docs/FINDINGS.md), with new shader ids:

| Pass | Shader | Reads | Writes |
|---|---|---|---|
| colour compose | psa5e9b7ef -> ps452c608a | t0 depth, t1 colour | #9059e rgba16f + r8 mask #bf67a |
| (4 draws: transparent/particles into #9059e) | | | |
| **TAA** | **psddfad309** (vs3f48df32) | **t0 r8 mask, t1 depth r32g8x24, t2 colour #9059e, t3 history #be88e, t4 velocity rgba16snorm #be862**; b0 SceneInfo (512 bytes), b1 256 bytes | **#be9ee rgba16f** |
| history copy | copy | #be9ee | #be88e |
| bloom down/up | pseb1e43cf, psf76db36a x5, ps60951143 .. psba7dcf1c | #be9ee | 1920x1080 .. 30x16 |
| bloom composite | ps629a5b35 | t0 bloom 1920x1080 | into #be9ee |
| **tonemap** | **ps81003188** (vs3f48df32; b0 SceneInfo .. b9, 32^3 LUTs) | **t0 #be9ee** | #9059e |
| ? (same b1 as TAA) | psff2662f2 | t0 #9059e, b0 SceneInfo | #be9ee |
| copy back | ps83760deb | t0 #be9ee | #9059e |
| HUD | ps5c43bdb5 (5-index quads) | | #9059e |
| output | psb106fe94 | t0 #9059e | back buffer 3840x2160 rgb10a2 |

Same TAA registers as the DX12 build (t0 mask, t1 depth, t2 colour, t3 history, t4 velocity).
No motion blur pass in this capture (motion blur is likely off in these settings).

## Capture 2 (2026-11-13: Image Quality 50%, 1920x1080 -> 3840x2160, RenoDX off, game HDR on)

`docs/captures/RE2DLSS-DX11-frame-2-50pct.txt`, bytecode + `fxc /dumpbin` in `docs/shaders`.
Without RenoDX the scene targets are r11g11b10f (RenoDX upgrades them to rgba16f); shader ids are
the same either way.

Everything up to the sharpening runs at render size; one pass then stretches to output size:

| Pass | Shader (entry names from RDEF) | Reads | Writes |
|---|---|---|---|
| **TAA** | **psddfad309** = PreTonemap2_PS | t0 EffectMaskTex, t1 ReadonlyDepth, t2 HDRImage, t3 PrevHDRImage, t4 Velocity; cb0 SceneInfo, cb1 Tonemap (AABlend, ResponsiveAARate, preTonemapRange) | render size |
| bloom + composite | pseb1e43cf .. ps629a5b35 | TAA output | into TAA output |
| **tonemap** | **ps81003188** | t0 | render size |
| **sharpen** | **psff2662f2** (5-tap, Tonemap.sharpness) | t0 tonemapped | render size |
| **stretch** | **psaff99b25** (vsa60b7c3f) | t0 depth, t1 sharpened, SceneInfo | **output size** colour + d32f depth |
| (at 100%: plain copy) | ps83760deb (`ld` by pixel) | | |
| HUD | ps5c43bdb5 | | output size |
| output | psb106fe94 (HDRMapping: PQ encode) | | back buffer rgb10a2 |

TAA maths identical to the DX12 build's PreTonemap2_PS: colour x Exposure (VS output: WhitePtSrv x
exposureAdjustment), unjittered by `projElement[0].zw * screenInverseSize * 0.5`, prevUV = uv +
(v.x * 0.5, -v.y * 0.5), output divided by Exposure again.

SceneInfo (cb0, 512 bytes here, 528 in the DX12 build) has the DX12 layout at the offsets
RE2DLSS uses: projElement[0] at byte 160 (x scale, y scale, **jitter x, y in clip space**), screenSize
at 368 (1920 1080 = render size), cameraNearPlane at 392. Jitter in this frame: -0.000228, 0.000360
clip = 0.22, 0.19 render pixels.

So RE2DLSS's design applies: DLSS in place of PreTonemap2_PS writing an output-size image, the
bloom composite, tonemap and sharpening redirected to output size, the stretch replaced by a copy.
psaff99b25 also writes a 4K depth (for the HUD?), to check from its bytecode (added to DumpShaders).

## 0.1.0 test (2026-11-13, user: "looked a lot better")

RenoDX off, game HDR on, 4K. Log: NGX D3D11 started (the NVIDIA app's driver override loaded
DLSS 310.9.16), DLSS ran at every Image Quality step from 50% to 100% with no errors: 1920x1080
(preset M), 2304x1296, 2688x1512, 3072x1728, 3456x1944 (preset K) -> 3840x2160, and DLAA at
3840x2160. Tonemapped and sharpened 4K textures were created in the game's format (r11g11b10f).

The stretch psaff99b25 (docs/shaders) is bilinear colour (t1) + depth (t0) to SV_Depth, UV =
pixel x SceneInfo.screenInverseSize: running it and then drawing our image over its colour is right.

## 0.1.0 (DLSS)

`src/upscaler.cpp`, `src/dlss.cpp`: RE2DLSS's design on D3D11.

- DLSS through NGX's D3D11 interface, run inside a clean `ID3DDeviceContextState` swapped in and
  out (`SwapDeviceContextState`), so NGX's bindings never touch the game's. The add-on's own copies
  (blit.hlsl, with format conversion) run the same way.
- DLAA (100%): DLSS -> X (rgba16f), drawn into the TAA target; the TAA draw is skipped.
- Upscaling: DLSS -> X at output size; the game's bloom composite, tonemap and sharpening draws
  are redirected in place (render target, viewport, scissor, t0, b0 = SceneInfo copy with the
  output size) and the game's bindings are put back before its next GPU call (D3D11 state
  persists and the game may not set it again); the stretch draw runs, then Y/Z is drawn over its
  colour.
- SceneInfo comes from the CPU's last write to the 512-byte constant buffer bound as b0.

## 0.1.0 with RenoDX (2026-11-13)

RenoDX on: the scene targets are rgba16f (format 10) and the tonemapped/sharpened 4K textures are
created rgba16f to match. DLSS ran at every Image Quality step (model K, the user's choice) and
DLAA with no errors; the redirected tonemap is the game's own draw, so RenoDX's tonemap applies.

## 0.1.1 render resolution dropdown (2026-11-13, works)

Needs REFramework's TDB66 build. The June 2022 release failed to start on D3D11 under ReShade
("Failed to initialize REFramework on DirectX 11"); **nightly 01366** (`RE2_TDB66.zip`, the last
nightly with per-game TDB builds; later nightlies are one REFramework.zip without TDB66) starts.
RE2DLSS-DX11.lua sets via.render.RenderConfig.ImageQualityRate as in the DX12 build. Log: Native
(DLAA 3840x2160), Quality 2561x1440, Balanced 2227x1252, Performance 1920x1080, back to Native,
each applied within a fraction of a second. The game's post chain format changes with the scale
(r11g11b10f at 67% and 58%, rgba16f at 50%); the 4K textures are recreated to match.

## 0.2.0 (untested): FSR, sharpening, sharper textures

- **FSR 3.1 / 4** (`src/bridge.cpp`): AMD's runtime is Direct3D 12 only. The add-on makes a D3D12
  device on the game's adapter and shares textures (D3D12_HEAP_FLAG_SHARED, opened with
  OpenSharedResource1) and a fence (OpenSharedFence) with D3D11. Per frame: D3D11 copies colour,
  motion and the effect mask into the shared textures and draws the depth (r32f_x8x24 SRV) into a
  shared r32f render target (a depth-stencil texture can't be copied into a plain one), signals,
  flushes; D3D12 waits, runs fsr.cpp (unchanged from the D3D12 add-ons), signals; D3D11 waits on the
  GPU and copies the output into X. Everything after is the DLSS path.
- **Sharpening**: RCAS (rcas.hlsl, cs_5_0) after DLSS, in the clean context state; FSR's own RCAS.
- **Sharper textures**: D3D11 samplers can't be rewritten, so after each PSSetSamplers the game's
  material samplers (anisotropic/trilinear, wrap, with mips) are rebound as copies with
  mip bias log2(render scale), made once per bias; follows the render scale live.

## 0.2.0 test (2026-11-13)

- FSR through the bridge works once the shared textures are made by D3D11 (MISC_SHARED |
  SHARED_NTHANDLE, opened with ID3D12Device::OpenSharedHandle); D3D12-made shared textures opened by
  D3D11 failed with E_INVALIDARG. FSR 3.1.6 (RTX 5080) ran at 50%, 100% (native AA) and 67%.
- The game binds an 8x8 placeholder (format 72) as the velocity on the first frame and the first
  after a menu: those frames are left to the game's TAA now.
- Mip bias -1.00 at 50%, -0.58 at 67%, 0 at 100%; 5 material samplers. It drops to 0 while the
  upscaler doesn't run (menus) and comes back after.
- RCAS after DLSS ran.

## Fixes after the 0.2.0 test (2026-11-13)

- **Lights dimming below DLAA**: DLSS was told exposure 1.0; the TAA's colour is multiplied by
  Exposure = WhitePtSrv[0] x exposureAdjustment (~0.05). exposure.hlsl computes it on the GPU from
  the TAA's own inputs (VS t0, PS b1) for DLSS's exposure texture. User: better.
- **Bloom fading toward Performance**: the bloom chain read the game's render-size TAA output,
  which keeps less of small bright lights than DLSS. Now DLSS's 4K image is scaled down
  (downsample.hlsl, 2x2 bilinear taps per pixel) into the TAA target and the game's TAA is skipped.
- **Leon see-through until the bias changed**: a new sampler reusing a released sampler's address
  kept the old biased copy. OnInitSampler now drops whatever was recorded for that handle.
