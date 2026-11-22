; Inno Setup script: packs the Windows release folder into ONE installer file (Tesla.org-Setup.exe).
; Built automatically by .github/workflows/build.yml (run from the project root with ISCC).
[Setup]
AppName=Tesla.org
AppVersion=0.1.0
AppPublisher=Tesla.org
DefaultDirName={autopf}\Tesla.org
DefaultGroupName=Tesla.org
OutputDir=..\installer
OutputBaseFilename=Tesla.org-Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\tesla_org.exe
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion createallsubdirs

[Icons]
Name: "{group}\Tesla.org"; Filename: "{app}\tesla_org.exe"
Name: "{autodesktop}\Tesla.org"; Filename: "{app}\tesla_org.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\tesla_org.exe"; Description: "Launch Tesla.org"; Flags: nowait postinstall skipifsilent
