# Hunyuan3D-2.1 — Windows / 16 GB VRAM Fork

Image → 3D model, running locally on Windows. This is a fork of
[Tencent-Hunyuan/Hunyuan3D-2.1](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1)
with Windows build fixes and memory/speed work so it fits on a **16 GB** card.

Upstream states it needs **29 GB VRAM** for shape + texture. This fork runs the
full pipeline in **~11 GB**, or ~15 GB on the high-quality preset.

Powered by Tencent Hunyuan.

---

## ⚠️ Read this first — what it is good at

**This model makes OBJECTS, not characters.**

That is not a limitation of this fork — it is what the model was trained on.
Tencent's own documentation says it targets:

> gaming assets, e-commerce products, and general 3D object creation
> **rather than character or humanoid generation**

Its training data is object datasets: Objaverse-XL, ShapeNet, ModelNet40, Thingi10K.
There is no character or anime dataset in there.

| Works well | Works badly |
|---|---|
| Props — sword, cup, chair, lamp, bag | Anime / game characters |
| Furniture, food, tools, machines | Faces (a full-body render gives the face ~61 px) |
| Clothing pieces — skirt, jacket, hood | Anything needing a skeleton |
| Photo of a real object → 3D | Separate hair / skin / cloth materials |
| Game background assets in bulk | Exact replication of a 2D drawing |

