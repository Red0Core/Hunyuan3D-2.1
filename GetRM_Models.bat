@echo off
setlocal enabledelayedexpansion
cd /D "%~dp0"

:: ---------------------------------------------------------------------------
:: Downloads the 2 model files that are too big for GitHub.
:: Run this once after cloning. Safe to re-run: it skips files already correct.
::
::   u2net.onnx            168 MB  -> u2net\
::   RealESRGAN_x4plus.pth  64 MB  -> hy3dpaint\ckpt\
:: ---------------------------------------------------------------------------

echo.
echo  Hunyuan3D-2.1 - downloading required models
echo  ==========================================
echo.

set "OK=1"

call :get "u2net.onnx" ^
         "u2net" ^
         "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx" ^
         "60024c5c889badc19c04ad937298a77b"

call :get "RealESRGAN_x4plus.pth" ^
         "hy3dpaint\ckpt" ^
         "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" ^
         "99ec365d4afad750833258a1a24f44ca"

echo.
if "!OK!"=="1" (
    echo  All models ready. You can run StartHunyuan3D.bat now.
) else (
    echo  Something failed above. Check your internet and run this again.
)
echo.
pause
exit /b 0


:: ---------------------------------------------------------------------------
:: :get  <filename>  <folder>  <url>  <expected md5>
:: ---------------------------------------------------------------------------
:get
set "NAME=%~1"
set "DIR=%~2"
set "URL=%~3"
set "WANT=%~4"
set "DEST=%CD%\%DIR%\%NAME%"

echo  [%NAME%]

if not exist "%CD%\%DIR%" mkdir "%CD%\%DIR%"

if exist "%DEST%" (
    call :md5 "%DEST%"
    if /I "!GOT!"=="%WANT%" (
        echo    already present and valid - skipping
        echo.
        exit /b 0
    )
    echo    present but wrong/incomplete - downloading again
    del /f /q "%DEST%"
)

echo    downloading...
curl -L --fail --progress-bar -o "%DEST%" "%URL%"
if errorlevel 1 (
    echo    DOWNLOAD FAILED
    if exist "%DEST%" del /f /q "%DEST%"
    set "OK=0"
    echo.
    exit /b 1
)

call :md5 "%DEST%"
if /I not "!GOT!"=="%WANT%" (
    echo    CHECKSUM MISMATCH - file is corrupt, deleting
    echo      expected %WANT%
    echo      got      !GOT!
    del /f /q "%DEST%"
    set "OK=0"
    echo.
    exit /b 1
)

echo    done and verified
echo.
exit /b 0


:: ---------------------------------------------------------------------------
:: :md5  <file>   ->  sets GOT
:: ---------------------------------------------------------------------------
:md5
set "GOT="
for /f "skip=1 tokens=*" %%A in ('certutil -hashfile "%~1" MD5 2^>nul') do (
    if not defined GOT set "GOT=%%A"
)
set "GOT=!GOT: =!"
exit /b 0
