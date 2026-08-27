Option Explicit

Dim shell, fileSystem, scriptFolder, launcherPath, command, index, argument

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptFolder = fileSystem.GetParentFolderName(WScript.ScriptFullName)
launcherPath = fileSystem.BuildPath(scriptFolder, "DiscordLauncher.bat")
command = Chr(34) & launcherPath & Chr(34)

For index = 0 To WScript.Arguments.Count - 1
    argument = Replace(WScript.Arguments(index), Chr(34), Chr(34) & Chr(34))
    command = command & " " & Chr(34) & argument & Chr(34)
Next

shell.Run command, 0, False

Set fileSystem = Nothing
Set shell = Nothing
