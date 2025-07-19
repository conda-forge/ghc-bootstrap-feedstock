@echo off
setlocal enabledelayedexpansion

REM Windows CMD script to call windres with appropriate preprocessor
REM Based on CC variable or by searching for available compilers

echo Windres wrapper - detecting C compiler...

set WINDRES_CMD=%CONDA_PREFIX%\Library\x86_64-w64-mingw32\bin\windres.exe
set PREPROCESSOR_CMD=
set PREPROCESSOR_ARGS=

REM Check if CC variable is set
if defined CC (
    echo CC is set to: %CC%

    REM Check what type of compiler CC points to
    echo %CC% | findstr /i "clang" >nul
    if !errorlevel! == 0 (
        echo Detected Clang compiler
        set PREPROCESSOR_CMD=%CC%
        set PREPROCESSOR_ARGS=-E -xc-header -DRC_INVOKED
        goto :run_windres
    )

    echo %CC% | findstr /i "gcc" >nul
    if !errorlevel! == 0 (
        echo Detected GCC compiler
        set PREPROCESSOR_CMD=%CC%
        set PREPROCESSOR_ARGS=-E -xc-header -DRC_INVOKED
        goto :run_windres
    )

    echo %CC% | findstr /i "cl.exe" >nul
    if !errorlevel! == 0 (
        echo Detected MSVC compiler
        set PREPROCESSOR_CMD=%CC%
        set PREPROCESSOR_ARGS=/EP /TC
        goto :run_windres
    )

    REM If CC is set but we couldn't identify it, try to use it anyway
    echo Unknown compiler type, trying as generic preprocessor
    set PREPROCESSOR_CMD=%CC%
    set PREPROCESSOR_ARGS=-E
    goto :run_windres
)

REM CC not set, search for available compilers
echo CC not set, searching for available compilers...

REM Try to find Clang
where clang.exe >nul 2>&1
if !errorlevel! == 0 (
    echo Found Clang
    set PREPROCESSOR_CMD=clang.exe
    set PREPROCESSOR_ARGS=-E -xc-header -DRC_INVOKED
    goto :run_windres
)

REM Try to find GCC first
where gcc.exe >nul 2>&1
if !errorlevel! == 0 (
    echo Found GCC
    set PREPROCESSOR_CMD=gcc.exe
    set PREPROCESSOR_ARGS=-E -xc-header -DRC_INVOKED
    goto :run_windres
)

REM Try to find MSVC
where cl.exe >nul 2>&1
if !errorlevel! == 0 (
    echo Found MSVC cl.exe
    set PREPROCESSOR_CMD=cl.exe
    set PREPROCESSOR_ARGS=/EP /TC
    goto :run_windres
)

REM If no compiler found, try windres without explicit preprocessor
echo No C compiler found, trying windres with default settings
goto :run_windres_default

:run_windres
echo Using preprocessor: %PREPROCESSOR_CMD% %PREPROCESSOR_ARGS%

REM Set environment variables for windres
set CC=%PREPROCESSOR_CMD%
set CPP=%PREPROCESSOR_CMD% %PREPROCESSOR_ARGS%

REM Call windres with explicit preprocessor
%WINDRES_CMD% --preprocessor="%PREPROCESSOR_CMD% %PREPROCESSOR_ARGS%" %*
goto :end

:run_windres_default
echo Calling windres with default preprocessor
%WINDRES_CMD% %*
goto :end

:end
if !errorlevel! neq 0 (
    echo Windres failed with exit code !errorlevel!
    exit /b !errorlevel!
)

echo Windres completed successfully
exit /b 0
