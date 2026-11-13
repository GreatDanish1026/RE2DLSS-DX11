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

Next: capture 2 at about 50% Image Quality with RenoDX off and DumpShaders set (TAA, tonemap,
psff2662f2, ps83760deb, bloom composite, compose, output, VS), to see how the render size is
upscaled in this build and to read the jitter and velocity conventions.
