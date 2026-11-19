# Hunyuan3D 2.1 Image-to-Model на Windows

Проверенный профиль использует CPython 3.13.18, Torch 2.15.0+cu132 и torchvision 0.29.2+cu132 на Windows 11 x64 с RTX 5070 Ti (`sm_120`). CUDA-растеризатор и CPU-inpainting собираются для Python ABI `cp313`.

## Установка и сборка

Нужны uv, Git, Visual Studio Community 2026 с C++ и Windows SDK, а также драйвер NVIDIA с поддержкой CUDA 13.2. На тестовом компьютере использовались Windows SDK 10.0.26100.0 и драйвер 616.92.

```powershell
uv python install 3.13.18
.\setup-windows.ps1
```

Для размещения данных на D: откройте checkout на D: и задайте переменные для текущего процесса до установки или загрузки.

```powershell
$env:UV_CACHE_DIR = 'D:\.uv-cache'
$env:UV_PYTHON_INSTALL_DIR = 'D:\uv-python'
$env:HF_HOME = 'D:\huggingface'
```

На машине с готовым окружением используйте `.\setup-windows.ps1 -Offline`. При необходимости привязки к туннелю передайте `-TunnelInterface 'singbox_tun'` или `-TunnelInterface 'Karing TUN Network Adapter'`.

Установщик синхронизирует `uv.lock`, подготавливает локальный Toolkit 13.2.2 (`nvcc` 13.2.86) и MSVC 14.50 из каталога Visual Studio, собирает два расширения и запускает `doctor`. NVIDIA-архивы занимают 93 069 690 байт, архивы MSVC на проверенной машине — около 82 МБ. Скачанные архивы проверяются по SHA-256. С MSVC 19.52 этот nvcc падал даже на пустом ядре. Для сборки используется MSVC 19.50.35740 и установленный SDK. Wheel BasicSR 1.4.2 лежит в репозитории. [Происхождение и SHA-256](vendor/README.md)

## Веса и запуск

По умолчанию кеш Hugging Face лежит в каталоге `huggingface` рядом с checkout. До первого офлайн-запуска CLI подготавливает Hunyuan3D 2.1, DINOv2 Giant, U²-Net и Real-ESRGAN. Уже доступные файлы переиспользуются.

```powershell
uv run --locked --no-sync python hunyuan_cli.py models --ranges
```

При загрузке через TUN передайте IPv4 интерфейса в `models --ranges --source-address <IP>`.

```powershell
$env:UV_OFFLINE = '1'
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
$Glb = "outputs\prop-$(Get-Date -Format yyyyMMdd-HHmmss).glb"
uv run --locked --no-sync python hunyuan_cli.py generate 'D:\assets\reference.png' $Glb --preset quality --seed 1234
if ($LASTEXITCODE) { throw 'Hunyuan generation failed' }
uv run --locked --no-sync python hunyuan_cli.py verify $Glb
```

Отдельная проверка инструментов выполняется командой `uv run --locked --no-sync python hunyuan_cli.py doctor`. Она растеризует треугольник на GPU и проверяет inpainting на CPU. `verify` проверяет меш, UV и читаемость карт `baseColorTexture` и `metallicRoughnessTexture`. Для замера пайплайна используйте поле `seconds` из результата. `HY3D_PROFILE=1` добавляет время этапов.

`quality` проверялся на доме, диораме, ретрокамере и армиллярной сфере. Для оценки модели в Blender смотрите силуэт, детали с обратной стороны и мелкую отделённую геометрию.
