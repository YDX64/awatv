; Inno Setup script for AWAtv (Windows desktop installer)
;
; Compiles to dist\awatv-setup.exe — a self-contained installer that:
;   * extracts the Flutter Release output to %ProgramFiles%\AWAtv\
;   * adds Start Menu and Desktop shortcuts
;   * registers an uninstaller in Add/Remove Programs
;   * offers to launch AWAtv on completion
;
; Build with:    iscc.exe apps\mobile\windows\installer.iss
; Built by:      scripts\package-windows.ps1 (when iscc is on PATH)
;
; If you rename the Flutter project (changing pubspec.yaml's `name:`), update
; the .exe filename below — Flutter emits "<pubspec_name>.exe".

#define MyAppName        "AWAtv"
#define MyAppVersion     "0.2.0"
#define MyAppPublisher   "AWA Digital Interactive"
#define MyAppURL         "https://awatv.app"
#define MyAppExeName     "awatv_mobile.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4789-9012-AABBCCDDEEFF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\..\dist
OutputBaseFilename=awatv-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
PrivilegesRequired=admin
UninstallDisplayName={#MyAppName} {#MyAppVersion}
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Recursively copy the entire Flutter Release output (exe + DLLs + data dir).
Source: "..\..\..\apps\mobile\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; \
    Description: "{cm:LaunchProgram,{#MyAppName}}"; \
    Flags: nowait postinstall skipifsilent
