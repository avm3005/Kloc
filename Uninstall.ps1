if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs; Exit }

Add-Type -AssemblyName System.Windows.Forms

$appDataDir = "$env:APPDATA\Detaroxz\Kloc"
$keepData = $true
if (Test-Path $appDataDir) {
    $ans = [System.Windows.Forms.MessageBox]::Show("Do you want to remove your saved settings and presets?", "Kloc Uninstaller", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { $keepData = $false }
}

Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Kloc.ps1" -or $_.Name -match "Kloc.exe" } | Invoke-CimMethod -MethodName Terminate | Out-Null
Start-Sleep -Seconds 1

$installDir = "C:\Program Files\Detaroxz\Kloc"
$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')

$mainShortcutPath = Join-Path $commonPrograms "Kloc.lnk"
if (Test-Path $mainShortcutPath) { Remove-Item $mainShortcutPath -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Kloc" -ErrorAction SilentlyContinue
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "Kloc.lnk"
if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName "KlocDesktopClock" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Kloc" -Recurse -Force -ErrorAction SilentlyContinue

if (-not $keepData) {
    if (Test-Path $appDataDir) { Remove-Item -Path $appDataDir -Recurse -Force -ErrorAction SilentlyContinue }
}

[System.Windows.Forms.MessageBox]::Show("Uninstallation Complete!", "Kloc", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

Start-Process cmd.exe -ArgumentList "/c ping 127.0.0.1 -n 4 > nul & rmdir /s /q `"$installDir`"" -WindowStyle Hidden
Exit
