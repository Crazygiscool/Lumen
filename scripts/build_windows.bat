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
rem Step 2: Stage FFI DLLs into Flutter lib/ dir
rem -----------------------------------------
echo.
echo === Step 2: Stage FFI DLLs into Flutter lib/ dir ===
if not exist "%UI_DIR%\windows\lib" mkdir "%UI_DIR%\windows\lib"
copy /Y "%ROOT_DIR%\target\release\lumen_core.dll" "%UI_DIR%\windows\lib\lumen_core.dll" >nul
copy /Y "%ROOT_DIR%\target\release\fscore.dll" "%UI_DIR%\windows\lib\fscore.dll" >nul
copy /Y "%ROOT_DIR%\target\release\ublock.dll" "%UI_DIR%\windows\lib\ublock.dll" >nul
echo Staged lumen_core.dll, fscore.dll, ublock.dll

rem -----------------------------------------
rem Step 3: Build Flutter Windows
rem -----------------------------------------
echo.
echo === Step 3: Build Flutter Windows ===
cd "%UI_DIR%"
flutter config --enable-windows-desktop
flutter build windows --release
if %errorlevel% neq 0 (
    echo ERROR: Flutter build failed.
    exit /b 1
)
cd "%ROOT_DIR%"

rem -----------------------------------------
rem Step 4: Package
rem -----------------------------------------
echo.
echo === Step 4: Packaging ===
set BUNDLE_DIR=%UI_DIR%\build\windows\x64\runner\Release
set ZIP_NAME=Lumen-windows-v%VERSION%.zip

if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

rem Copy TUI into bundle
copy /Y "%ROOT_DIR%\target\release\lumen.exe" "%BUNDLE_DIR%\lumen-cli.exe" >nul
echo Bundled lumen-cli.exe

rem Zip the bundle
cd "%BUNDLE_DIR%"
powershell -Command "Compress-Archive -Path '.\*' -DestinationPath '%DIST_DIR%\%ZIP_NAME%' -Force"
cd "%ROOT_DIR%"

rem -----------------------------------------
rem Step 5: Build installer
rem -----------------------------------------
echo.
echo === Step 5: Build Installer ===
set ISCC="%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if exist %ISCC% (
    %ISCC% /DAPP_VERSION=%VERSION% /DBUNDLE_DIR="%BUNDLE_DIR%" "%~dp0lumen.iss"
    if !errorlevel! neq 0 (
        echo ERROR: Installer build failed.
        exit /b 1
    )
    echo Installer: %DIST_DIR%\Lumen-windows-v%VERSION%-setup.exe
) else (
    echo SKIPPED: Inno Setup not found at %ISCC%
    echo Install with: winget install JRSoftware.InnoSetup
)

echo.
echo === DONE ===
