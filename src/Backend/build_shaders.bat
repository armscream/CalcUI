@echo off
rem Builds the SPIR-V the GPU backend loads.
rem
rem The shaders are compiled with glslc, which comes with the Vulkan
rem SDK. The compiled files are kept in the repository, so a build of
rem CalcUI does not need the SDK; run this script after every change
rem of ui.vert or ui.frag.
rem
rem   build_shaders.bat
rem
rem On Linux and macOS the same thing is done by build_shaders.sh.

setlocal

set DIR=%~dp0
set GLSLC=glslc

where %GLSLC% >nul 2>nul
if errorlevel 1 (
    echo glslc was not found. It comes with the Vulkan SDK.
    echo Add the Bin directory of the SDK to the PATH and run this again.
    exit /b 1
)

echo Building ui.spv.vert
%GLSLC% -fshader-stage=vertex "%DIR%ui.vert" -o "%DIR%ui.spv.vert"
if errorlevel 1 exit /b 1

echo Building ui.spv.frag
%GLSLC% -fshader-stage=fragment "%DIR%ui.frag" -o "%DIR%ui.spv.frag"
if errorlevel 1 exit /b 1

echo Done.
endlocal