**No setting fixes the character case.** There is no rigging, no bones, and the
whole model is one mesh with one baked texture. If you want an anime character,
use [VRoid Studio](https://vroid.com/en/studio) (free, rigged, correct materials)
and use this for the props they hold.

---

## What is different from upstream

**Windows fixes**
- `int64` types in the CUDA kernel (`long` is 32-bit on MSVC)
- torch imported before the kernel, so the DLLs load in the right order
- a Windows kernel source directory
- `DifferentiableRenderer/setup.py`, replacing `compile_mesh_painter.sh`
  (that script calls `c++` and `python3-config`, which do not exist on Windows)
- `u2net` path pinned to the repo folder so it travels with the project
- HuggingFace cache resolution, with a fall back to cache when offline

**Fits 16 GB, and faster**
- only one model on the GPU at a time (shape / paint / multiview swap out)
- VAE decoding split into slices — **36 s → 0.6 s**, the single biggest win.
  Decoding 12 views at once overflowed VRAM and Windows silently paged to
  system RAM.
- dropped a redundant classifier-free-guidance branch; identical output, one
  third less UNet work
- fixed a texture bake loop that redid all previous views on every iteration
- cuDNN autotune left **off** — it cost 26 s on the first generation and gave
  nothing back

**Features**
- `MultiView` tab — optional front / back / left / right reference images
- mesh detail before texturing is adjustable (upstream locked it at 40 000 faces)
- one-shot setup, build and launch scripts

---

## Requirements

| | |
|---|---|
| OS | Windows 10 / 11 x64 |
| GPU | NVIDIA, 16 GB VRAM. Built for RTX 50-series (`sm_120`); RTX 20/30/40 also work |
| Driver | CUDA 12.8 capable — check with `nvidia-smi` |
| Python | 3.11 exactly (the shipped `.pyd` files are `cp311`) |
| Disk | ~45 GB (≈25 GB install, ≈20 GB models) |
| Build tools | [Visual Studio Build Tools 2022](https://visualstudio.microsoft.com/downloads/), "Desktop development with C++" |
| CUDA Toolkit | 12.8, must match your torch build |

Only needed if you compile the extensions yourself — see step 3.

---

## Installation

```bash
git clone https://github.com/official-imvoiid/Hunyuan3D-2.1
```

If the clone fails on long filenames:

```bash
git config --global core.longpaths true
```

### 1. Environment

```bash
Setup.bat
```

Downloads portable Miniconda into `installer_files\`, pins conda's env and
package folders to this directory, and creates a Python 3.11 environment. Nothing
is installed system-wide. Safe to re-run — finished steps are skipped.

### 2. AI models (~22 GB)

```bash
GetHFModels.bat
```

| Repo | Size | |
|---|---|---|
| `tencent/Hunyuan3D-2.1` | ~13 GB | required |
| `facebook/dinov2-giant` | ~4.2 GB | required |
| `tencent/Hunyuan3D-2mv` | ~4.6 GB | asks — only for the MultiView tab |

Set `HF_HOME` first if you want them on another drive:

```bash
setx HF_HOME "D:\huggingface"
```

### 3. Python packages and native extensions

```bash
Build.bat
```

Detects your toolchain and sets it up **for that window only** — your permanent
PATH is never modified. It looks for **system** tools first and offers the conda
copies only if a system one is missing.

```
python    OK    [conda env]
MSVC C++  OK    [system] ...\2022\BuildTools
nvcc      OK    [system] ...\CUDA\v12.8
GPU       NVIDIA GeForce RTX 5070 Ti  (sm_120)
torch     will install cu128 build (covers RTX 20/30/40/50)
```

Then pick **6** to run everything in order:

```
1  Install PyTorch  (GPU build - DO THIS FIRST)
2  Install requirements.txt
3  Install deepspeed
4  Build custom_rasterizer      (needs MSVC + CUDA)
5  Build DifferentiableRenderer (needs MSVC only)
6  Do 1-5 in order
7  Open a shell with this build environment
```

PyTorch is step 1 on purpose: `requirements.txt` has no `torch` line, so pip
would otherwise pull the **CPU** build in as a dependency of `torchmetrics` and
your GPU would never be used. The script verifies `torch.cuda.is_available()`
after installing and warns if it is False.

The GPU architecture is read from the driver, so nothing needs editing for a
different card.

### 4. Two remaining model files

```bash
GetRM_Models.bat
```

`u2net.onnx` (168 MB) and `RealESRGAN_x4plus.pth` (64 MB) — both too large for
GitHub. Verified by MD5, safe to re-run.

### 5. Run

```bash
StartHunyuan3D.bat
```

Open **http://localhost:8080**.

First start takes **2–4 minutes** and is silent for most of it while the 6.9 GB
shape model loads. Wait for `Application startup complete`.

---

## Using it

**Image Prompt** — one image. Uses `Hunyuan3D-2.1`. Best single-image geometry.

**MultiView Prompt** — front / back / left / right, any combination. Uploading
*any* view here switches to `Hunyuan3D-2mv` automatically; leave all four empty
and it stays on 2.1. Texturing uses 2.1 either way.

Multiview pins the back and sides the single-image model has to invent. The
trade-off: 2mv is a 2.0-generation shape model, so per-view surface detail is
slightly below 2.1.

Tip: turn **Randomize seed** off while comparing settings, or you are changing
two things at once.

---

## Settings

Two kinds. Sliders change per generation; flags need a restart.

### In the app — no restart

`Inference Steps` · `Octree Resolution` · `Guidance Scale` · `Number of Chunks` ·
`Seed` · `Remove Background`

### In `StartHunyuan3D.bat` — restart required

| Flag | Default | What it does |
|---|---|---|
| `--view_resolution` | 768 | texture detail. **768 is the maximum a 16 GB card can do** — 1024 does not OOM, it thrashes and never finishes |
| `--max_num_view` | 8 | number of camera views |
| `--texture_size` | 4096 | texture image size |
| `--render_size` | 2048 | render size used for baking |
| `--max_face_num` | 100000 | mesh detail before texturing (upstream: 40000) |
| `--low_vram_mode` | on | one model on the GPU at a time — required at 16 GB |
| `--enable_flashvdm` | on | faster shape decoding |

A ~65 s draft preset is written as comments inside the file.

Do not raise `--max_face_num` to 200000 — it costs another 48 s in UV unwrap
alone for almost no visible gain.

**Careful:** "Target Face Number" in the Export tab is **not** `--max_face_num`.
It only applies with "Simplify Mesh" ticked and does nothing for texture quality.

### Environment switches

| | |
|---|---|
| `HY3D_PROFILE=1` | per-phase time and VRAM breakdown in the console |
| `HY3D_FAST_CFG=0` | restore the original 3-branch texture guidance |

---

## Performance

Measured on an RTX 5070 Ti (16 GB), one textured model:

| Preset | Time | Peak VRAM |
|---|---|---|
| Draft (6 views @ 512, 2048 texture, 40k faces) | 64–67 s | 10.8 GB |
| Default (8 views @ 768, 4096 texture, 100k faces) | ~164 s | 15.0 GB |
| MultiView | ~197 s | 15.3 GB |

Upstream, unmodified, requires 29 GB and will not run at all.

---

## Rebuilding on another PC

The `.pyd` files in this repo are **Python 3.11 / Windows x64 only**. On any
other Python version they will not load and must be rebuilt:

```bash
Build.bat
```

Pick 4 and 5. The CUDA architecture comes from `nvidia-smi`, so no editing is
needed for a different GPU — just install the CUDA Toolkit matching your torch:

```bash
python -c "import torch; print(torch.version.cuda)"
```

---

## Troubleshooting

**`Filename too long` on clone**
`git config --global core.longpaths true`

**`InPaint Function CAN NOT BE Imported!!!`**
`mesh_inpaint_processor.cp311-win_amd64.pyd` must sit next to `MeshRender.py`
inside `hy3dpaint\DifferentiableRenderer\`, not in site-packages — it is imported
relatively.

**Out of memory**
Lower `--view_resolution 512` and `--texture_size 2048`.

**`Python script failed to run.` with no traceback above it**
It was interrupted, not broken. Startup is silent for 2–4 minutes.

**`Too little data for declared Content-Length` in the console**
Harmless. A Gradio preview race when several images are dropped in quickly; the
image reloads itself. Already suppressed.

**deepspeed fails to build**
Only used for training — `gradio_app.py` never imports it, so generation works
without it. `_dsbuild.py` works around an upstream packaging bug: deepspeed's
`setup.py` requires `bin/deepspeed.bat` on Windows, but its sdist ships no `.bat`
files at all.

**The face looks blurry**
That is the limit, not a bug. On a full-body subject the face gets about 61 px at
`--view_resolution 768`, and 1024 does not fit in 16 GB. Paint it by hand in
`save_dir\<id>\textured_mesh.jpg` instead — it maps straight back onto the mesh.

---

## License

Licensed under the **Tencent Hunyuan 3D 2.1 Community License Agreement**.
See [LICENSE](LICENSE) and [Notice.txt](Notice.txt).

Tencent Hunyuan 3D 2.1 is licensed under the Tencent Hunyuan 3D 2.1 Community
License Agreement, Copyright © 2025 Tencent. All Rights Reserved. The trademark
rights of "Tencent Hunyuan" are owned by Tencent or its affiliate.

**Not available in the European Union, the United Kingdom, or South Korea** —
the licence excludes those territories.

Modified files carry a notice of the change, as the licence requires. Tencent is
not affiliated with, and does not endorse, this fork.
