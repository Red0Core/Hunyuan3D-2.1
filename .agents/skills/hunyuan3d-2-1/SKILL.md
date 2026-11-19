---
name: hunyuan3d-2-1
description: 'Image-to-model (image-to-3D) with local Hunyuan3D 2.1: turn a reference image into a static textured PBR GLB prop, verify it and preview or import it in Blender. Use for Hunyuan, Hunyan, or preparing image-derived props for Roblox film work.'
---

# Hunyuan3D 2.1 Image-to-Model

**Input:** one reference image. **Output:** a static 3D mesh with baked PBR textures in a GLB. Use it for props, furniture, set dressing, compact dioramas and distinctive silhouettes. For an animated project, use [Roblox animation guidance](references/roblox-animation.md) to decide when a generated prop fits and how to hand it off.

## Reference first

For a new object, start by generating the reference image with ImageGen. Use one coherent object, a readable three-quarter angle, an unclipped silhouette, distinct material regions and real transparency. A compact scene should share a single base if you intend it to be treated as one asset. Preserve the original PNG and its alpha, inspect it, then pass that file to Hunyuan. When the user explicitly asks to reconstruct a supplied image as-is, use the supplied image. The CLI uses U²-Net for fully opaque images.

## Generate with the Windows cu132 profile

On the configured Windows host, use `D:\Hunyuan3D-2.1-cu132` with uv, Python 3.13.18, Torch 2.15.0+cu132 and the compiled cp313 extensions. Use the existing weights in `D:\huggingface`. See [Windows recovery](references/windows-recovery.md) for setup, repairs and downloads.

Tencent's [Code Usage](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1#code-usage) describes shape generation with `Hunyuan3DDiTFlowMatchingPipeline` followed by texturing with `Hunyuan3DPaintPipeline` using the mesh and reference. The upstream example uses six paint views at resolution 512. The Windows CLI wraps those stages and packs the PBR GLB.

```powershell
Set-Location -LiteralPath 'D:\Hunyuan3D-2.1-cu132'
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
$env:UV_OFFLINE = '1'
.\run-windows.ps1 generate 'D:\path\reference.png' 'D:\path\prop.glb' --preset quality --seed 1234
if ($LASTEXITCODE) { throw 'Hunyuan generation failed' }
.\run-windows.ps1 verify 'D:\path\prop.glb'
```

Use `draft` for iteration and `quality` for visible hero props with GPU headroom. Give each export a unique path. Keep the input and raw GLB with the project deliverables or in the checkout's `outputs` when no project path was specified. Report the measured time and settings when comparing outputs. The same seed across Torch builds can produce different starting noise, so record the profile as well as the seed.

## Verify the asset

Verify triangles, UVs and decodable `baseColorTexture` and `metallicRoughnessTexture`. For a shot-ready result, inspect the imported mesh with materials and from the intended front and rear or side. Use a neutral material when you need to tell actual geometry from baked detail. Inspect floating fragments with position-welded connectivity and remove only confirmed strays from a working copy. Preserve UVs and material links, retain the raw GLB and verify the cleaned GLB again.

For a requested live Blender import, use the connected Blender tools when available. Read the current scene, import into an isolated collection or scene and verify material display and framing. A glTF import only verifies what was exercised in Blender. Follow the destination workflow for scale, pivot, engine import, collision and animation.
