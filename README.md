# Hunyuan3D 2.1 Image-to-Model on Windows

Turn a reference image into a static 3D mesh and export a self-contained PBR GLB. This profile uses uv, Python 3.13 and PyTorch CUDA 13.2. It was tested on Windows 11 with a 16 GB RTX 5070 Ti.

## Quick start

Use Windows x64, Git, uv, Visual Studio Community 2026 with **Desktop development with C++** and a Windows SDK, and an NVIDIA driver that supports CUDA 13.2.

```powershell
git clone https://github.com/Red0Core/Hunyuan3D-2.1.git
cd Hunyuan3D-2.1
uv python install 3.13.18
.\setup-windows.ps1
uv run --locked --no-sync python hunyuan_cli.py models --ranges
```

The setup script syncs `uv.lock`, prepares the pinned CUDA 13.2.2 and MSVC 19.50 toolchain in the checkout, builds both native extensions and runs `doctor`. To reuse a prepared local environment and cached tools, run `.\setup-windows.ps1 -Offline`. For drive placement and optional TUN routing, see the [Windows guide](WINDOWS_CU132.md).

## Generate and verify a model

```powershell
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
uv run --locked --no-sync python hunyuan_cli.py generate 'D:\assets\reference.png' 'outputs\prop.glb' --preset quality --seed 1234
uv run --locked --no-sync python hunyuan_cli.py verify 'outputs\prop.glb'
```

Start with a centered, unclipped reference in three-quarter view. A PNG with clean transparency avoids background removal. Use `draft` to iterate and `quality` for small features. The GLB includes base color and metallic/roughness maps. Inspect it in Blender from the intended viewing angles, including the side and back when they matter.

## Upstream and Codex skill

This Windows adaptation builds on the [Windows fork](https://github.com/official-imvoiid/Hunyuan3D-2.1) of [Tencent Hunyuan3D 2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1). It retains sequential shape and paint stages, sliced VAE decoding and Windows rasterizer fixes. Tencent's [Code Usage](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1#code-usage) explains the two stages: generate the mesh with `Hunyuan3DDiTFlowMatchingPipeline`, then supply the mesh and image to `Hunyuan3DPaintPipeline`.

The [Image-to-Model skill](.agents/skills/hunyuan3d-2-1/SKILL.md) covers reference preparation and visual checks. See [Roblox animation uses](.agents/skills/hunyuan3d-2-1/references/roblox-animation.md) for static props and shot handoff.

Tencent's [license](LICENSE) and [notices](Notice.txt) apply. The agreement restricts use and redistribution to its defined territory, which excludes the European Union, the United Kingdom and South Korea. Review the terms before using or redistributing the code or generated assets.
