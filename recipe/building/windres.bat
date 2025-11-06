@echo off
setlocal enabledelayedexpansion

REM Windows CMD script to call windres with appropriate preprocessor
REM Fixes GHC's malformed --preprocessor arguments by parsing and reformatting them

where windres.exe >nul 2>&1
if !errorlevel! == 0 (
    set WINDRES_CMD=windres.exe
) else (
    set WINDRES_CMD=%CONDA_PREFIX%\Library\x86_64-w64-mingw32\bin\windres.exe
    if not exist "!WINDRES_CMD!" (
        echo ERROR: windres.exe not found in PATH or conda environment
        exit /b 1
    )
)

REM Parse arguments from GHC and fix malformed --preprocessor option
set "FIXED_ARGS="
set "FOUND_PREPROCESSOR=0"

:parse_loop
if "%~1"=="" goto :done_parsing

REM Check if this is the malformed --preprocessor argument
echo %~1 | findstr /b /c:"--preprocessor=" >nul
if !errorlevel! == 0 (
    REM Extract the full --preprocessor argument value (may span multiple tokens due to quotes)
    set "PREPROC_ARG=%~1"

    REM Check if the argument contains quotes (malformed format from GHC)
    echo !PREPROC_ARG! | findstr "\"" >nul
    if !errorlevel! == 0 (
        REM Parse malformed format: --preprocessor="cmd" "arg1" "arg2" ...
        REM Extract command (first quoted string)
        for /f "tokens=1* delims==" %%a in ("!PREPROC_ARG!") do (
            set "PREP_VALUE=%%b"
        )

        REM Remove quotes and extract command
        set "PREP_VALUE=!PREP_VALUE:"=!"

        REM Split into command and args
        for /f "tokens=1,*" %%a in ("!PREP_VALUE!") do (
            set "PREP_CMD=%%a"
            set "PREP_ARGS=%%b"
        )

        REM Build proper windres arguments
        set "FIXED_ARGS=!FIXED_ARGS! --preprocessor=!PREP_CMD!"

        REM Add each argument as separate --preprocessor-arg
        for %%a in (!PREP_ARGS!) do (
            set "ARG=%%a"
            set "ARG=!ARG:"=!"
            set "FIXED_ARGS=!FIXED_ARGS! --preprocessor-arg=!ARG!"
        )

        set "FOUND_PREPROCESSOR=1"
    ) else (
        REM Already properly formatted, pass through
        set "FIXED_ARGS=!FIXED_ARGS! %~1"
    )
) else (
    REM Not a preprocessor argument, pass through
    set "FIXED_ARGS=!FIXED_ARGS! %~1"
)

shift
goto :parse_loop

:done_parsing

REM If no preprocessor was specified in arguments, add one based on CC
if !FOUND_PREPROCESSOR! == 0 (
    if defined CC (
        set "FIXED_ARGS=--preprocessor=%CC% !FIXED_ARGS!"
    )
)

REM Call windres with fixed arguments
%WINDRES_CMD% !FIXED_ARGS!
set EXITCODE=!errorlevel!

exit /b !EXITCODE!
