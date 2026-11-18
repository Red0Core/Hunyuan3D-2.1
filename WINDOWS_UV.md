# Hunyuan3D 2.1 на Windows через uv

Локальная ветка основана на `official-imvoiid/Hunyuan3D-2.1@6d31b3724aa369a41d86582f34f34c472b5a47cb`.
Профиль фиксирует CPython 3.11.18 x64, Torch 2.11.0+cu128 и torchvision 0.26.0+cu128.
На этой машине проект расположен в `D:\Hunyuan3D-2.1`, кеш uv в `D:\.uv-cache`, веса Hub в `D:\huggingface`.
Два вспомогательных веса лежат в `u2net` и `hy3dpaint\ckpt` внутри проекта. Временные файлы команды установки лежат в `.hunyuan-tmp`.

## Установка и запуск

Запустите из каталога проекта в PowerShell. Команда `setup` использует уже установленный Python из `.python-version`.

```powershell
.\run-windows.ps1 setup
.\run-windows.ps1 doctor
.\run-windows.ps1 models
.\run-windows.ps1 generate assets\demo.png outputs\demo.glb --preset draft --seed 1234
.\run-windows.ps1 verify outputs\demo.glb
```

`doctor` загружает поставляемые `.pyd` и вызывает GPU-растеризацию и CPU-inpainting. `models` загружает только нужные ревизии для одного входного изображения. `generate` по умолчанию использует черновой пресет и загружает shape и paint на GPU по очереди. Для интеграции передайте путь к изображению и новый путь `.glb`. Последняя строка stdout содержит JSON с путём результата, количеством треугольников, размерами текстур и пиком аллокаций Torch. Ненулевой код выхода означает ошибку. Файл публикуется только после проверки геометрии, UV и двух встроенных PBR-карт.

Если Xet держит соединения без прогресса, остановите этот запуск и выполните `.\run-windows.ps1 models --ranges`. Команда продолжает частичные загрузки с официального Hugging Face и сверяет SHA-256 перед записью в кеш.

Для явного выбора локального интерфейса sing-box используйте:

```powershell
$tun = (Get-NetIPAddress -InterfaceAlias 'singbox_tun' -AddressFamily IPv4 | Select-Object -First 1).IPAddress
.\run-windows.ps1 models --ranges --source-address $tun --workers 48
```
### Особенности зафиксированных wheels

Windows wheel `bpy==4.2.0` опубликован как `cp311-win_amd64`, но его внутренний файл `WHEEL` содержит `Tag: cp39-cp39-win_amd64`. Из-за этого `uv pip check` сообщает об ошибке тега платформы. На CPython 3.11.18 импорт `bpy` и загрузка paint-модуля прошли. Экспорт CLI использует встроенные PBR-материалы trimesh.

## Проверка на RTX 5070 Ti

19 ноября 2026 года после перезагрузки обе поставляемые библиотеки прошли `doctor`. Полный прогон использовал локальные веса в `D:\huggingface`, `HF_HUB_OFFLINE=1` и `TRANSFORMERS_OFFLINE=1`.

- Вход `assets\demo.png`, пресет `draft`, seed `1234`. По времени от запуска пайплайна до валидированного GLB прошло 153,17 с.
- `outputs\demo.glb` содержит 40 000 треугольников, UV и две встроенные PNG-карты размером 2048 × 2048. Размер файла 5 094 176 байт.
- Blender импортировал GLB и отрисовал виды спереди и сзади. На задней стороне стоек таблички видны небольшие артефакты чернового пресета.
- При `HY3D_PROFILE=1` каждая стадия paint pipeline сбрасывает счётчик пиковой памяти. В этом режиме CLI возвращает `null` в `peak_allocated_gib`. Максимум среди записанных стадий paint в этом запуске был 8,96 ГиБ по счётчику PyTorch.
## Пересборка расширений

Обычный запуск использует два готовых `cp311-win_amd64.pyd` от форка. Для пересборки на CUDA 12.8 откройте x64 shell с MSVC v143 и выбранными SDK/CUDA. На этой машине CUDA 12.8.93 лежит в `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8`. У текущего MSVC 19.52 версия выше порога CUDA 12.8. Используйте MSVC v143 14.44 для этого профиля. Для работ со сборкой используйте отдельную рабочую копию, поскольку команды обновят локальные бинарники рядом с исходниками.

```powershell
$root = (Get-Location).Path
$env:CUDA_HOME = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8'
$env:CUDA_PATH = $env:CUDA_HOME
$env:TORCH_CUDA_ARCH_LIST = '12.0'
$env:DISTUTILS_USE_SDK = '1'
$env:PATH = "$env:CUDA_HOME\bin;$env:PATH"
$python = Join-Path $root '.venv\Scripts\python.exe'

Push-Location hy3dpaint\custom_rasterizer
try { & $python setup.py build_ext --inplace; if ($LASTEXITCODE) { throw 'CUDA rasterizer build failed' } }
finally { Pop-Location }

Push-Location hy3dpaint\DifferentiableRenderer
try { & $python setup.py build_ext --inplace; if ($LASTEXITCODE) { throw 'CPU inpaint build failed' } }
finally { Pop-Location }

.\run-windows.ps1 doctor
```
