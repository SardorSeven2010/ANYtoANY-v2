; =====================================================================
; CORE - Windows o'rnatuvchisi (Inno Setup 6)
;
; GitHub Actions'da "flutter build windows" dan keyin avtomatik ishlaydi
; va build/installer/CORE-Setup.exe faylini yaratadi.
; Qo'lda: ISCC.exe /DAppVersion=2.0.0 installer\core.iss
; =====================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8C2F6A2E-4B1D-4C5E-9E7A-3F1B2D4A5C6E}
AppName=CORE
AppVersion={#AppVersion}
AppVerName=CORE {#AppVersion}
AppPublisher=CORE
DefaultDirName={autopf}\CORE
DefaultGroupName=CORE
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=CORE-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Administrator huquqi bo'lmasa, faqat joriy foydalanuvchi uchun o'rnatishga ruxsat
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\CORE.exe
SetupIconFile=core.ico
UninstallDisplayName=CORE

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CORE"; Filename: "{app}\CORE.exe"
Name: "{autodesktop}\CORE"; Filename: "{app}\CORE.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\CORE.exe"; Description: "{cm:LaunchProgram,CORE}"; Flags: nowait postinstall skipifsilent
