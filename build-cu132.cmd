@echo off
setlocal
pushd "%~dp0"
set "PROJECT=%CD%"
set "CUDA_HOME=%PROJECT%\.cuda-13.2.1"
set "CUDA_PATH=%CUDA_HOME%"
set "PYTHON=%PROJECT%\.venv\Scripts\python.exe"
set "VS=%ProgramFiles%\Microsoft Visual Studio\18\Community"
if not exist "%CUDA_HOME%\bin\nvcc.exe" (
    echo Prepare the toolkit with prepare-cuda132.ps1 -Download first.
    goto :error
)
if not exist "%PYTHON%" (
    echo Prepare the project's uv environment first.
    goto :error
)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 goto :error
set "PATH=%CUDA_HOME%\bin;%CUDA_HOME%\bin\x64;%VS%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
set "INCLUDE=%CUDA_HOME%\include\cccl;%INCLUDE%"
set "LIB=%CUDA_HOME%\lib\x64;%CUDA_HOME%\lib;%LIB%"
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
