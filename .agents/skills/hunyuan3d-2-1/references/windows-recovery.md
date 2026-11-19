# Windows cu132 recovery

On the configured host, use `D:\Hunyuan3D-2.1-cu132`. Run `uv run --locked --no-sync python hunyuan_cli.py doctor` from that checkout before changing anything. It reports the Python and Torch versions and calls the CUDA rasterizer and CPU inpainting extension.

The verified toolchain is CPython 3.13.18 x64, Torch 2.15.0+cu132, torchvision 0.29.2+cu132, nvcc 13.2.86 from Toolkit 13.2.2, and MSVC 14.50.35717 (cl 19.50.35740). The RTX 5070 Ti uses `sm_120`. Compare the driver CUDA number in `nvidia-smi`, `torch.version.cuda` and `nvcc --version` separately. The rasterizer must match the Torch and Python ABIs. CPU inpainting must match the Python ABI.

On this host, nvcc 13.2 crashed with MSVC 19.52 on a minimal standalone kernel. Run `.\setup-windows.ps1 -Offline` to sync cached dependencies, rebuild with the pinned local toolchain and run `doctor` if repair is authorized. Keep ComfyUI isolated.

The normal run reuses the pinned weights in `D:\huggingface` and the U²-Net and Real-ESRGAN files in the checkout. If a download is needed and authorized, use the active sing-box or Karing TUN interface. Pass `-TunnelInterface $tun.InterfaceAlias` to `setup-windows.ps1` when provisioning and the interface IP to the resumable model downloader.

```powershell
$tun = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -in 'singbox_tun', 'Karing TUN Network Adapter' -and $_.AddressState -eq 'Preferred'
} | Select-Object -First 1
if (-not $tun) { throw 'Start the sing-box or Karing TUN first.' }
uv run --locked --no-sync python hunyuan_cli.py models --ranges --source-address $tun.IPAddress --workers 48
```

Retain partial downloads and pinned revisions. Tencent's [Code Usage](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1#code-usage) explains the original shape and paint stages.
