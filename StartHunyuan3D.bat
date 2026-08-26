@echo off
setlocal

cd /D "%~dp0"

:: Define paths
set "Miniconda=%CD%\installer_files\Miniconda"
set "Scripts=%Miniconda%\Scripts"
set "Bin=%Miniconda%\Library\bin"
set "CondaBat=%Miniconda%\condabin\conda.bat"

:: Update PATH
set "PATH=%Miniconda%;%Miniconda%\condabin;%Scripts%;%Bin%;%PATH%"

:: Activate Conda env
call "%CondaBat%" activate hunyuan3d >nul 2>&1 || (
    echo Failed to activate 'hunyuan3d' environment.
    exit /b 1
)

:: conda's activate.d scripts (vs2017_compiler_vars.bat, ~cuda-nvcc_activate.bat)
:: have no @echo off, so activation turns echo back ON. Re-assert it here or
:: every following command gets printed to the console.
@echo off

set "PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True"
set "HF_HUB_DISABLE_TELEMETRY=1"
set "HF_HUB_DISABLE_PROGRESS_BARS=1"

:: ---------------------------------------------------------------------------
:: Quality preset. ~164s per textured model, peak 15.0GB on a 16GB card.
::
:: The GUI has two input tabs:
::   Image Prompt      - one image, uses Hunyuan3D-2.1 (best single-view geometry)
::   MultiView Prompt  - front/back/left/right, any subset, uses Hunyuan3D-2mv
::                       (downloads ~4.6GB the first time you actually use it)
:: Upload anything in the MultiView tab and it routes there automatically.
::
:: Cost of each flag, measured:
::   --max_num_view 8 --view_resolution 768 : texture sharpness   (multiview 16s -> 58s)
::   --texture_size 4096 --render_size 2048 : holds that detail   (uv inpaint 4s -> 21s)
::   --max_face_num 100000                  : face/limb geometry  (remesh 6s -> 23s)
::
:: For the ~65s fast preset instead, swap the flags below for:
::   --max_num_view 6 --view_resolution 512 --render_size 1024
::   --texture_size 2048 --max_face_num 40000
::   --default_steps 25 --default_octree 256
::
:: Do not raise --max_face_num to 200000: it costs another 48s in UV unwrap alone
:: for almost no visible gain.
::
:: Other switches:
::   HY3D_PROFILE=1  -> per-phase time/VRAM breakdown in this console
::   HY3D_FAST_CFG=0 -> restore the original 3-branch texture guidance
:: ---------------------------------------------------------------------------
:: One line on purpose. Multi-line ^ continuations get echoed by cmd and are
:: fragile; keep the flags together here.
set "ARGS=--enable_flashvdm --low_vram_mode --max_num_view 8 --view_resolution 768 --render_size 2048 --texture_size 4096 --max_face_num 100000 --default_steps 30 --default_octree 384"

python gradio_app.py %ARGS%

if errorlevel 1 (
    echo.
    echo  The app exited with an error. The real cause is in the lines above.
    echo  If you pressed Ctrl+C this is normal - startup takes 2-4 minutes.
    echo.
    pause
    exit /b 1
)
