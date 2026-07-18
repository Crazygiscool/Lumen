@echo off
setlocal enabledelayedexpansion

rem -----------------------------------------
rem CONFIG
rem -----------------------------------------
set CORE_DIR=core
set UI_DIR=ui
set LIB_NAME=lumen_core.dll
set TARGET_LIB=target\release\%LIB_NAME%

rem Flutter bundle output directory (debug)
set FLUTTER_BUNDLE_DIR=%UI_DIR%\build\windows\x64\debug\bundle

rem -----------------------------------------
rem STEP 0 — Parse arguments
rem -----------------------------------------
set DEV_MODE=false
set TUI_MODE=false

:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--dev" set DEV_MODE=true
if "%~1"=="--tui" set TUI_MODE=true
shift
goto parse_args
:done_args

rem -----------------------------------------
rem STEP 1 — Build Rust backend
rem -----------------------------------------
echo Building Rust backend...
cd %CORE_DIR%
cargo build --release
if %errorlevel% neq 0 (
    echo ERROR: Rust build failed.
    exit /b 1
)
cd ..

rem -----------------------------------------
rem STEP 2 — Ensure shared library is linked
rem -----------------------------------------
if not exist "%TARGET_LIB%" (
    echo ERROR: %TARGET_LIB% does not exist.
    echo Make sure your Cargo.toml has:
    echo [lib]
    echo crate-type = ["cdylib"]
    exit /b 1
)

echo Linking shared library...
rem Copy to ui/windows/lib/ so CMake picks it up during flutter build
if not exist "%UI_DIR%\windows\lib" mkdir "%UI_DIR%\windows\lib"
copy /Y "%TARGET_LIB%" "%UI_DIR%\windows\lib\%LIB_NAME%" >nul
echo Updated: %UI_DIR%\windows\lib\%LIB_NAME%

rem -----------------------------------------
rem EXECUTION
rem -----------------------------------------
if "%DEV_MODE%"=="true" (
    echo Dev mode enabled — running with flutter run (DDS + hot reload)
    cd %UI_DIR%
    flutter config --enable-windows-desktop
    flutter run
    cd ..
) else (
    echo Building Flutter bundle...
    cd %UI_DIR%
    flutter config --enable-windows-desktop
    flutter build windows --debug
    cd ..

    rem Copy DLL into the bundle directory
    if not exist "%FLUTTER_BUNDLE_DIR%" mkdir "%FLUTTER_BUNDLE_DIR%"
    copy /Y "%TARGET_LIB%" "%FLUTTER_BUNDLE_DIR%\%LIB_NAME%" >nul
    echo Updated: %FLUTTER_BUNDLE_DIR%\%LIB_NAME%

    echo Running Lumen from bundle...
    "%FLUTTER_BUNDLE_DIR%\Lumen.exe"
)

rem -----------------------------------------
rem STEP 5 — Optional: Run Rust TUI backend AFTER UI closes
rem -----------------------------------------
if "%TUI_MODE%"=="true" (
    echo Running Rust TUI...
    cargo run --bin lumen
)

echo Done.
endlocal
