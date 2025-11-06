@echo off
setlocal enabledelayedexpansion

REM Windows CMD script to call windres with appropriate preprocessor
REM GHC passes malformed --preprocessor arguments, so we strip them and rebuild

REM Find windres executable
where windres.exe 2>nul >nul
if %errorlevel% == 0 (
    set "WINDRES_CMD=windres.exe"
) else (
    set "WINDRES_CMD=%CONDA_PREFIX%\Library\x86_64-w64-mingw32\bin\windres.exe"
    if not exist "!WINDRES_CMD!" (
        echo ERROR: windres.exe not found
        exit /b 1
    )
)

REM Detect preprocessor from CC or environment
set "PREPROC_CMD="
set "PREPROC_ARGS="

if defined CC (
    set "PREPROC_CMD=%CC%"
    REM Detect compiler type and set appropriate args
    echo %CC% | find /i "gcc" 2>nul >nul && (
        set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    )
    echo %CC% | find /i "clang" 2>nul >nul && (
        set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    )
    echo %CC% | find /i "cl.exe" 2>nul >nul && (
        set "PREPROC_ARGS=/EP /TC"
    )
)

REM Build clean arguments list, filtering out malformed --preprocessor
set "CLEAN_ARGS="

:parse_loop
if "%~1"=="" goto :done_parsing

REM Skip any --preprocessor argument (we'll add our own)
set "ARG=%~1"
echo !ARG! | find "--preprocessor" 2>nul >nul
if !errorlevel! == 0 (
    REM Skip this malformed argument
    shift
    goto :parse_loop
)

REM Keep all other arguments
set "CLEAN_ARGS=!CLEAN_ARGS! %~1"
shift
goto :parse_loop

:done_parsing

REM Build final windres command with proper preprocessor
if defined PREPROC_CMD (
    set "FINAL_ARGS=--preprocessor=!PREPROC_CMD!"

    REM Add each preprocessor argument separately
    for %%a in (!PREPROC_ARGS!) do (
        set "FINAL_ARGS=!FINAL_ARGS! --preprocessor-arg=%%a"
    )

    REM Add the cleaned arguments
    set "FINAL_ARGS=!FINAL_ARGS! !CLEAN_ARGS!"
) else (
    REM No preprocessor specified, just use cleaned args
    set "FINAL_ARGS=!CLEAN_ARGS!"
)

REM Execute windres with corrected arguments
%WINDRES_CMD% !FINAL_ARGS!
exit /b %errorlevel%
