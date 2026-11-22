; Inno Setup script: makes CyberNeonPlayer-Setup.exe (no admin rights needed)
#define AppName "CyberNeon Player"
#define AppExe "CyberNeonPlayer.exe"

[Setup]
AppId={{6F1D2B7E-4C3A-4E6B-9A57-C1B0A9E5D3F4}
AppName={#AppName}
AppVersion=1.0
AppPublisher=CyberNeon
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=CyberNeonPlayer-Setup
SetupIconFile=cyberneon-player.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "autostart"; Description: "Start in the background (tray) when I log in"; Flags: unchecked

[Files]
Source: "..\dist\CyberNeonPlayer\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Parameters: "--background"; Tasks: autostart

[Run]
Filename: "{app}\{#AppExe}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent
