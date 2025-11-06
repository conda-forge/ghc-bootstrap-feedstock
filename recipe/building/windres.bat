@echo off
setlocal enabledelayedexpansion

REM Windres wrapper to fix GHC's malformed --preprocessor arguments

REM Find windres
where windres.exe 2>nul >nul
if %errorlevel% == 0 (
    set "WINDRES_CMD=windres.exe"
) else (
    set "WINDRES_CMD=%CONDA_PREFIX%\Library\x86_64-w64-mingw32\bin\windres.exe"
)

REM Determine preprocessor from CC
set "PREPROC_CMD="
set "PREPROC_ARGS="

if defined CC (
    set "PREPROC_CMD=%CC%"
    echo %CC% | find /i "gcc" >nul && set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    echo %CC% | find /i "clang" >nul && set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    echo %CC% | find /i "cl.exe" >nul && set "PREPROC_ARGS=/EP /TC"
)

REM Filter out --preprocessor arguments, keep everything else
set "OTHER_ARGS="

:loop
if "%~1"=="" goto :endloop
set "ARG=%~1"

REM Check if this argument starts with --preprocessor
echo.!ARG! | find /i "--preprocessor" >nul
if errorlevel 1 (
    REM Not a preprocessor arg, keep it
    set "OTHER_ARGS=!OTHER_ARGS! %1"
)

shift
goto :loop

:endloop

REM Build final command
if defined PREPROC_CMD (
    set "FINAL=--preprocessor=!PREPROC_CMD!"
    for %%a in (!PREPROC_ARGS!) do (
        set "FINAL=!FINAL! --preprocessor-arg=%%a"
    )
    set "FINAL=!FINAL!!OTHER_ARGS!"
) else (
    set "FINAL=!OTHER_ARGS!"
)

echo DEBUG: Args: !FINAL!

REM Execute
!WINDRES_CMD! !FINAL!
exit /b %errorlevel%
