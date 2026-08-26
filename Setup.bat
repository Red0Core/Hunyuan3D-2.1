@echo off
setlocal EnableDelayedExpansion
cd /D "%~dp0"

:: ---------------------------------------------------------------------------
:: One-shot setup. Does what GetConda.bat + SetEnv.bat did, then builds the env.
::
::   1. downloads and installs portable Miniconda
::   2. writes .condarc so envs/pkgs stay in this folder
::   3. creates the python 3.11 environment
::
:: Everything stays inside installer_files\ - nothing touches your system.
:: Safe to re-run: finished steps are skipped.
:: ---------------------------------------------------------------------------

set "SCRIPT_DIR=%CD%"
set "INSTALL_DIR=%SCRIPT_DIR%\installer_files"
set "CONDA_ROOT_PREFIX=%INSTALL_DIR%\Miniconda"
set "ENV_DIR=%INSTALL_DIR%\Environments"
set "ENV_NAME=hunyuan3d"
set "PY_VER=3.11"
set "MINICONDA_DOWNLOAD_URL=https://repo.anaconda.com/miniconda/Miniconda3-py311_25.7.0-2-Windows-x86_64.exe"

echo.
echo  Portable Miniconda - full setup
echo  ==============================
echo   folder : %SCRIPT_DIR%
echo   env    : %ENV_NAME%  (python %PY_VER%)
echo.

:: === STEP 1 - Miniconda ====================================================
echo  [1/3] Miniconda
if exist "%CONDA_ROOT_PREFIX%\_conda.exe" (
    echo    already installed - skipping
    goto :step2
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%ENV_DIR%" mkdir "%ENV_DIR%"

echo    downloading installer...
curl -L --fail --progress-bar "%MINICONDA_DOWNLOAD_URL%" -o "%INSTALL_DIR%\miniconda_installer.exe"

if not exist "%INSTALL_DIR%\miniconda_installer.exe" (
    echo    curl failed, trying certutil...
    echo %MINICONDA_DOWNLOAD_URL% > "%INSTALL_DIR%\download_url.txt"
    certutil -urlcache -split -f @"%INSTALL_DIR%\download_url.txt" "%INSTALL_DIR%\miniconda_installer.exe"
    del "%INSTALL_DIR%\download_url.txt" 2>nul
)

if not exist "%INSTALL_DIR%\miniconda_installer.exe" (
    echo.
    echo    ALL DOWNLOAD METHODS FAILED
    echo    Download manually from:
    echo      %MINICONDA_DOWNLOAD_URL%
    echo    and save as:
    echo      %INSTALL_DIR%\miniconda_installer.exe
    echo    then run this again.
    pause
    exit /b 1
)

echo    installing...
start /wait "" "%INSTALL_DIR%\miniconda_installer.exe" /InstallationType=JustMe /NoShortcuts=1 /AddToPath=0 /RegisterPython=0 /NoRegistry=1 /S /D=%CONDA_ROOT_PREFIX%

if not exist "%CONDA_ROOT_PREFIX%\_conda.exe" (
    echo    INSTALL FAILED - see messages above
    pause
    exit /b 1
)
del "%INSTALL_DIR%\miniconda_installer.exe" 2>nul
echo    done

:step2
echo.

:: === STEP 2 - .condarc =====================================================
:: Must happen BEFORE creating the env, or conda puts it in the wrong place.
echo  [2/3] Paths (.condarc)
echo envs_dirs: > "%CONDA_ROOT_PREFIX%\.condarc"
echo   - %ENV_DIR% >> "%CONDA_ROOT_PREFIX%\.condarc"
echo pkgs_dirs: >> "%CONDA_ROOT_PREFIX%\.condarc"
echo   - %CONDA_ROOT_PREFIX%\pkgs >> "%CONDA_ROOT_PREFIX%\.condarc"
echo    envs -^> %ENV_DIR%
echo    pkgs -^> %CONDA_ROOT_PREFIX%\pkgs
echo.

:: === STEP 3 - environment ==================================================
echo  [3/3] Environment "%ENV_NAME%"

set "PATH=%CONDA_ROOT_PREFIX%;%CONDA_ROOT_PREFIX%\condabin;%CONDA_ROOT_PREFIX%\Scripts;%CONDA_ROOT_PREFIX%\Library\bin;%PATH%"

if exist "%ENV_DIR%\%ENV_NAME%\python.exe" (
    echo    already exists - skipping
) else (
    echo    creating python %PY_VER% env, please wait...
    call "%CONDA_ROOT_PREFIX%\condabin\conda.bat" create -n %ENV_NAME% python=%PY_VER% -y --override-channels -c conda-forge
    if not exist "%ENV_DIR%\%ENV_NAME%\python.exe" (
        echo    ENV CREATION FAILED
        pause
        exit /b 1
    )
    echo    done
)

echo.
echo  ======================================================================
echo   Setup complete.
echo  ----------------------------------------------------------------------
echo   Next:
echo     1. Cmd.bat          - open a shell with pre-coded env paths
echo     2. GetHFModels.bat  - download the AI models
echo  =======================================================================
echo.

choice /C YN /M "  Open the environment shell now"
if errorlevel 2 goto :done
cls
call "%SCRIPT_DIR%\Cmd.bat"

:done
endlocal
