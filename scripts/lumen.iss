; Inno Setup script for Lumen
; Compile with: ISCC /DAPP_VERSION=x.y.z /DBUNDLE_DIR=path lumen.iss

#ifndef APP_VERSION
  #define APP_VERSION "0.0.0-dev"
#endif

#ifndef BUNDLE_DIR
  #error "BUNDLE_DIR must be set (path to Flutter release bundle)"
#endif

[Setup]
AppId={{B8A3C2E1-7F4D-4E6A-9C1B-3D5E8F2A1B0C}
AppName=Lumen
AppVersion={#APP_VERSION}
AppPublisher=Lumen
DefaultDirName={autopf}\Lumen
DefaultGroupName=Lumen
OutputDir=..\dist
OutputBaseFilename=Lumen-windows-v{#APP_VERSION}-setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
; Let the user choose whether to install for all users or just the current
; user. {autopf} and {autodesktop} automatically resolve to the per-machine or
; per-user location based on the chosen mode.
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=..\ui\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lumen.exe
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenu"; Description: "Create a Lumen group in the Start Menu"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter GUI
Source: "{#BUNDLE_DIR}\lumen.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BUNDLE_DIR}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
; Rust FFI core library
Source: "{#BUNDLE_DIR}\lib\lumen_core.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#BUNDLE_DIR}\lib\fscore.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#BUNDLE_DIR}\lib\ublock.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
; Rust TUI CLI
Source: "{#BUNDLE_DIR}\lumen-cli.exe"; DestDir: "{app}"; Flags: ignoreversion
; Flutter data directory
Source: "{#BUNDLE_DIR}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Lumen"; Filename: "{app}\lumen.exe"; Comment: "Launch Lumen"; Tasks: startmenu
Name: "{group}\Lumen CLI"; Filename: "{cmd}"; Parameters: "/K ""{app}\lumen-cli.exe"" interactive"; Comment: "Open Lumen terminal interface"; Tasks: startmenu
Name: "{group}\Uninstall Lumen"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Lumen"; Filename: "{app}\lumen.exe"; Comment: "Launch Lumen"; Tasks: desktopicon

[Run]
Filename: "{app}\lumen.exe"; Description: "Launch Lumen"; Flags: nowait postinstall skipifsilent
