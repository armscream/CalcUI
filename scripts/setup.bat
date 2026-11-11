@echo off
rem Prepares a working copy of CalcUI.
rem
rem   scripts\setup.bat
rem
rem The Runa text engine is a submodule, so it has to be fetched before
rem anything can be built. The Odin compiler has to be on the PATH.

setlocal
setlocal enabledelayedexpansion

set DIR=%~dp0
set ROOT=%DIR%..

echo Fetching the submodules...
git -C "%ROOT%" submodule update --init --recursive
if errorlevel 1 (
    echo The submodules could not be fetched.
    exit /b 1
)

where odin >nul 2>nul
if errorlevel 1 (
    echo odin was not found. Put the Odin compiler on the PATH.
    exit /b 1
)

echo The compiler is:
odin version

echo The submodules are at:
git -C "%ROOT%" submodule status

endlocal
