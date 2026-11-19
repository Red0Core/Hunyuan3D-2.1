# Hunyuan3D 2.1 на Windows с Python 3.13 и CUDA 13.2

Профиль `robloxstoryfactory/uv-win-cu132` работает из отдельной копии `D:\Hunyuan3D-2.1-cu132`. Базовую конфигурацию Python 3.11 / cu128 можно запустить из `D:\Hunyuan3D-2.1`.

| Компонент | Версия |
| --- | --- |
| Python x64 | 3.13.18 |
| PyTorch / torchvision | 2.15.0+cu132 / 0.29.2+cu132 |
| CUDA Toolkit / nvcc | 13.2.2 / 13.2.86 |
| MSVC для CUDA-сборки | 14.50.35717, cl 19.50.35740 |
| Windows SDK | 10.0.26100.0 |
| GPU / драйвер | GeForce RTX 5070 Ti (sm_120) / 616.92 |

## Окружение

```powershell
Set-Location -LiteralPath 'D:\Hunyuan3D-2.1-cu132'
.\stage-cu132.ps1             # показать план
.\stage-cu132.ps1 -Download   # синхронизировать uv.lock, подготовить CUDA и MSVC
```

Нужны существующие uv с Python 3.13 x64 и Visual Studio Community 2026 с Windows SDK. Подготовка привязана к `singbox_tun`. Python-пакеты фиксирует `uv.lock`. Совместимые Torch и torchvision переиспользуются из кеша `D:\.uv-cache`. BasicSR 1.4.2 берётся из проверенного универсального wheel из того же кеша. На чистой машине потребуется wheel с указанным в скрипте SHA-256. Исходная упаковка BasicSR 1.4.2 ломается при сборке под Python 3.13.

Пять архивов Toolkit занимают 93 069 690 байт. Четыре x64-пакета MSVC из каталога установленной Visual Studio занимают 83 284 392 байта. Скрипты проверяют SHA-256 и распаковывают инструменты в рабочую копию на D:. MSVC использует установленный SDK. На этой машине `cudafe++` из CUDA 13.2.1 и 13.2.2 падает с `0xC0000005` на пустом ядре с MSVC 19.52. CUDA 13.2.2 с MSVC 19.50 собрала ядро и растеризатор под `sm_120`.

CLI сам экспортирует PBR GLB. Опциональный extra `blender` нужен для старого пути конвертации через `bpy`.

## Сборка и проверка

```powershell
.\build-cu132.cmd
if ($LASTEXITCODE) { throw 'cu132 native build failed' }
.\run-windows.ps1 doctor

$env:HF_HUB_OFFLINE = '1'
$env:TRANSFORMERS_OFFLINE = '1'
$env:UV_OFFLINE = '1'
$Glb = "outputs\neo-machiya-cu132-$(Get-Date -Format yyyyMMdd-HHmmss).glb"
.\run-windows.ps1 generate 'D:\Hunyuan3D-2.1\outputs\neo-machiya\reference.png' $Glb --preset quality --seed 1234
if ($LASTEXITCODE) { throw 'cu132 inference failed' }
.\run-windows.ps1 verify $Glb
```

В рабочей копии используются существующие веса Hugging Face из `D:\huggingface`. У U²-Net и Real-ESRGAN жёсткие ссылки на проверенные веса из базового профиля. `doctor` выполняет тест растеризации треугольника на GPU и проверяет обработку текстуры на CPU. Сборка создаёт расширения `cp313-win_amd64.pyd` рядом с исходниками.


## Результат на RTX 5070 Ti

Тест `quality` с seed `1234` и тем же изображением японского дома сохранил GLB c 100 000 треугольников и встроенными PNG-картами `baseColorTexture` и `metallicRoughnessTexture` по 2048 × 2048. Повторный запуск `verify` подтвердил встроенные карты и читаемые данные текстур. Blender 5.3.0 импортировал меш с обеими картами, сохранил их в `.blend` и отрендерил превью. В исходном GLB видны мелкие отделённые фрагменты геометрии около крыши.

| Профиль | Весь запуск | Диффузия текстур (цикл денойзинга) |
| --- | ---: | ---: |
| Python 3.11 / cu128 | 250,01 с | 112,14 с |
| Python 3.13 / cu132 | 472,69 с | 274,71 с |

Это по одному прогону на профиль. Для повседневной генерации на этой машине базовый cu128 пока быстрее. Для отладки более свежих зависимостей доступен проверенный cu132 без смены рабочего профиля.
