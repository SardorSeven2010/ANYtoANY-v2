; =====================================================================
; ANYtoANY - Windows o'rnatuvchisi (Inno Setup 6)
;
; GitHub Actions'da "flutter build windows" dan keyin avtomatik ishlaydi
; va build/installer/ANYtoANY-Setup.exe faylini yaratadi.
; Qo'lda: ISCC.exe /DAppVersion=1.0.0 installer\anytoany.iss
; =====================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8C2F6A2E-4B1D-4C5E-9E7A-3F1B2D4A5C6E}
AppName=ANYtoANY
AppVersion={#AppVersion}
AppVerName=ANYtoANY {#AppVersion}
AppPublisher=ANYtoANY
DefaultDirName={autopf}\ANYtoANY
DefaultGroupName=ANYtoANY
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=ANYtoANY-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Administrator huquqi bo'lmasa, faqat joriy foydalanuvchi uchun o'rnatishga ruxsat
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\ANYtoANY.exe
UninstallDisplayName=ANYtoANY

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ANYtoANY"; Filename: "{app}\ANYtoANY.exe"
Name: "{autodesktop}\ANYtoANY"; Filename: "{app}\ANYtoANY.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ANYtoANY.exe"; Description: "{cm:LaunchProgram,ANYtoANY}"; Flags: nowait postinstall skipifsilent
