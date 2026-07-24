# create-shortcut.ps1 — puts a ChatterFix shortcut on the desktop.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'ChatterFix.exe'
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut((Join-Path $desktop 'ChatterFix.lnk'))
$sc.TargetPath = $exe
$sc.WorkingDirectory = $PSScriptRoot
$sc.IconLocation = "$exe,0"
$sc.Description = 'ChatterFix - keyboard chatter filter'
$sc.Save()
Write-Host "Shortcut created: $(Join-Path $desktop 'ChatterFix.lnk')"
