"""Model downloader used by GetHFModels.bat. Resumes; skips what exists."""
import sys
from huggingface_hub import snapshot_download

want_mv = len(sys.argv) > 1 and sys.argv[1] == "1"

JOBS = [
    ("tencent/Hunyuan3D-2.1", "shape + paint  (~13 GB)",
     ["hunyuan3d-dit-v2-1/*", "hunyuan3d-paintpbr-v2-1/*"]),
    ("facebook/dinov2-giant", "image encoder  (~4.2 GB)",
     # safetensors only - skips the duplicate pytorch_model.bin
     ["*.json", "*.txt", "*.safetensors"]),
]
if want_mv:
    JOBS.append(
        ("tencent/Hunyuan3D-2mv", "multiview shape  (~4.6 GB)",
         # .ckpt only - the .safetensors copy is 3 GB and never loaded
         ["hunyuan3d-dit-v2-mv/config.yaml", "hunyuan3d-dit-v2-mv/model.fp16.ckpt"]))

failed = 0
for repo, label, patterns in JOBS:
    print("\n  [%s]  %s" % (repo, label), flush=True)
    try:
        print("    ok -> %s" % snapshot_download(repo_id=repo, allow_patterns=patterns), flush=True)
    except Exception as e:
        failed += 1
        print("    FAILED: %s: %s" % (type(e).__name__, str(e)[:180]), flush=True)

sys.exit(1 if failed else 0)
