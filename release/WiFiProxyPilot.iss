#ifndef AppVersion
  #define AppVersion "3.3.0-beta.1"
#endif
#ifndef SourceDir
  #define SourceDir "generated\installer-stage"
#endif
#ifndef OutputPath
  #define OutputPath "dist"
#endif
[Setup]
AppId={{15F7908C-5C54-4D45-9343-1973BFEA3B47}
AppName=WiFi Proxy Pilot
AppVersion={#AppVersion}
AppVerName=WiFi Proxy Pilot {#AppVersion}
AppPublisher=WiFi Proxy Pilot contributors
AppPublisherURL=https://github.com/jeffxuu/WiFiProxyPilot
AppSupportURL=https://github.com/jeffxuu/WiFiProxyPilot/issues
AppUpdatesURL=https://github.com/jeffxuu/WiFiProxyPilot/releases
DefaultDirName={localappdata}\Programs\WiFiProxyPilot
DefaultGroupName=WiFi Proxy Pilot
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupArchitecture=x64
MinVersion=10.0.22000
WizardStyle=modern
LanguageDetectionMethod=uilanguage
ShowLanguageDialog=auto
LicenseFile=..\LICENSE
OutputDir={#OutputPath}
OutputBaseFilename=WiFiProxyPilot-Setup-x64
SetupIconFile=..\src\WiFiProxySwitcher\assets\app.ico
UninstallDisplayName=WiFi Proxy Pilot
UninstallDisplayIcon={app}\WiFiProxyPilot.exe
Uninstallable=yes
UninstallFilesDir={app}
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
UsePreviousLanguage=yes
UsePreviousAppDir=yes
ChangesAssociations=no
ChangesEnvironment=no
SetupLogging=yes

[Languages]
Name: "en_US"; MessagesFile: "compiler:Default.isl"
Name: "zh_CN"; MessagesFile: "installer\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\WiFiProxyPilot.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\*.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\runtimes\*"; DestDir: "{app}\runtimes"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#SourceDir}\en-US\*"; DestDir: "{app}\en-US"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#SourceDir}\zh-CN\*"; DestDir: "{app}\zh-CN"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#SourceDir}\InstallerLifecycle.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\engine\*"; DestDir: "{app}\engine"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\InstallerLifecycle.ps1"; DestDir: "{tmp}\pilot-lifecycle"; Flags: dontcopy
Source: "{#SourceDir}\installer-files.json"; DestDir: "{tmp}\pilot-lifecycle"; Flags: dontcopy
Source: "{#SourceDir}\engine\*"; DestDir: "{tmp}\pilot-lifecycle\engine"; Flags: dontcopy recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\WiFi Proxy Pilot"; Filename: "{app}\WiFiProxyPilot.exe"; WorkingDir: "{app}"; IconFilename: "{app}\WiFiProxyPilot.exe"
Name: "{userdesktop}\WiFi Proxy Pilot"; Filename: "{app}\WiFiProxyPilot.exe"; WorkingDir: "{app}"; IconFilename: "{app}\WiFiProxyPilot.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\WiFiProxyPilot.exe"; Description: "{cm:LaunchProgram,WiFi Proxy Pilot}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\installer-owned.json"
Type: files; Name: "{app}\installer-pending.json"

[CustomMessages]
en_US.SetupFailed=Installation verification failed. No proxy backup was overwritten. See the lifecycle log at %1 and retry Setup.
zh_CN.SetupFailed=安装验证失败。最初的代理备份没有被覆盖。请查看 %1 中的生命周期日志并重试安装。
en_US.Conflict=Windows proxy settings changed after Pilot last wrote them.%n%nYes: restore the configuration saved before first activation.%nNo: keep the current Windows proxy settings.%nCancel: cancel uninstall without changing the running application or watcher.
zh_CN.Conflict=Windows 代理设置已在 Pilot 最后一次写入后被修改。%n%n是：恢复首次启用前保存的配置。%n否：保留当前 Windows 代理设置。%n取消：取消卸载，不改变正在运行的界面或监控。
en_US.RestoreChoice=Restore the Windows manual proxy configuration saved before first activation?%n%nYes: restore original proxy settings.%nNo: keep current proxy settings.%nCancel: leave the application installed.
zh_CN.RestoreChoice=是否恢复首次启用前保存的 Windows 手动代理配置？%n%n是：恢复原始代理配置。%n否：保留当前代理配置。%n取消：保留应用安装，不执行卸载。
en_US.DataChoice=Delete your rules, configuration, original proxy backup and Pilot log files?%n%nYes: delete those known user-data files.%nNo: retain a recoverable copy in %LOCALAPPDATA%\WiFiProxyPilot-Retained.%nCancel: cancel uninstall without changes.%n%nUnknown files and upgrade backups are always preserved.
zh_CN.DataChoice=是否删除您的规则、配置、原始代理备份和 Pilot 日志？%n%n是：删除这些已知的用户数据文件。%n否：在 %LOCALAPPDATA%\WiFiProxyPilot-Retained 中保留可恢复的副本。%n取消：取消卸载，不进行任何更改。%n%n未知文件和升级备份始终保留。
en_US.UninstallFailed=Uninstall stopped because lifecycle verification failed. Application files and the uninstall entry have been preserved for retry. See %1.
zh_CN.UninstallFailed=生命周期验证失败，卸载已停止。程序文件和卸载入口已保留，便于重试。请查看 %1。
en_US.SilentConflict=Silent uninstall requires an explicit /PROXY=restore or /PROXY=keep choice when a restore conflict exists.
zh_CN.SilentConflict=检测到代理恢复冲突。静默卸载必须明确指定 /PROXY=restore 或 /PROXY=keep。

[Code]
var
  LifecycleResult: String;
  UninstallArguments: String;
  ExistingInnoRegistration: Boolean;

function InitializeSetup(): Boolean;
begin
  ExistingInnoRegistration := RegKeyExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{15F7908C-5C54-4D45-9343-1973BFEA3B47}_is1');
  Result := True;
end;

function Quote(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

function RunLifecycle(const Script, Action, Additional: String; var Code: Integer): Boolean;
var
  Parameters: String;
  Json: AnsiString;
  Captured: TExecOutput;
  Index: Integer;
begin
  LifecycleResult := ExpandConstant('{localappdata}\WiFiProxySwitcher-Control\installer-' + Action + '-result.json');
  ForceDirectories(ExtractFileDir(LifecycleResult));
  DeleteFile(LifecycleResult);
  Parameters := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + Quote(Script) +
    ' -Action ' + Action + ' -AppDir ' + Quote(ExpandConstant('{app}')) +
    ' -ResultPath ' + Quote(LifecycleResult) + ' ' + Additional;
  Result := ExecAndCaptureOutputWithNativeSysDir(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Parameters,
    ExtractFileDir(Script), SW_HIDE, ewWaitUntilTerminated, Code, Captured);
  for Index := 0 to GetArrayLength(Captured.StdOut)-1 do begin
    if Index < 32 then Log('Lifecycle stdout: ' + Captured.StdOut[Index]);
  end;
  for Index := 0 to GetArrayLength(Captured.StdErr)-1 do begin
    if Index < 32 then Log('Lifecycle stderr: ' + Captured.StdErr[Index]);
  end;
  if Result then begin
    Result := LoadStringFromFile(LifecycleResult, Json);
    if Result then Log('Lifecycle result: ' + String(Json));
    Result := Result and
      (((Code = 0) and (Pos('"Succeeded":true', Json) > 0)) or
       ((Code = 20) and (Pos('"Code":"RestoreConflict"', Json) > 0)));
  end;
  Log('Lifecycle ' + Action + ': process exit=' + IntToStr(Code) + ', checked result=' + IntToStr(Ord(Result)));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  ExtractTemporaryFiles('{tmp}\pilot-lifecycle\*');
  if not RunLifecycle(ExpandConstant('{tmp}\pilot-lifecycle\InstallerLifecycle.ps1'), 'PrepareInstall', '', Code) or (Code <> 0) then
    Result := FmtMessage(CustomMessage('SetupFailed'), [LifecycleResult])
  else Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
begin
  if CurStep = ssPostInstall then begin
    if not RunLifecycle(ExpandConstant('{app}\InstallerLifecycle.ps1'), 'CommitInstall', '', Code) or (Code <> 0) then begin
      { A failed first migration must not leave a competing installed-app record. The
        SID-bound pending receipt allows a safe retry without overwriting arbitrary files. }
      if not ExistingInnoRegistration then
        RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{15F7908C-5C54-4D45-9343-1973BFEA3B47}_is1');
      RaiseException(FmtMessage(CustomMessage('SetupFailed'), [LifecycleResult]));
    end;
  end;
end;

function InitializeUninstall(): Boolean;
var
  Code, Choice, DataChoice: Integer;
  Proxy, DeleteData, Extra: String;
begin
  Result := False;
  if not RunLifecycle(ExpandConstant('{app}\InstallerLifecycle.ps1'), 'InspectUninstall', '', Code) then begin
    MsgBox(FmtMessage(CustomMessage('UninstallFailed'), [LifecycleResult]), mbError, MB_OK);
    Exit;
  end;
  Proxy := Lowercase(ExpandConstant('{param:PROXY|}'));
  DeleteData := Lowercase(ExpandConstant('{param:DELETEUSERDATA|no}'));
  if UninstallSilent then begin
    if (Code = 20) and (Proxy <> 'restore') and (Proxy <> 'keep') then begin
      Log(CustomMessage('SilentConflict'));
      Exit;
    end;
    if Proxy = '' then Proxy := 'restore';
  end else begin
    if Code = 20 then
      Choice := MsgBox(CustomMessage('Conflict'), mbConfirmation, MB_YESNOCANCEL)
    else Choice := MsgBox(CustomMessage('RestoreChoice'), mbConfirmation, MB_YESNOCANCEL);
    if Choice = IDCANCEL then Exit;
    if Choice = IDYES then Proxy := 'restore' else Proxy := 'keep';
    DataChoice := MsgBox(CustomMessage('DataChoice'), mbConfirmation, MB_YESNOCANCEL);
    if DataChoice = IDCANCEL then Exit;
    if DataChoice = IDYES then DeleteData := 'yes' else DeleteData := 'no';
  end;
  if (Proxy <> 'restore') and (Proxy <> 'keep') then Exit;
  if (DeleteData <> 'yes') and (DeleteData <> 'no') then Exit;
  Extra := '-ProxyChoice ' + Proxy;
  if DeleteData = 'yes' then Extra := Extra + ' -DeleteUserData';
  UninstallArguments := Extra;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Code: Integer;
begin
  { Native final uninstall confirmation happens after InitializeUninstall. Defer every
    mutation until usUninstall, so canceling that native confirmation is also harmless. }
  if CurUninstallStep = usUninstall then begin
    if not RunLifecycle(ExpandConstant('{app}\InstallerLifecycle.ps1'), 'Uninstall', UninstallArguments, Code) or (Code <> 0) then
      RaiseException(FmtMessage(CustomMessage('UninstallFailed'), [LifecycleResult]));
  end;
end;
