if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; Exit }
Write-Host "Uninstalling Kloc v1.0.0..." -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Kloc.ps1" -or $_.Name -match "Kloc.exe" } | Invoke-CimMethod -MethodName Terminate | Out-Null
$installDir = "C:\Program Files\Detaroxz\Kloc"; $appDataDir = "$env:APPDATA\Detaroxz\Kloc"; $startMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) "Kloc"
if (Test-Path $installDir) { Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $appDataDir) { Remove-Item -Path $appDataDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $startMenuDir) { Remove-Item -Path $startMenuDir -Recurse -Force -ErrorAction SilentlyContinue }
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Kloc" -ErrorAction SilentlyContinue
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "Kloc.lnk"
if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Kloc" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Uninstallation Complete!" -ForegroundColor Green; Start-Sleep -Seconds 2
