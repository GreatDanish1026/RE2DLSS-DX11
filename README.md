# RE2DLSS-DX11 0.1.1

ReShade add-on for the **DirectX 11 version of Resident Evil 2** (the 2019 remake, Steam beta
branch `dx11_non-rt`, without ray tracing) that replaces the game's TAA with **NVIDIA DLSS**.
For the current DirectX 12 version of the game, use RE2DLSS instead.

- **DLAA**: at 100% render resolution, DLSS anti-aliases at native resolution.
- **Upscaling**: below 100%, DLSS upscales to your screen resolution, and the game's bloom,
  tonemapping (RenoDX HDR works), sharpening and HUD run at full resolution.
- **Render resolution dropdown**: Native (DLAA), Quality (67%), Balanced (58%), Performance (50%), or
  the game's own Image Quality slider. The bundled REFramework sets it.
- **DLSS model**: Automatic (K, M at Performance), or K, J, L or M.
- **F9** switches DLSS on and off, to compare with the game's TAA.

## Requirements

- Resident Evil 2 on the Steam beta branch **dx11_non-rt** (Properties > Betas), with DirectX 11
  selected and **TAA** anti-aliasing (the plain TAA option).
- An NVIDIA RTX graphics card.
- ReShade 6.8 or later **with add-on support**.

## Install

**With Fluffy Mod Manager**: put `RE2DLSS-DX11-0.1.1.zip` in Fluffy Mod Manager's `Games\RE2R\Mods`
folder (or drag it onto the manager) and enable it. **By hand**: copy the contents of the zip's
`RE2DLSS-DX11` folder into the game folder (where `re2.exe` is).

It installs:

- `RE2DLSS-DX11.addon64` (the add-on) and `nvngx_dlss.dll` (NVIDIA's DLSS 310.9.16).
- `dinput8.dll`: **REFramework**, the build for this version of the game (TDB66, from REFramework
  nightly 01366). It replaces any REFramework already in the folder: the 2022 TDB66 release doesn't
  start under ReShade on DirectX 11, and newer REFramework builds don't support this game version.
- `reframework\autorun\RE2DLSS-DX11.lua`: sets the render resolution chosen in the overlay.

## Settings

ReShade overlay (Home key), Add-ons tab, **RE2DLSS-DX11**; saved in `ReShade.ini` under
`[RE2DLSS-DX11]`.

- **Settings**: DLSS on/off (F9), render resolution, DLSS model.
- **Status**: what's running (render size, DLAA or upscaling), or why DLSS isn't.
- **Advanced**: upscaling below 100% (off: DLSS anti-aliases at the render resolution and the game
  stretches the result), the game's sharpening at full resolution, the game's exposure and effect
  mask for DLSS, and a frame capture tool for development.

## Notes

- Not supported: FSR, frame generation and Ray Reconstruction (this version of the game has no ray
  tracing).
- `RE2DLSS-DX11.log` next to `re2.exe` records what the add-on found and did.

## Licence

MIT (LICENSE). Third-party licences in `RE2DLSS-DX11-licenses` and THIRD_PARTY_NOTICES.txt.
