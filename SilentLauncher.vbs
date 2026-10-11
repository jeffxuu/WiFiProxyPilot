Option Explicit
Dim shell, fso, root, action, exe, command, result, script
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
action = "Start"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0)
Select Case LCase(action)
    Case "watch", "install", "start", "stop", "uninstall", "restore", "status"
    Case Else
        WScript.Quit 2
End Select
exe = shell.ExpandEnvironmentStrings("%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe")
If Not fso.FileExists(exe) Then exe = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
shell.CurrentDirectory = root
If LCase(action) = "watch" Then
    script = fso.BuildPath(root, "ProxyWatcher.ps1")
    command = Quote(exe) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(script)
Else
    script = fso.BuildPath(root, "Control.ps1")
    command = Quote(exe) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(script) & " -Action " & action & " -Quiet"
End If
' Wait=True lets Task Scheduler observe the real watcher exit code and restart failures.
result = shell.Run(command, 0, True)
WScript.Quit result
Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
