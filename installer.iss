#ifndef AppVer
  #define AppVer "1.0.0"
#endif

[Setup]
AppId={{2b5aac8c-6768-46ca-9515-e199683ec259}
AppName=Tachyon
AppVersion={#AppVer}
AppVerName=Tachyon {#AppVer}
AppPublisher=Chomusuke
AppPublisherURL=https://github.com/chomusuke-mk/tachyon
AppSupportURL=https://github.com/chomusuke-mk/tachyon/issues
AppUpdatesURL=https://github.com/chomusuke-mk/tachyon/releases
AppContact=7k9mc4urn@mozmail.com
AppComments=Ultra-fast, lightweight modern music player with continuous crossfade and advanced DSP audio effects.
AppCopyright=Copyright (c) 2026 Chomusuke
AppReadmeFile=README.md

DefaultDirName={localappdata}\Programs\Tachyon
DefaultGroupName=Tachyon
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableDirPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
OutputDir=dist
OutputBaseFilename=tachyon-windows
SetupIconFile=windows\runner\resources\app_icon.ico
WizardStyle=modern
LicenseFile=LICENSE
InfoBeforeFile=third_party_licenses\THIRD_PARTY_LICENSES.txt
UninstallDisplayIcon={app}\tachyon.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DirExistsWarning=no
UsePreviousAppDir=yes
UsePreviousTasks=yes
Compression=lzma2/ultra64
SolidCompression=yes
RestartIfNeededByRun=no
CloseApplications=force
CloseApplicationsFilter=tachyon.exe
SetupLogging=yes
ChangesAssociations=no
VersionInfoVersion={#AppVer}.0
VersionInfoCompany=Chomusuke
VersionInfoDescription=Tachyon Installer
VersionInfoProductName=Tachyon
VersionInfoProductVersion={#AppVer}
SetupMutex=SetupMutex{#SetupSetting("AppId")}

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Tachyon"; Filename: "{app}\tachyon.exe"; IconFilename: "{app}\tachyon.exe"
Name: "{userdesktop}\Tachyon"; Filename: "{app}\tachyon.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create desktop icon"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
Filename: "{app}\tachyon.exe"; Description: "Launch Tachyon"; Flags: nowait postinstall skipifsilent