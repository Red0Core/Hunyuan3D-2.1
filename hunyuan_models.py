"""Pinned model assets for the Hunyuan3D 2.1 Windows inference workflow."""

import functools
import hashlib
import http.client
import os
import shutil
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(ROOT.parent / "huggingface"))
os.environ.setdefault("U2NET_HOME", str(ROOT / "u2net"))

HUNYUAN = "tencent/Hunyuan3D-2.1"
HUNYUAN_REVISION = "0b94677654c57bb9a6b6845cd7b704ccf551d327"
DINO = "facebook/dinov2-giant"
DINO_REVISION = "611a9d42f2335e0f921f1e313ad3c1b7178d206d"
ESRGAN_PATH = ROOT / "hy3dpaint" / "ckpt" / "RealESRGAN_x4plus.pth"


def download_opener(source_address: str | None):
    if not source_address:
        return urllib.request.urlopen

    class BoundHTTPSHandler(urllib.request.HTTPSHandler):
        def https_open(self, request):
            connect = functools.partial(http.client.HTTPSConnection, source_address=(source_address, 0))
            return self.do_open(connect, request, context=self._context)

    return urllib.request.build_opener(BoundHTTPSHandler()).open


def download_asset(path: Path, url: str, expected_md5: str, opener=urllib.request.urlopen) -> None:
    def digest(candidate: Path) -> str:
        with candidate.open("rb") as file:
            return hashlib.file_digest(file, lambda: hashlib.md5(usedforsecurity=False)).hexdigest()

    if path.is_file() and digest(path) == expected_md5:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_suffix(path.suffix + ".part")
    if partial.is_file() and digest(partial) == expected_md5:
        partial.replace(path)
        return

    for attempt in range(8):
        offset = partial.stat().st_size if partial.is_file() else 0
        headers = {"Range": f"bytes={offset}-"} if offset else {}
        request = urllib.request.Request(url, headers=headers)
        print(f"Downloading {path.name} from byte {offset}", flush=True)
        try:
            with opener(request, timeout=45) as response:
                if response.status == 206:
                    if not response.headers.get("Content-Range", "").startswith(f"bytes {offset}-"):
                        raise OSError(f"Unexpected resume offset for {path.name}")
                    mode = "ab"
                else:
                    mode = "wb"
                with partial.open(mode) as file:
                    shutil.copyfileobj(response, file, length=256 * 1024)
            if digest(partial) != expected_md5:
                raise OSError(f"Checksum mismatch for {partial}")
            partial.replace(path)
            return
        except OSError:
            if attempt == 7:
                raise
            time.sleep(min(attempt + 1, 10))


def model_directories(*, download: bool) -> tuple[Path, Path]:
    from huggingface_hub import snapshot_download

    print(f"Resolving Hunyuan3D 2.1 in {os.environ['HF_HOME']}", flush=True)
    hunyuan = snapshot_download(
        HUNYUAN,
        revision=HUNYUAN_REVISION,
        allow_patterns=["hunyuan3d-dit-v2-1/*", "hunyuan3d-paintpbr-v2-1/*"],
        local_files_only=not download,
    )
    print(f"Resolving DINOv2 Giant in {os.environ['HF_HOME']}", flush=True)
    dino = snapshot_download(
        DINO,
        revision=DINO_REVISION,
        allow_patterns=["*.json", "model.safetensors"],
        local_files_only=not download,
    )
    return Path(hunyuan), Path(dino)


def download_models(source_address: str | None = None) -> None:
    model_directories(download=True)
    opener = download_opener(source_address)
    download_asset(
        Path(os.environ["U2NET_HOME"]) / "u2net.onnx",
        "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx",
        "60024c5c889badc19c04ad937298a77b",
        opener,
    )
    download_asset(
        ESRGAN_PATH,
        "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
        "99ec365d4afad750833258a1a24f44ca",
        opener,
    )


if __name__ == "__main__":
    download_models()
