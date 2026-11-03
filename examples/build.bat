@echo off
rem Builds every example.
rem
rem   examples\build.bat
rem
rem The examples are built into the bin directory of the repository, so
rem that they can be started from one place. On Linux and macOS the
rem same thing is done by build.sh.

setlocal
setlocal enabledelayedexpansion

set DIR=%~dp0
set ROOT=%DIR%..
set BIN=%ROOT%\bin

if not exist "%BIN%" mkdir "%BIN%"

where odin >nul 2>nul
if errorlevel 1 (
    echo odin was not found. Put the Odin compiler on the PATH.
    exit /b 1
)

for %%D in ("%DIR%*") do (
    if exist "%%D\main.odin" (
        set NAME=%%~nxD
        echo Building !NAME!
        odin build "%%D" -out:"%BIN%\!NAME!.exe"
        if errorlevel 1 (
            echo !NAME! did not build.
            exit /b 1
        )
    )
)

echo Done. The programs are in %BIN%.
endlocal
