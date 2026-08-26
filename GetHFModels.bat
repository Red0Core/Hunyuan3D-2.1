@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

:: ---------------------------------------------------------------------------
:: Downloads the AI models. Installs huggingface_hub via pip if missing.
:: Safe to re-run - finished files are skipped, partial ones resume.
::
::   tencent/Hunyuan3D-2.1   ~13 GB   required
::   facebook/dinov2-giant   ~4.2 GB  required
::   tencent/Hunyuan3D-2mv   ~4.6 GB  optional (MultiView tab only)
:: ---------------------------------------------------------------------------

:: Where models are stored. Change this line to use another drive.
if "%HF_HOME%"=="" set "HF_HOME=D:\huggingface"

echo.
echo  Hunyuan3D - model downloader
echo  ===========================
echo  Storing in: %HF_HOME%
echo.

:: use the portable env if it is here, otherwise whatever python is on PATH
set "PY=python"
if exist "%CD%\installer_files\Environments\hunyuan3d\python.exe" (
    set "PY=%CD%\installer_files\Environments\hunyuan3d\python.exe"
    echo  Using env python
) else (
    where python >nul 2>&1
    if errorlevel 1 (
        echo  ERROR: python not found.
        echo  Run Setup.bat first, or open Cmd.bat and try again.
        echo.
        pause
        exit /b 1
    )
    echo  Using python from PATH
)
echo.

echo  Checking huggingface_hub...
"%PY%" -c "import huggingface_hub" >nul 2>&1
if errorlevel 1 (
    echo    installing with pip...
    "%PY%" -m pip install --upgrade huggingface_hub
    if errorlevel 1 (
        echo    pip install FAILED
        pause
        exit /b 1
    )
) else (
    echo    already installed
)
echo.

set "GET_MV=0"
echo  Also download the MultiView model? (~4.6 GB)
echo  Only needed if you use the MultiView tab.
choice /C YN /M "  Download Hunyuan3D-2mv"
if errorlevel 2 goto :run
set "GET_MV=1"

:run
echo.
"%PY%" "%~dp0_hfdl.py" %GET_MV%
if errorlevel 1 (
    echo.
    echo  Some downloads failed. Check your internet and run again.
    echo  Nothing is lost - partial files resume.
    pause
    exit /b 1
)

echo.
echo  All models ready.
echo  Make HF_HOME permanent with:  setx HF_HOME "%HF_HOME%"
echo.
pause
