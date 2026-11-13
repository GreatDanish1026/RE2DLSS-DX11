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

Next: a capture with TAA on, to find the TAA pass, its inputs (colour, depth, velocity, history),
the tonemap after it, and the jitter.
