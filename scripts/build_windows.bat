@echo off
setlocal enabledelayedexpansion

rem -----------------------------------------
rem CONFIG
rem -----------------------------------------
set ROOT_DIR=%~dp0..
set UI_DIR=%ROOT_DIR%\ui
set DIST_DIR=%ROOT_DIR%\dist
set TARGET=x86_64-pc-windows-msvc

rem Extract version from pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr /r "^version:" "%UI_DIR%\pubspec.yaml"') do (
    set VERSION=%%a
)

echo === Lumen Windows Build ===
echo Root:    %ROOT_DIR%
echo UI:      %UI_DIR%
echo Dist:    %DIST_DIR%
echo Version: %VERSION%

rem -----------------------------------------
rem Step 1: Build Rust workspace
rem -----------------------------------------
echo.
echo === Step 1: Build Rust Workspace ===
cargo build --release --locked
if %errorlevel% neq 0 (
    echo ERROR: Rust build failed.
    exit /b 1
)

rem -----------------------------------------
rem Step 2: Build Flutter Windows
rem -----------------------------------------
echo.
echo === Step 2: Build Flutter Windows ===
cd "%UI_DIR%"
flutter config --enable-windows-desktop
flutter build windows --release
if %errorlevel% neq 0 (
    echo ERROR: Flutter build failed.
    exit /b 1
)
cd "%ROOT_DIR%"

rem -----------------------------------------
rem Step 3: Package
rem -----------------------------------------
echo.
echo === Step 3: Packaging ===
set BUNDLE_DIR=%UI_DIR%\build\windows\runner\release
set ZIP_NAME=Lumen-windows-v%VERSION%.zip

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

rem Copy TUI into bundle
copy /Y "%ROOT_DIR%\target\release\lumen.exe" "%BUNDLE_DIR%\lumen-cli.exe" >nul
echo Bundled lumen-cli.exe

rem Zip the bundle
cd "%BUNDLE_DIR%"
powershell -Command "Compress-Archive -Path '.\*' -DestinationPath '%DIST_DIR%\%ZIP_NAME%' -Force"
cd "%ROOT_DIR%"

echo.
echo === DONE ===
echo Bundle: %BUNDLE_DIR%
echo Archive: %DIST_DIR%\%ZIP_NAME%
