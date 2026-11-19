# Проверка Hunyuan3D с CUDA 13.2

Экспериментальный профиль на `D:\Hunyuan3D-2.1-cu132` в ветке `robloxstoryfactory/uv-win-cu132`. Базовый проверенный профиль на `D:\Hunyuan3D-2.1` работает независимо.

- Python `3.13.18`, Torch `2.15.0+cu132` и torchvision `0.29.2+cu132` уже подготовлены из локального кеша. BasicSR берётся из существующего универсального wheel `py3-none-any` из кеша uv. Создавать wheel сборкой sdist под 3.13 не требуется.
- Веса Hugging Face используются из `D:\huggingface`. Веса Real-ESRGAN и U²-Net доступны на том же томе через жёсткие ссылки. Сеть для инференса можно отключить переменными `HF_HUB_OFFLINE=1` и `TRANSFORMERS_OFFLINE=1`.
- CLI сохраняет PBR GLB без загрузки встроенного Blender. Расширение `blender` в `pyproject.toml` предназначено для встроенного конвертера с `bpy`. Обычный `uv sync` его не ставит.
- Скомпилированные `.pyd` упаковки Python 3.11 остаются в Git для старого профиля. В рабочем каталоге Python 3.13 ищет свои `.pyd`, которые создаёт `build-cu132.cmd`.

## Загрузка после согласования

```powershell
Set-Location -LiteralPath 'D:\Hunyuan3D-2.1-cu132'
.\stage-cu132.ps1             # показать план без сетевых запросов
.\stage-cu132.ps1 -Download   # выполнить только после команды пользователя
```

Скрипт требует работающий `singbox_tun`. Пять выбранных архивов из манифеста NVIDIA Toolkit `13.2.1` суммарно занимают 93 246 909 байт. Скрипт возобновляет прерванные загрузки и сверяет SHA-256 по манифесту перед распаковкой. Toolkit устанавливается в `.cuda-13.2.1` внутри этой рабочей копии. Следом uv разрешит зависимости и создаст новый `uv.lock`. Офлайн-резолв проекта пока не прошёл. Точный объём дополнительных wheels будет ясен при разрешении и синхронизации. Проверки сейчас используют только существующий кеш.

## Сборка и проверка после подготовки окружения

```powershell
.\build-cu132.cmd
if ($LASTEXITCODE) { throw 'cu132 native build failed' }
$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
.\run-windows.ps1 generate 'D:\Hunyuan3D-2.1\outputs\neo-machiya\reference.png' 'outputs\neo-machiya-cu132.glb' --preset quality --seed 1234
if ($LASTEXITCODE) { throw 'cu132 inference failed' }
.\run-windows.ps1 verify 'outputs\neo-machiya-cu132.glb'
```

Сборка включает существующий x64 MSVC Visual Studio 2026 в дочернем процессе, задаёт `sm_120` и проверяет реальные вызовы CUDA-растеризатора и CPU-inpainting. Скомпилированные расширения и полный прогон на `cu132` нужно проверить на машине после скачивания Toolkit и зависимостей.
