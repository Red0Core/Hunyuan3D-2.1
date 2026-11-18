"""Run and validate Hunyuan3D 2.1 on Windows without a GUI."""

import argparse
import gc
import io
import json
import os
import sys
import tempfile
import time
from pathlib import Path

from hunyuan_models import ESRGAN_PATH, ROOT, download_models, model_directories

PAINT = ROOT / "hy3dpaint"
RASTERIZER = PAINT / "custom_rasterizer"
sys.path[:0] = [str(ROOT / "hy3dshape"), str(RASTERIZER), str(PAINT)]

PRESETS = {
    "draft": dict(max_num_view=6, resolution=512, render_size=1024, texture_size=2048, target_face_count=40000),
    "quality": dict(max_num_view=8, resolution=768, render_size=2048, texture_size=4096, target_face_count=100000),
}


def check_native() -> None:
    import numpy as np
    import torch
    import torchvision
    import custom_rasterizer_kernel
    from DifferentiableRenderer import mesh_inpaint_processor

    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch CUDA is unavailable")
    print(
        f"{sys.executable}\nPython {sys.version.split()[0]} | Torch {torch.__version__} | "
        f"torchvision {torchvision.__version__} | CUDA {torch.version.cuda} | "
        f"{torch.cuda.get_device_name()} | {torch.cuda.get_arch_list()}",
        flush=True,
    )
    vertices = torch.tensor(
        [[-0.75, -0.75, 0.0, 1.0], [0.75, -0.75, 0.0, 1.0], [0.0, 0.75, 0.0, 1.0]],
        device="cuda",
    )
    faces = torch.tensor([[0, 1, 2]], dtype=torch.int32, device="cuda")
    indices, barycentric = custom_rasterizer_kernel.rasterize_image(
        vertices, faces, torch.empty(0, device="cuda"), 32, 32, 1e-6, 0,
    )
    torch.cuda.synchronize()
    covered = int((indices == 1).sum())
    if covered == 0 or not torch.isfinite(barycentric[indices == 1]).all():
        raise RuntimeError("CUDA rasterization returned an invalid triangle")
    print(f"CUDA triangle: {covered} covered pixels | {custom_rasterizer_kernel.__file__}")

    texture = np.zeros((8, 8, 3), dtype=np.float32)
    texture[..., 0] = 0.5
    mask = np.full((8, 8), 255, dtype=np.uint8)
    positions = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], dtype=np.float32)
    uv = np.array([[0.2, 0.2], [0.8, 0.2], [0.2, 0.8]], dtype=np.float32)
    triangle = np.array([[0, 1, 2]], dtype=np.int32)
    result, result_mask = mesh_inpaint_processor.meshVerticeInpaint(texture, mask, positions, uv, triangle, triangle)
    if result.shape != texture.shape or result_mask.shape != mask.shape or not np.isfinite(result).all():
        raise RuntimeError("CPU inpainting returned an invalid texture")
    print(f"CPU inpainting: {result.shape} | {mesh_inpaint_processor.__file__}", flush=True)


def export_pbr(obj_path: Path, glb_path: Path) -> None:
    import trimesh
    from PIL import Image
    from convert_utils import combine_metallic_roughness

    mesh = trimesh.load(obj_path, force="mesh", process=False)
    if mesh.visual.kind != "texture" or mesh.visual.uv is None:
        raise RuntimeError("The textured OBJ has no UV coordinates")
    base = obj_path.with_suffix(".jpg")
    metallic = obj_path.with_name(obj_path.stem + "_metallic.jpg")
    roughness = obj_path.with_name(obj_path.stem + "_roughness.jpg")
    mr = obj_path.with_name("metallic_roughness.png")
    combine_metallic_roughness(metallic, roughness, mr)
    with Image.open(base) as base_image, Image.open(mr) as mr_image:
        mesh.visual.material = trimesh.visual.material.PBRMaterial(
            name="Hunyuan PBR",
            baseColorTexture=base_image.convert("RGB"),
            metallicRoughnessTexture=mr_image.convert("RGB"),
            metallicFactor=1.0,
            roughnessFactor=1.0,
        )
        mesh.export(glb_path)


def verify_glb(path: Path) -> dict:
    from PIL import Image, ImageStat
    from pygltflib import GLTF2

    model = GLTF2().load_binary(str(path))
    blob = model.binary_blob()
    primitives = [p for mesh in model.meshes for p in mesh.primitives]
    if not primitives or not blob:
        raise ValueError("GLB contains no geometry or binary payload")

    texture_info = {}
    triangles = 0
    for primitive in primitives:
        if primitive.attributes.POSITION is None or primitive.attributes.TEXCOORD_0 is None:
            raise ValueError("GLB primitive is missing positions or UVs")
        if primitive.material is None or primitive.indices is None:
            raise ValueError("GLB primitive is missing its material or indices")
        if primitive.mode not in (None, 4):
            raise ValueError("Expected glTF triangles")
        triangles += model.accessors[primitive.indices].count // 3
        material = model.materials[primitive.material].pbrMetallicRoughness
        if material is None:
            raise ValueError("GLB has no PBR material")
        for field in ("baseColorTexture", "metallicRoughnessTexture"):
            texture = getattr(material, field)
            if texture is None:
                raise ValueError(f"GLB material is missing {field}")
            image = model.images[model.textures[texture.index].source]
            if image.bufferView is None or image.uri:
                raise ValueError(f"{field} is not embedded in the GLB binary chunk")
            view = model.bufferViews[image.bufferView]
            start = view.byteOffset or 0
            if view.buffer != 0 or start + view.byteLength > len(blob):
                raise ValueError(f"Invalid buffer view for {field}")
            with Image.open(io.BytesIO(blob[start:start + view.byteLength])) as embedded:
                rgb = embedded.convert("RGB")
                texture_info[field] = {
                    "size": rgb.size,
                    "format": embedded.format,
                    "channel_stddev": [round(v, 2) for v in ImageStat.Stat(rgb).stddev],
                }
    if triangles <= 0:
        raise ValueError("GLB has no triangles")
    return {"glb": str(path), "bytes": path.stat().st_size, "triangles": triangles, "textures": texture_info}


