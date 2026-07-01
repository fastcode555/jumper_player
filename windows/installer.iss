; Inno Setup script — builds a Windows installer (setup .exe) for Jump Player.
; Compiled in CI: ISCC.exe /DAppVersion=<version> /O"installer" windows\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define MyAppName "Jump Player"
#define MyAppExeName "jump_player.exe"

[Setup]
; Stable AppId so future versions upgrade in place instead of installing twice.
AppId={{8F3B1E2A-9C4D-4E6F-A1B2-7C8D9E0F1A2B}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher=fastcode555
DefaultDirName={autopf}\JumpPlayer
DisableProgramGroupPage=yes
OutputBaseFilename=jump_player-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式 (Create a desktop shortcut)"; GroupDescription: "附加任务 (Additional tasks):"

[Files]
Source: "{#SourcePath}\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName} (Launch now)"; Flags: nowait postinstall skipifsilent
