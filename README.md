# Hunyuan3D 2.1 Image-to-Model on Windows

Turn a reference image into a static 3D mesh and export a textured PBR GLB from the command line. This checkout uses uv, Python 3.13 and PyTorch CUDA 13.2. The Windows low-VRAM pipeline has been tested on a 16 GB RTX 5070 Ti (`sm_120`).

Built on the [Windows fork](https://github.com/official-imvoiid/Hunyuan3D-2.1) of [Tencent Hunyuan3D 2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1). It retains the fork's sequential shape and paint stages, sliced VAE decoding and Windows rasterizer fixes. The local CLI packs base color and metallic/roughness textures directly in the GLB.

## Setup on Windows

Use Windows x64, uv, Python 3.13.18, Visual Studio Community 2026 with the C++ workload and Windows SDK, and an NVIDIA driver that runs PyTorch cu132. On the tested machine, MSVC 19.50 works with the local CUDA Toolkit 13.2.2. The setup stages this toolset inside the checkout.

```powershell
.\stage-cu132.ps1
.\stage-cu132.ps1 -Download
.\build-cu132.cmd
.\run-windows.ps1 doctor
```

The first command previews setup. The download command checks the active sing-box TUN route and syncs `uv.lock`. See the [Windows guide](WINDOWS_CU132.md) for the toolchain, cache and model prefetch commands.

## Generate a textured model

```powershell
$env:UV_OFFLINE = '1'
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
.\run-windows.ps1 generate 'D:\assets\reference.png' 'outputs\prop.glb' --preset quality --seed 1234
.\run-windows.ps1 verify 'outputs\prop.glb'
```

Prefetch the weights once before using offline mode. Start with a centered image of the full object in three-quarter view. A PNG with a clean transparent background avoids background removal. Use `draft` for iteration and `quality` to preserve more detail. Open the resulting GLB in Blender to inspect the silhouette, texture placement and inferred back.

Tencent documents the same two-stage workflow in [Code Usage](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1#code-usage): `Hunyuan3DDiTFlowMatchingPipeline` builds the shape and `Hunyuan3DPaintPipeline` takes the mesh and reference image to synthesize its texture. Its example paint config uses six views and resolution 512. This checkout has its own locked Windows setup and command-line presets.

## Codex skill

The [Hunyuan Image-to-Model skill](.agents/skills/hunyuan3d-2-1/SKILL.md) explains input preparation, PBR validation and where the workflow fits into [Roblox animation](.agents/skills/hunyuan3d-2-1/references/roblox-animation.md).

Tencent's [license](LICENSE) and [notices](Notice.txt) apply. Refer to the [current upstream agreement](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/blob/main/LICENSE) for terms on sharing software and generated output.
