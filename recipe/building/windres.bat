@echo off
setlocal enabledelayedexpansion

REM Windres wrapper to fix GHC's malformed --preprocessor arguments

REM Find windres
where windres.exe 2>nul 1>nul
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
    set "CC_LOWER=%CC%"

    REM Convert to lowercase for comparison
    for %%i in ("A=a" "B=b" "C=c" "D=d" "E=e" "F=f" "G=g" "H=h" "I=i" "J=j" "K=k" "L=l" "M=m" "N=n" "O=o" "P=p" "Q=q" "R=r" "S=s" "T=t" "U=u" "V=v" "W=w" "X=x" "Y=y" "Z=z") do set "CC_LOWER=!CC_LOWER:%%~i!"

    echo !CC_LOWER! | findstr /C:"gcc" >nul && set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    echo !CC_LOWER! | findstr /C:"clang" >nul && set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"
    echo !CC_LOWER! | findstr /C:"cl.exe" >nul && set "PREPROC_ARGS=/EP /TC"
)

REM Filter out --preprocessor arguments, keep everything else
set "OTHER_ARGS="

:loop
if "%~1"=="" goto :endloop

REM Check if this argument starts with --preprocessor using substring
set "ARG=%~1"
set "CHECK=!ARG:~0,14!"

if "!CHECK!" == "--preprocessor" (
    REM Skip this malformed argument
    shift
    goto :loop
)

REM Keep this argument
set "OTHER_ARGS=!OTHER_ARGS! %1"
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

echo DEBUG: Calling windres with: !FINAL!

REM Execute
!WINDRES_CMD! !FINAL!
exit /b %errorlevel%
