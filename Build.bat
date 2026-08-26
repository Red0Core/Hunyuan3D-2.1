@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

:: ===========================================================================
:: Detects the build toolchain, sets it up TEMPORARILY (this window only),
:: then installs torch / requirements / deepspeed and builds the extensions.
::
:: SYSTEM tools are preferred. If a system tool is missing, the conda env copy
:: is offered instead. Nothing here changes your permanent PATH.
:: ===========================================================================

if not exist "gradio_app.py" (
    echo  ERROR: run this from the Hunyuan3D folder ^(next to gradio_app.py^)
    pause & exit /b 1
)

set "ENV_ROOT=%CD%\installer_files\Environments\hunyuan3d"

echo.
echo  ============================================================
echo   Hunyuan3D - build environment
echo  ============================================================
echo.
echo  Detecting tools...
echo.

:: ---------------------------------------------------------------- PYTHON --
set "PY="
set "PY_SRC="
if exist "%ENV_ROOT%\python.exe" (
    set "PY=%ENV_ROOT%\python.exe"
    set "PY_SRC=conda env"
) else (
    where python >nul 2>&1
    if not errorlevel 1 (
        for /f "delims=" %%p in ('where python') do if not defined PY set "PY=%%p" & set "PY_SRC=system PATH"
    )
)

:: ------------------------------------------------------------------ MSVC --
set "VCVARS="
set "VSPATH="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set "VSPATH=%%i"
)
if defined VSPATH if exist "!VSPATH!\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=!VSPATH!\VC\Auxiliary\Build\vcvars64.bat"

:: ------------------------------------------------------------------ CUDA --
set "SYS_CUDA="
if defined CUDA_PATH if exist "%CUDA_PATH%\bin\nvcc.exe" set "SYS_CUDA=%CUDA_PATH%"
if not defined SYS_CUDA (
    for /f "delims=" %%d in ('dir /b /ad /o-n "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v*" 2^>nul') do (
        if not defined SYS_CUDA if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%d\bin\nvcc.exe" set "SYS_CUDA=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%d"
    )
)
set "CONDA_CUDA="
if exist "%ENV_ROOT%\Library\bin\nvcc.exe" set "CONDA_CUDA=%ENV_ROOT%\Library"

:: -------------------------------------------------------------- GPU ARCH --
set "ARCH="
set "GPUNAME="
for /f "usebackq delims=" %%a in (`nvidia-smi --query-gpu^=compute_cap --format^=csv^,noheader 2^>nul`) do if not defined ARCH set "ARCH=%%a"
for /f "usebackq delims=" %%a in (`nvidia-smi --query-gpu^=name --format^=csv^,noheader 2^>nul`) do if not defined GPUNAME set "GPUNAME=%%a"

set "TORCH_PKG="
if defined ARCH (
    set "TORCH_PKG=torch==2.11.0+cu128 torchvision==0.26.0+cu128"
    set "TORCH_URL=https://download.pytorch.org/whl/cu128"
)

:: ---------------------------------------------------------------- REPORT --
echo  ------------------------------------------------------------
if defined PY       (echo   python    OK    [%PY_SRC%]) else (echo   python    MISSING)
if defined VCVARS   (echo   MSVC C++  OK    [system] !VSPATH!) else (echo   MSVC C++  MISSING)
if defined SYS_CUDA (
    echo   nvcc      OK    [system] !SYS_CUDA!
) else (
    if defined CONDA_CUDA (echo   nvcc      not on system - found in conda env) else (echo   nvcc      MISSING)
)
if defined GPUNAME  (echo   GPU       !GPUNAME!  ^(sm_!ARCH:.=!^)) else (echo   GPU       not detected)
if defined TORCH_PKG (echo   torch     will install cu128 ^(covers RTX 20/30/40/50^))
echo  ------------------------------------------------------------
echo.

:: ------------------------------------------------------- MISSING HANDLING --
if not defined PY (
    echo  Python not found. Run Setup.bat first.
    pause & exit /b 1
)
if not defined VCVARS (
    echo  MSVC C++ build tools are MISSING - required to compile.
    echo.
    echo  Install "Visual Studio Build Tools 2022" with the
    echo  "Desktop development with C++" workload:
    echo     https://visualstudio.microsoft.com/downloads/
    echo.
    pause & exit /b 1
)

