@echo off
setlocal
pushd "%~dp0"
set "PROJECT=%CD%"
set "CUDA_HOME=%PROJECT%\.cuda-13.2.2"
set "CUDA_PATH=%CUDA_HOME%"
set "PYTHON=%PROJECT%\.venv\Scripts\python.exe"
set "VS=%ProgramFiles%\Microsoft Visual Studio\18\Community"
set "MSVC=%PROJECT%\.hunyuan-tmp\msvc-14.50\VC\Tools\MSVC\14.50.35717"
if not exist "%CUDA_HOME%\bin\nvcc.exe" (
    echo Prepare the toolkit with prepare-cuda132.ps1 -Download first.
    goto :error
)
if not exist "%PYTHON%" (
    echo Prepare the project's uv environment first.
    goto :error
)
if not exist "%MSVC%\bin\Hostx64\x64\cl.exe" (
    echo Prepare the local MSVC 14.50 toolset before building.
    goto :error
)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 goto :error
set "VCToolsInstallDir=%MSVC%\"
set "VCToolsVersion=14.50.35717"
set "NVCC_PREPEND_FLAGS=--use-local-env"
set "PATH=%MSVC%\bin\Hostx64\x64;%CUDA_HOME%\bin;%CUDA_HOME%\bin\x64;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
set "INCLUDE=%MSVC%\include;%CUDA_HOME%\include\cccl;%INCLUDE%"
set "LIB=%MSVC%\lib\x64;%CUDA_HOME%\lib\x64;%CUDA_HOME%\lib;%LIB%"
set "TEMP=%PROJECT%\.hunyuan-tmp"
set "TMP=%TEMP%"
set "DISTUTILS_USE_SDK=1"
set "TORCH_CUDA_ARCH_LIST=12.0"
set "MAX_JOBS=2"
"%PYTHON%" -c "import sys,torch; assert sys.version_info[:2]==(3,13) and torch.version.cuda=='13.2', (sys.version,torch.version.cuda)"
if errorlevel 1 goto :error
cd /d "%PROJECT%\hy3dpaint\custom_rasterizer"
"%PYTHON%" setup.py build_ext --inplace
if errorlevel 1 goto :error
cd /d "%PROJECT%\hy3dpaint\DifferentiableRenderer"
"%PYTHON%" setup.py build_ext --inplace
if errorlevel 1 goto :error
cd /d "%PROJECT%"
"%PYTHON%" -B hunyuan_cli.py doctor
if errorlevel 1 goto :error
popd
exit /b 0
:error
popd
exit /b 1
