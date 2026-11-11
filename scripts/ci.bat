@echo off

setlocal
setlocal enabledelayedexpansion

set DIR=%~dp0
set ROOT=%DIR%..
set BIN=%ROOT%\bin
set FAILED=

where odin >nul 2>nul
if errorlevel 1 (
    echo odin was not found. Put the Odin compiler on the PATH.
    exit /b 1
)

if not exist "%BIN%" mkdir "%BIN%"

pushd "%ROOT%"

echo.
echo == Checking src\GUI
odin check src\GUI -no-entry-point
if errorlevel 1 (
    echo src\GUI did not check.
    set FAILED=src\GUI
    goto fail
)

echo.
echo == Testing src\GUI
set CALCUI_SKIP_BENCH=1
odin test src\GUI
if errorlevel 1 (
    echo The tests of src\GUI did not pass.
    set FAILED=the tests of src\GUI
    goto fail
)

echo.
echo == Building the examples
call :build_examples
if errorlevel 1 (
    echo An example did not build.
    set FAILED=the examples
    goto fail
)

echo.
echo == Checking src\Window
odin check src\Window -no-entry-point
if errorlevel 1 (
    echo src\Window did not check.
    set FAILED=src\Window
    goto fail
)

echo.
echo == Checking src\Backend
odin check src\Backend -no-entry-point
if errorlevel 1 (
    echo src\Backend did not check.
    set FAILED=src\Backend
    goto fail
)

echo.
echo == Rendering a picture
odin run tools\shot -- "%BIN%\shot.png"
if errorlevel 1 (
    echo The picture was not written.
    set FAILED=the picture
    goto fail
)
if not exist "%BIN%\shot.png" (
    echo The picture was not written.
    set FAILED=the picture
    goto fail
)
for %%A in ("%BIN%\shot.png") do if %%~zA LSS 1 (
    echo The picture is empty.
    set FAILED=the picture
    goto fail
)

popd
echo.
echo Passed: src\GUI, the tests of src\GUI, the examples, src\Window,
echo src\Backend and the picture in bin\shot.png.
endlocal
exit /b 0

:fail
echo.
echo Failed: %FAILED%
popd
endlocal
exit /b 1

:build_examples
for /d %%D in ("%ROOT%\examples\*") do (
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
exit /b 0
