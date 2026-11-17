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
echo == Checking src\NodeGraph
odin check src\NodeGraph -no-entry-point
if errorlevel 1 (
    echo src\NodeGraph did not check.
    set FAILED=src\NodeGraph
    goto fail
)

echo.
echo == Checking src\Tests
odin check src\Tests -no-entry-point
if errorlevel 1 (
    echo src\Tests did not check.
    set FAILED=src\Tests
    goto fail
)

echo.
echo == Testing src\Tests
set CALCUI_BENCH_BUDGET=0
set CALCUI_BENCH_OUTPUT=docs\other\internalbenchmarks.md
set CALCUI_BENCH_BUILD=minimal
odin test src\Tests -define:ODIN_TEST_THREADS=1
if errorlevel 1 (
    echo The tests of src\Tests did not pass.
    set FAILED=the tests of src\Tests
    goto fail
)

echo.
echo == Testing examples\09_node_graph\blueprint
odin test examples\09_node_graph\blueprint -define:ODIN_TEST_THREADS=1
if errorlevel 1 (
    echo The blueprint tests did not pass.
    set FAILED=the blueprint tests
    goto fail
)

echo.
echo == Testing examples\09_node_graph
odin test examples\09_node_graph -define:ODIN_TEST_THREADS=1
if errorlevel 1 (
    echo The node graph example tests did not pass.
    set FAILED=the node graph example tests
    goto fail
)

echo.
echo == Checking examples\09_node_graph\features
odin check examples\09_node_graph\features -no-entry-point
if errorlevel 1 (
    echo The node graph feature packages did not check.
    set FAILED=the node graph feature packages
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

echo.
echo == Rendering the node graph picture
odin run tools\shot_node_graph -- "%BIN%\shot_node_graph.png"
if errorlevel 1 (
    echo The node graph picture was not written.
    set FAILED=the node graph picture
    goto fail
)
if not exist "%BIN%\shot_node_graph.png" (
    echo The node graph picture was not written.
    set FAILED=the node graph picture
    goto fail
)
for %%A in ("%BIN%\shot_node_graph.png") do if %%~zA LSS 1 (
    echo The node graph picture is empty.
    set FAILED=the node graph picture
    goto fail
)

echo.
echo == Rendering the SDF picture and checking its pixels
odin run tools\shot_sdf -- "%BIN%\shot_sdf.ppm"
if errorlevel 1 (
    echo The SDF picture was not written.
    set FAILED=the SDF picture
    goto fail
)
if not exist "%BIN%\shot_sdf.ppm" (
    echo The SDF picture was not written.
    set FAILED=the SDF picture
    goto fail
)
for %%A in ("%BIN%\shot_sdf.ppm") do if %%~zA LSS 1 (
    echo The SDF picture is empty.
    set FAILED=the SDF picture
    goto fail
)

odin run tools\shot_sdf -- verify
if errorlevel 1 (
    echo The SDF pixel checks did not pass.
    set FAILED=the SDF pixel checks
    goto fail
)

odin run tools\shot_sdf -- parity
if errorlevel 1 (
    echo The SDF parity check did not pass.
    set FAILED=the SDF parity check
    goto fail
)

popd
echo.
echo Passed: src\NodeGraph, src\GUI, src\Tests, the blueprint tests,
echo the examples, src\Window, src\Backend and the three pictures.
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
