; SMPTLOG 通联日志助手 —— Inno Setup 6 安装脚本
;
; 用法（在 SRC/smptlog 目录下）：
;   1. 先执行 flutter build windows --release
;   2. iscc installer\smptlog.iss
; 产物：..\..\EXE\SMPTLOG-Setup-1.1.6.exe
;
; 设计要点：
; - 当前用户安装（PrivilegesRequired=lowest），不需要管理员权限
; - 程序装到 %LOCALAPPDATA%\Programs\SMPTLOG
; - 数据单独放在 %LOCALAPPDATA%\SMPTLOG（与安装目录分离，升级不丢）
; - 卸载前询问是否保留数据，默认保留

#define MyAppName "SMPTLOG 通联日志"
#define MyAppShortName "SMPTLOG"
#define MyAppVersion "1.1.6"
#define MyAppPublisher "SMPTLOG"
#define MyAppExeName "smptlog.exe"

[Setup]
AppId={{8E5C1B36-3D2A-4C8E-9F71-5A2B7C4D9E10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
LicenseFile=..\..\..\LICENSE
DefaultDirName={localappdata}\Programs\{#MyAppShortName}
DefaultGroupName={#MyAppShortName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\EXE
OutputBaseFilename=SMPTLOG-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
AllowNoIcons=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式:"; Flags: checkedonce

[Files]
; Flutter 构建产物整目录复制
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; 许可证与版权归属声明（Apache-2.0 第 4 条要求随二进制分发）
Source: "..\..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\NOTICE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 可选：关联 .adi 文件（双击用 SMPTLOG 打开）
Root: HKCU; Subkey: "Software\Classes\.adi"; ValueType: string; ValueName: ""; ValueData: "SMPTLOG.AdiFile"; Flags: uninsdeletevalue; Tasks: desktopicon
Root: HKCU; Subkey: "Software\Classes\SMPTLOG.AdiFile"; ValueType: string; ValueName: ""; ValueData: "ADIF 通联日志文件"; Flags: uninsdeletekey; Tasks: desktopicon
Root: HKCU; Subkey: "Software\Classes\SMPTLOG.AdiFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
var
  RemoveData: Boolean;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  RemoveData := False;
  if MsgBox('是否同时删除通联日志数据？' + #13#10 + #13#10 +
            '数据目录：%LOCALAPPDATA%\SMPTLOG' + #13#10 +
            '选择“否”将保留全部通联记录、中继台与设置，' +
            '下次安装可继续使用。',
            mbConfirmation, MB_YESNO) = IDYES then
  begin
    if MsgBox('再次确认：删除后无法恢复（除非你另有导出备份）。', mbConfirmation, MB_YESNO) = IDYES then
      RemoveData := True;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if RemoveData then
    begin
      DataDir := ExpandConstant('{localappdata}\SMPTLOG');
      DelTree(DataDir, True, True, True);
    end;
  end;
end;
