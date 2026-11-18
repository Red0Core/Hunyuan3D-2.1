"""Resume downloads of the pinned Hugging Face weights using verified HTTP ranges."""

import concurrent.futures
import hashlib
import shutil
import time
import urllib.request
from pathlib import Path

from huggingface_hub.constants import HF_HUB_CACHE

from hunyuan_models import DINO, DINO_REVISION, HUNYUAN, HUNYUAN_REVISION, download_opener

CHUNK_BYTES = 32 * 1024 * 1024
WEIGHTS = (
    (HUNYUAN, HUNYUAN_REVISION, "hunyuan3d-dit-v2-1/model.fp16.ckpt",
     7366389768, "6b519fc7242f78e9b5f47ea4d55668fe3d944a2d27332f4ca68d29a6ff603f5e"),
    (HUNYUAN, HUNYUAN_REVISION, "hunyuan3d-paintpbr-v2-1/unet/diffusion_pytorch_model.bin",
     3925293863, "675a1b5cd0098b2002637c443946529c03c5cd54427f40245263350feb3dd5b8"),
    (HUNYUAN, HUNYUAN_REVISION, "hunyuan3d-paintpbr-v2-1/text_encoder/pytorch_model.bin",
     1361671895, "c3e254d7b61353497ea0be2c4013df4ea8f739ee88cffa0ba58cd085459ed565"),
    (HUNYUAN, HUNYUAN_REVISION, "hunyuan3d-paintpbr-v2-1/vae/diffusion_pytorch_model.bin",
     334707217, "1b4889b6b1d4ce7ae320a02dedaeff1780ad77d415ea0d744b476155c6377ddc"),
    (HUNYUAN, HUNYUAN_REVISION, "hunyuan3d-paintpbr-v2-1/image_encoder/model.safetensors",
     1264217240, "ae616c24393dd1854372b0639e5541666f7521cbe219669255e865cb7f89466a"),
    (DINO, DINO_REVISION, "model.safetensors",
     4546005432, "917d3c470db999d32a312f8542149be91c7cbac61ee8fb4b67ae3d82b79ce21f"),
)


def fetch_part(url: str, part: Path, index: int, total: int, opener) -> None:
    first = index * CHUNK_BYTES
    last = min(first + CHUNK_BYTES, total) - 1
    part_size = last - first + 1
    for attempt in range(12):
        have = part.stat().st_size if part.is_file() else 0
        if have == part_size:
            return
        if have > part_size:
            raise ValueError(f"Unexpected size for {part}")
        start = first + have
        request = urllib.request.Request(f"{url}?range_part={index}&start={start}", headers={"Range": f"bytes={start}-{last}"})
        try:
            with opener(request, timeout=45) as response:
                expected = f"bytes {start}-{last}/{total}"
                if response.status != 206 or response.headers.get("Content-Range") != expected:
                    raise OSError(f"Expected Content-Range {expected}, received {response.status}")
                with part.open("ab") as dest:
                    remaining = last - start + 1
                    while remaining:
                        data = response.read(min(256 * 1024, remaining))
                        if not data:
                            raise OSError("Early EOF")
                        dest.write(data)
                        remaining -= len(data)
            return
        except OSError:
            if attempt == 11:
                raise
            time.sleep(min(attempt + 1, 10))


def restore_verified_blobs(workers: int, source_address: str | None) -> None:
    cache = Path(HF_HUB_CACHE)
    opener = download_opener(source_address)
    unfinished = []
    for repo, revision, name, size, expected_sha in WEIGHTS:
        blob = cache / ("models--" + repo.replace("/", "--")) / "blobs" / expected_sha
        if blob.is_file() and blob.stat().st_size == size:
            print(f"Cached {repo}/{name}", flush=True)
            continue
        blob.parent.mkdir(parents=True, exist_ok=True)
        parts_dir = blob.with_suffix(".ranges")
        parts_dir.mkdir(exist_ok=True)
        parts = [parts_dir / f"{i:04d}.part" for i in range((size + CHUNK_BYTES - 1) // CHUNK_BYTES)]
        unfinished.append((repo, revision, name, size, expected_sha, blob, parts))
    if not unfinished:
        return

    expected_total = sum(item[3] for item in unfinished)
    last_report = time.monotonic()
    all_parts = [part for item in unfinished for part in item[6]]
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        pending = set()
        for index in range(max(len(item[6]) for item in unfinished)):
            for repo, revision, name, size, _, _, parts in unfinished:
                if index < len(parts):
                    url = f"https://huggingface.co/{repo}/resolve/{revision}/{name}"
                    pending.add(pool.submit(fetch_part, url, parts[index], index, size, opener))
        while pending:
            done, pending = concurrent.futures.wait(pending, timeout=30, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in done:
                future.result()
            if not pending or time.monotonic() - last_report >= 30:
                downloaded = sum(part.stat().st_size for part in all_parts if part.is_file())
                print(f"HTTP ranges: {downloaded / 2**30:.2f} / {expected_total / 2**30:.2f} GiB", flush=True)
                last_report = time.monotonic()

    for repo, _, name, size, expected_sha, blob, parts in unfinished:
        staged = blob.with_suffix(".ranges-complete")
        with staged.open("wb") as output:
            for part in parts:
                with part.open("rb") as source:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
        with staged.open("rb") as candidate:
            sha = hashlib.file_digest(candidate, "sha256").hexdigest()
        if staged.stat().st_size != size or sha != expected_sha:
            raise ValueError(f"Publisher SHA-256 or size mismatch for {repo}/{name}")
        staged.replace(blob)
        for part in parts:
            part.unlink()
        parts[0].parent.rmdir()
        print(f"Verified SHA-256 {repo}/{name}", flush=True)
