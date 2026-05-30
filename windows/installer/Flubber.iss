; Inno Setup script — instalador de Flubber para Windows.
; Genera Flubber-Setup.exe con desinstalador (aparece en "Agregar o quitar programas"),
; reinstalación/reparación al re-ejecutar, accesos directos y opción de inicio con Windows.
;
; Compilar:  ISCC.exe /DAppSrc="<ruta a publish>" /DOutDir="<carpeta salida>" Flubber.iss
; (sin /D usa los valores por defecto de abajo, relativos a este .iss)

#ifndef AppSrc
  #define AppSrc "..\..\publish"
#endif
#ifndef OutDir
  #define OutDir "."
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Flubber"
#define AppExe "Flubber.exe"
#define AppPublisher "Cristian Garcia"
#define AppUrl "https://github.com/lordmacu/flubber-ai-companion"

[Setup]
; AppId fija => permite actualizar/reparar/desinstalar correctamente entre versiones.
AppId={{60528B81-68B7-4EC6-8EA2-5378C1BC529A}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
; Instalación por-usuario (sin admin): evita UAC y SmartScreen de instalador sin firmar.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=Flubber-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "Iniciar Flubber al encender Windows"; GroupDescription: "Inicio:"

[Files]
Source: "{#AppSrc}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Inicio con Windows (solo si se elige la tarea "startup"). Per-usuario.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; \
  ValueType: string; ValueName: "Flubber"; ValueData: """{app}\{#AppExe}"""; \
  Flags: uninsdeletevalue; Tasks: startup

[Run]
; Lanzar Flubber al terminar la instalación.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Limpieza opcional de datos del usuario al desinstalar (state/config/conversaciones).
; Comentado por defecto para no borrar datos sin avisar; descomentar si se quiere borrado total.
; Type: filesandordirs; Name: "{userappdata}\SlimePet"
