# Windows cu132 recovery

Use `D:\Hunyuan3D-2.1-cu132` on the configured host. Run `.\run-windows.ps1 doctor` before changing anything. It checks the Python and Torch versions and makes real calls into the CUDA rasterizer and CPU inpainting extension. Run from the cu132 checkout so the paths and lockfile resolve from it.

The known toolchain is CPython 3.13.18 x64, Torch 2.15.0+cu132, torchvision 0.29.2+cu132, nvcc 13.2.86 from Toolkit 13.2.2, and local MSVC 14.50.35717 (cl 19.50.35740). The RTX 5070 Ti uses `sm_120`. The driver CUDA number in `nvidia-smi`, `torch.version.cuda` and `nvcc --version` measure different components. The rasterizer must match the Torch and Python ABIs. CPU inpainting must match the Python ABI.

On the tested host, nvcc 13.2 crashed with MSVC 19.52 on a minimal standalone kernel. The checkout's `prepare-msvc1450.ps1` stages the compatible host compiler beside the project. Use the repository's Windows guide and `stage-cu132.ps1` or `build-cu132.cmd` when repair is authorized. Preserve the isolated ComfyUI environment.

The normal run uses the weights in `D:\huggingface` and the U²-Net and Real-ESRGAN files in the checkout. Use the existing caches. If weights are missing and a download is authorized, get the active sing-box or Karing TUN address and resume the pinned downloads:

```powershell
$tun = & .\get-tun.ps1
.\run-windows.ps1 models --ranges --source-address $tun.IPAddress --workers 48
```

Retain partial downloads and keep the pinned revisions. The published source repository's [README and Code Usage](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1#code-usage) explain the original model stages. Use the local locked Windows profile for installation and execution.