def generate(image_path: Path, output_path: Path, preset: str, seed: int) -> dict:
    import torch
    from PIL import Image, ImageOps
    from torchvision_fix import apply_fix

    if output_path.exists():
        raise FileExistsError(output_path)
    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch CUDA is unavailable")
    apply_fix()

    from hy3dshape import FaceReducer, Hunyuan3DDiTFlowMatchingPipeline
    from hy3dshape.pipelines import export_to_trimesh
    from hy3dshape.rembg import BackgroundRemover
    from textureGenPipeline import Hunyuan3DPaintConfig, Hunyuan3DPaintPipeline

    started = time.perf_counter()
    hunyuan, dino = model_directories(download=False)
    if not ESRGAN_PATH.is_file():
        raise FileNotFoundError(f"{ESRGAN_PATH}. Run the models command first.")
    with Image.open(image_path) as source:
        image = ImageOps.exif_transpose(source).convert("RGBA")
    if image.getchannel("A").getextrema() == (255, 255):
        if not (Path(os.environ["U2NET_HOME"]) / "u2net.onnx").is_file():
            raise FileNotFoundError("u2net.onnx is missing. Run the models command first.")
        image = BackgroundRemover()(image.convert("RGB"))

    torch.backends.cudnn.benchmark = False
    torch.manual_seed(seed)
    torch.cuda.reset_peak_memory_stats()
    config = Hunyuan3DPaintConfig(**PRESETS[preset])
    config.multiview_cfg_path = str(PAINT / "cfgs" / "hunyuan-paint-pbr.yaml")
    config.multiview_pretrained_path = str(hunyuan / "hunyuan3d-paintpbr-v2-1")
    config.dino_ckpt_path = str(dino)
    config.realesrgan_ckpt_path = str(ESRGAN_PATH)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=".hunyuan-", dir=output_path.parent) as work:
        work = Path(work)
        print("Loading and running shape on CUDA", flush=True)
        shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(str(hunyuan))
        shape.enable_flashvdm()
        steps, octree = (25, 256) if preset == "draft" else (30, 384)
        output = shape(
            image=image, num_inference_steps=steps, guidance_scale=7.5, octree_resolution=octree,
            num_chunks=20000, generator=torch.Generator().manual_seed(seed), output_type="mesh",
        )
        mesh = export_to_trimesh(output)[0]
        del shape, output
        gc.collect()
        torch.cuda.empty_cache()
        shape_obj = work / "shape.obj"
        mesh = FaceReducer()(mesh, max_facenum=config.target_face_count)
        mesh.export(shape_obj)

        print("Loading and running texture pipeline on CUDA", flush=True)
        paint = Hunyuan3DPaintPipeline(config)
        textured_obj = work / "textured.obj"
        paint(mesh_path=str(shape_obj), image_path=image, output_mesh_path=str(textured_obj), save_glb=False)
        candidate = work / "textured.glb"
        export_pbr(textured_obj, candidate)
        result = verify_glb(candidate)
        candidate.replace(output_path)

    return {
        **result,
        "glb": str(output_path),
        "preset": preset,
        "seed": seed,
        "seconds": round(time.perf_counter() - started, 2),
        "peak_allocated_gib": round(torch.cuda.max_memory_allocated() / 2**30, 2),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="Exercise the CUDA and CPU extensions")
    models = commands.add_parser("models", help="Download the pinned model files")
    models.add_argument("--ranges", action="store_true", help="Resume large files using HTTP ranges")
    models.add_argument("--source-address", help="Local IP address for the range downloader")
    models.add_argument("--workers", type=int, choices=range(1, 49), default=16, metavar="1-48")
    run = commands.add_parser("generate", help="Generate a self-contained textured GLB")
    run.add_argument("image", type=Path)
    run.add_argument("output", type=Path)
    run.add_argument("--preset", choices=PRESETS, default="draft")
    run.add_argument("--seed", type=int, default=1234)
    verify = commands.add_parser("verify", help="Check geometry, UVs and embedded PBR maps")
    verify.add_argument("glb", type=Path)
    args = parser.parse_args()

    if args.command == "doctor":
        check_native()
    elif args.command == "models":
        if args.ranges:
            from filelock import FileLock
            from huggingface_hub.constants import HF_HUB_CACHE
            from hunyuan_model_ranges import restore_verified_blobs

            cache = Path(HF_HUB_CACHE)
            cache.mkdir(parents=True, exist_ok=True)
            with FileLock(cache / ".hunyuan-download.lock", timeout=0):
                restore_verified_blobs(workers=args.workers, source_address=args.source_address)
                download_models(args.source_address)
        else:
            download_models(args.source_address)
    elif args.command == "verify":
        print(json.dumps(verify_glb(args.glb.resolve(strict=True))))
    else:
        if args.output.suffix.lower() != ".glb":
            parser.error("The output path must end in .glb")
        print(json.dumps(generate(args.image.resolve(strict=True), args.output.resolve(), args.preset, args.seed)))


if __name__ == "__main__":
    main()
