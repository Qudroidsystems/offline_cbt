; Inno Setup script — builds OfflineCBT-Setup-<version>.exe
; One installer for every computer (exam server and student computers);
; the role is chosen the first time the app opens.
; Build with installer\build_windows.ps1 (needs Flutter + Inno Setup 6).

#define AppName "Offline CBT"
#ifndef AppVersion
  #define AppVersion "1.0.0"   ; build_windows.ps1 passes the version from pubspec.yaml
#endif
#define AppExe "offline_cbt.exe"

[Setup]
AppId={{6F1A4C2E-7B7D-4E59-9C61-0FA2C1B0CB7E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Qudroid Systems
DefaultDirName={autopf}\OfflineCBT
DefaultGroupName={#AppName}
OutputDir=..\dist
OutputBaseFilename=OfflineCBT-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
SetupIconFile=assets\app_icon.ico
WizardImageFile=assets\wizard_large.bmp
WizardSmallImageFile=assets\wizard_small.bmp
UninstallDisplayIcon={app}\{#AppExe}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} installer
; Keep data (exams, answers, backups in %APPDATA%\OfflineCBT) when upgrading or uninstalling
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
; Everything Flutter puts in build\windows\x64\runner\Release (exe, DLLs incl. sqlite3.dll, data\)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Let student computers reach the exam server over Wi-Fi (TCP 47810 = exams, UDP 47811 = auto-discovery).
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Offline CBT"""; Flags: runhidden waituntilterminated
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Offline CBT"" dir=in action=allow program=""{app}\{#AppExe}"" enable=yes profile=any"; Flags: runhidden waituntilterminated
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Offline CBT"" dir=in action=allow protocol=TCP localport=47810 profile=any"; Flags: runhidden waituntilterminated
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""Offline CBT"" dir=in action=allow protocol=UDP localport=47811 profile=any"; Flags: runhidden waituntilterminated
Filename: "{app}\{#AppExe}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""Offline CBT"""; Flags: runhidden; RunOnceId: "fw"