set "CUDA_DIR=%SYS_CUDA%"
set "CUDA_SRC=system"
if not defined SYS_CUDA (
    if defined CONDA_CUDA (
        echo  No system CUDA Toolkit found, but the conda env has nvcc.
        echo    !CONDA_CUDA!\bin\nvcc.exe
        echo.
        choice /C YN /M "  Use the conda env nvcc for this build"
        if errorlevel 2 (
            echo.
            echo  Install the CUDA Toolkit system-wide instead:
            echo     https://developer.nvidia.com/cuda-downloads
            echo  Match your torch CUDA version ^(12.8^).
            pause & exit /b 1
        )
        set "CUDA_DIR=!CONDA_CUDA!"
        set "CUDA_SRC=conda env"
    ) else (
        echo  No CUDA Toolkit found - required for custom_rasterizer.
        echo    system-wide : https://developer.nvidia.com/cuda-downloads
        echo    or into env : conda install -c nvidia cuda-toolkit=12.8
        echo.
        pause & exit /b 1
    )
)
echo.

:: -------------------------------------------------- TEMPORARY ENVIRONMENT --
echo  Setting up build environment ^(this window only^)...
call "%VCVARS%" >nul 2>&1
if errorlevel 1 ( echo  vcvars64.bat FAILED & pause & exit /b 1 )

set "CUDA_HOME=%CUDA_DIR%"
set "CUDA_PATH=%CUDA_DIR%"
set "PATH=%CUDA_DIR%\bin;%PATH%"
if defined ARCH set "TORCH_CUDA_ARCH_LIST=%ARCH%"
set "DISTUTILS_USE_SDK=1"

:: cl.exe needs CUDA's targets\x64 headers for nv/target, which cuda_fp16.h
:: pulls in. nvcc locates them itself; cl.exe does not.
if exist "%CUDA_DIR%\include\targets\x64" set "INCLUDE=%CUDA_DIR%\include\targets\x64;%INCLUDE%"
:: conda lays CUDA libs out as Library\lib, but torch passes Library\lib\x64
:: (the NVIDIA layout), so cudart.lib is not found at link time.
if exist "%CUDA_DIR%\lib\cudart.lib" set "LIB=%CUDA_DIR%\lib;%LIB%"

:: put the conda env on PATH, else "python" resolves to system python
if "%PY_SRC%"=="conda env" (
    set "PATH=%ENV_ROOT%;%ENV_ROOT%\Library\mingw-w64\bin;%ENV_ROOT%\Library\usr\bin;%ENV_ROOT%\Library\bin;%ENV_ROOT%\Scripts;%ENV_ROOT%\bin;%PATH%"
    set "CONDA_PREFIX=%ENV_ROOT%"
    set "CONDA_DEFAULT_ENV=hunyuan3d"
)

echo    MSVC      ready
echo    CUDA      %CUDA_DIR%   [%CUDA_SRC%]
echo    ARCH LIST %TORCH_CUDA_ARCH_LIST%
for /f "delims=" %%v in ('python --version 2^>^&1') do echo    python    %%v  ^(from PATH^)
for /f "delims=" %%v in ('where nvcc 2^>nul') do echo    nvcc      %%v
"%PY%" -c "import torch;print('   torch    ',torch.__version__,' cuda',torch.version.cuda,' gpu',torch.cuda.is_available())" 2>nul
if errorlevel 1 echo    torch     NOT INSTALLED yet - do step 1 first
echo.

:menu
echo  ============================================================
echo    1  Install PyTorch  ^(GPU build - DO THIS FIRST^)
echo    2  Install requirements.txt
echo    3  Install deepspeed            ^(optional - training only^)
echo    4  Build custom_rasterizer      ^(needs MSVC + CUDA^)
echo    5  Build DifferentiableRenderer ^(needs MSVC only^)
echo    6  Do 1-5 in order
echo    7  Open a shell with this build environment
echo    0  Exit
echo  ============================================================
choice /C 12345670 /N /M "  Choose: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto m1
if "%SEL%"=="2" goto m2
if "%SEL%"=="3" goto m3
if "%SEL%"=="4" goto m4
if "%SEL%"=="5" goto m5
if "%SEL%"=="6" goto m6
if "%SEL%"=="7" goto m7
if "%SEL%"=="8" goto done
goto menu

:m1
call :torch
goto menu

:m2
call :req
goto menu

:m3
call :deepspd
goto menu

:m4
call :rasteriz
goto menu

:m5
call :diffrend
goto menu

:m6
call :torch
if errorlevel 1 goto m6fail
call :req
if errorlevel 1 goto m6fail
call :deepspd
call :rasteriz
if errorlevel 1 goto m6fail
call :diffrend
if errorlevel 1 goto m6fail
echo.
echo   All steps finished.
echo.
goto menu

:m6fail
echo.
echo   STOPPED - a step above failed. Fix it, then run that step alone.
echo.
goto menu

:m7
echo.
echo  Build env active. Type exit to return.
cmd /k
goto menu

:done
endlocal
exit /b 0


:: =========================== routines ======================================

:torch
echo.
echo  --- installing PyTorch ---
if not defined TORCH_PKG (
    echo  No NVIDIA GPU detected - skipping. Install torch manually.
    echo.
    exit /b 0
)
echo  %TORCH_PKG%
echo  from %TORCH_URL%
echo.
echo  Must run BEFORE requirements.txt: requirements.txt has no torch line,
echo  so pip would pull the CPU build in as a dependency of torchmetrics.
echo.
"%PY%" -m pip install %TORCH_PKG% --index-url %TORCH_URL%
if errorlevel 1 ( echo   torch install FAILED & echo. & exit /b 1 )
"%PY%" -c "import torch;print('   installed:',torch.__version__,'| cuda',torch.version.cuda,'| gpu',torch.cuda.is_available())"
"%PY%" -c "import torch,sys;sys.exit(0 if torch.cuda.is_available() else 1)" 2>nul
if errorlevel 1 (
    echo.
    echo   WARNING: torch reports NO GPU - probably the CPU build.
    echo   Fix:  pip uninstall -y torch torchvision   then run step 1 again.
)
echo.
exit /b 0

:req
echo.
echo  --- installing requirements.txt ---
"%PY%" -m pip install -r requirements.txt
if errorlevel 1 ( echo   requirements FAILED & echo. & exit /b 1 )
echo.
exit /b 0

:deepspd
echo.
echo  --- installing deepspeed ---
echo  Building from source. deepspeed's sdist is missing bin\deepspeed.bat
echo  which its own setup.py requires on Windows - _dsbuild.py adds it.
echo.
:: never pre-compile the CUDA ops: they need aio.lib / cufile.lib (Linux only)
set "DS_BUILD_OPS=0"
set "DS_BUILD_AIO=0"
set "DS_BUILD_SPARSE_ATTN=0"
set "DS_BUILD_EVOFORMER_ATTN=0"
:: deepspeed's builder imports cpuinfo; without it it falls back to Linux lscpu
"%PY%" -m pip install py-cpuinfo
"%PY%" "%~dp0_dsbuild.py"
if errorlevel 1 (
    echo.
    echo   deepspeed FAILED.
    echo   NOTE: deepspeed is only used for TRAINING - gradio_app.py never
    echo   imports it, so generation still works without it.
    echo.
    exit /b 0
)
"%PY%" -c "import deepspeed;print('   installed: deepspeed',deepspeed.__version__)" 2>nul
echo.
exit /b 0

:rasteriz
echo.
echo  --- building custom_rasterizer ---
pushd hy3dpaint\custom_rasterizer
"%PY%" -m pip install . --no-build-isolation
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" ( echo   custom_rasterizer FAILED & echo. & exit /b 1 )
echo.
exit /b 0

:diffrend
echo.
echo  --- building DifferentiableRenderer ---
"%PY%" -c "import pybind11" 2>nul
if errorlevel 1 (
    echo   pybind11 missing - run step 2 ^(requirements.txt^) first.
    echo.
    exit /b 1
)
pushd hy3dpaint\DifferentiableRenderer
"%PY%" setup.py build_ext --inplace
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" ( echo   DifferentiableRenderer FAILED & echo. & exit /b 1 )
echo.
exit /b 0
