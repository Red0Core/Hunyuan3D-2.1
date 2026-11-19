# Hunyuan3D 2.1 Image-to-Model на Windows

Рабочий профиль на Windows 11 x64 с RTX 5070 Ti (sm_120). Он использует CPython 3.13.18, Torch 2.15.0+cu132, torchvision 0.29.2+cu132 и `uv.lock`. Рендерер и CPU-inpainting собираются для ABI `cp313`.

## Установка

Нужны uv, Python 3.13.18 x64, Visual Studio Community 2026 с C++ и Windows SDK, а также драйвер NVIDIA с поддержкой cu132. На проверенной машине установлен Windows SDK 10.0.26100.0 и драйвер 616.92.

```powershell
.\stage-cu132.ps1
.\stage-cu132.ps1 -Download
.\build-cu132.cmd
.\run-windows.ps1 doctor
```

Python можно установить заранее через `uv python install 3.13.18`. Если установка нужна на D:, задайте `UV_PYTHON_INSTALL_DIR` для этого процесса. `stage-cu132.ps1` использует `D:\.uv-cache`. Wheel BasicSR 1.4.2 входит в репозиторий: оригинальная сборка sdist не проходит под Python 3.13. [Происхождение и SHA-256](vendor/README.md)

Подготовка требует активного sing-box TUN, включая Karing. CUDA Toolkit 13.2.2 (nvcc 13.2.86) занимает 93 069 690 байт архивов, MSVC 14.50 — 83 284 392 байта. Скрипты проверяют архивы и распаковывают их в checkout. Используется существующий SDK. На проверенной машине CUDA 13.2.2 падала с MSVC 19.52 даже на пустом ядре. С MSVC 19.50.35740 успешно собраны и загружены оба расширения.

## Веса и запуск

По умолчанию Hugging Face использует каталог `huggingface` рядом с checkout. На этом компьютере это `D:\huggingface`. Перед первым офлайн-запуском подготавливаются Hunyuan3D 2.1, DINOv2 Giant, U²-Net и Real-ESRGAN. Запускайте загрузку только если нужных файлов ещё нет.

```powershell
$tun = & .\get-tun.ps1
.\run-windows.ps1 models --ranges --source-address $tun.IPAddress --workers 48
```

```powershell
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
$env:UV_OFFLINE = '1'
$Glb = "outputs\prop-$(Get-Date -Format yyyyMMdd-HHmmss).glb"
.\run-windows.ps1 generate 'D:\assets\reference.png' $Glb --preset quality --seed 1234
if ($LASTEXITCODE) { throw 'Hunyuan generation failed' }
.\run-windows.ps1 verify $Glb
```

`doctor` растеризует тестовый треугольник на GPU и проверяет inpainting на CPU. `verify` проверяет меш, UV и читаемость встроенных карт `baseColorTexture` и `metallicRoughnessTexture`. Для замера самого пайплайна берите поле `seconds` из результата генерации. `HY3D_PROFILE=1` добавляет время отдельных этапов.

`quality` проверен на доме, диораме с садом, ретрокамере и сфере с тонкими кольцами. Проверка включала импорт GLB и рендер в Blender с обеими PBR-картами. Один ракурс может давать выдуманные детали сзади и отдельные фрагменты. Проверяйте модель в ракурсах, которые войдут в кадр.
