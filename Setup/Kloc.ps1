# Install-Kloc.ps1 - Single-File Setup for Kloc Desktop Clock v1.0.3

# --- 1. AUTOMATIC ADMINISTRATOR ELEVATION ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "     Kloc Desktop Clock Installer - v1.0.3       " -ForegroundColor White
Write-Host "=================================================" -ForegroundColor Cyan
Start-Sleep -Seconds 1

# --- 2. PREVIOUS INSTALLATION DETECTION & SETTINGS MIGRATION ---
$appDataFolder = "$env:APPDATA\Detaroxz\Kloc"
$settingsFile = "$appDataFolder\settings.json"
$existingSettings = $null

if (Test-Path $settingsFile) {
    Write-Host "[*] Previous settings detected. Backing up to memory..." -ForegroundColor Yellow
    $existingSettings = Get-Content $settingsFile -Raw
}

Write-Host "[*] Terminating existing background processes..." -ForegroundColor DarkGray
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Kloc.ps1" -or $_.Name -match "Kloc.exe" } | Invoke-CimMethod -MethodName Terminate | Out-Null

$installDir = "C:\Program Files\Detaroxz\Kloc"
$commonPrograms = [Environment]::GetFolderPath('CommonPrograms')

Write-Host "[*] Cleaning up old application data..." -ForegroundColor DarkGray
if (Test-Path $installDir) { Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue }

$oldMenuDir = Join-Path $commonPrograms "Kloc"
if (Test-Path $oldMenuDir) { Remove-Item -Path $oldMenuDir -Recurse -Force -ErrorAction SilentlyContinue }
$mainShortcutPath = Join-Path $commonPrograms "Kloc.lnk"
if (Test-Path $mainShortcutPath) { Remove-Item $mainShortcutPath -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Kloc" -ErrorAction SilentlyContinue
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "Kloc.lnk"
if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName "KlocDesktopClock" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Kloc" -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path $installDir -ItemType Directory -Force | Out-Null
if (-not (Test-Path $appDataFolder)) { New-Item -Path $appDataFolder -ItemType Directory -Force | Out-Null }

if ($null -ne $existingSettings) {
    Set-Content -Path $settingsFile -Value $existingSettings -Force
    Write-Host "[*] Settings successfully migrated!" -ForegroundColor Green
}

# --- 3. DYNAMICALLY GENERATE THE SVG-BASED .ICO NATIVELY ---
Write-Host "[*] Compiling UI Assets & SVG Icon..." -ForegroundColor Cyan
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(256, 256)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#EFD9A0"))), 12, 12, 210, 210)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#98C4D8"))), 24, 24, 210, 210)
$wPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#FEFEFE"), 18)
$wPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $wPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($wPen, 129, 129, 129, 65)
$g.DrawLine($wPen, 129, 129, 185, 129)

$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $ms.ToArray()
$icoStream = New-Object System.IO.FileStream("$installDir\icon.ico", [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($icoStream)
$bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]1); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([int16]1); $bw.Write([int16]32)
$bw.Write([int32]$pngBytes.Length); $bw.Write([int32]22); $bw.Write($pngBytes)
$bw.Flush(); $icoStream.Dispose(); $ms.Dispose(); $g.Dispose(); $bmp.Dispose()

# --- 4. BUILD THE TASK MANAGER EXECUTABLE & INVISIBLE LAUNCHER ---
Write-Host "[*] Creating Native Background Wrapper & Silencer..." -ForegroundColor Cyan
Copy-Item "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -Destination "$installDir\Kloc.exe" -Force

$launcherVbs = @'
Set ws = CreateObject("WScript.Shell")
ws.Run """C:\Program Files\Detaroxz\Kloc\Kloc.exe"" -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Program Files\Detaroxz\Kloc\Kloc.ps1""", 0, False
'@
Set-Content -Path "$installDir\Invisible.vbs" -Value $launcherVbs -Encoding Ascii

# --- 5. DEFINE THE MAIN CLOCK SCRIPT PAYLOAD ---
Write-Host "[*] Writing Kloc Engine & Layout logic..." -ForegroundColor Cyan
$klocContent = @'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Inject C# for WorkerW Desktop Binding, Window Positioning & Memory Management
$signature = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr FindWindowEx(IntPtr parentHandle, IntPtr childAfter, string className, string windowTitle);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    public static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("kernel32.dll")]
    public static extern bool SetProcessWorkingSetSize(IntPtr proc, int min, int max);

    public static void TrimMemory() {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        try {
            SetProcessWorkingSetSize(Process.GetCurrentProcess().Handle, -1, -1);
        } catch {}
    }
    
    public static void EnforceDesktopPosition(IntPtr hwnd, bool alwaysOnTop) {
        IntPtr HWND_BOTTOM = new IntPtr(1);
        IntPtr HWND_TOPMOST = new IntPtr(-1);
        uint flags = 0x0001 | 0x0002 | 0x0010 | 0x0200; // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER
        if (alwaysOnTop) {
            SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags);
        } else {
            SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, flags);
        }
    }

    public static void BindToDesktop(IntPtr hwnd) {
        IntPtr progman = FindWindow("Progman", null);
        IntPtr result;
        SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0, 1000, out result);
        
        IntPtr workerw = IntPtr.Zero;
        EnumWindows(new EnumWindowsProc((tophandle, topparamhandle) => {
            IntPtr p = FindWindowEx(tophandle, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (p != IntPtr.Zero) {
                workerw = FindWindowEx(IntPtr.Zero, tophandle, "WorkerW", null);
            }
            return true;
        }), IntPtr.Zero);
        
        if (workerw == IntPtr.Zero) { workerw = progman; }
        
        if (IntPtr.Size == 8) {
            SetWindowLongPtr64(hwnd, -8, workerw);
        } else {
            SetWindowLong32(hwnd, -8, workerw.ToInt32());
        }
    }

    public static void UnbindFromDesktop(IntPtr hwnd) {
        if (IntPtr.Size == 8) {
            SetWindowLongPtr64(hwnd, -8, IntPtr.Zero);
        } else {
            SetWindowLong32(hwnd, -8, 0);
        }
    }
}
"@
Add-Type -TypeDefinition $signature -Language CSharp

$mutexCreated = $false
$script:klocMutex = New-Object System.Threading.Mutex($true, "Global\KlocDesktopClock_Mutex", [ref]$mutexCreated)
if (-not $mutexCreated) { Exit }

$appDataFolder = "$env:APPDATA\Detaroxz\Kloc"
$settingsFile = "$appDataFolder\settings.json"
if (-not (Test-Path $appDataFolder)) { New-Item -Path $appDataFolder -ItemType Directory -Force | Out-Null }

$defaultSettings = @{
    FontQuote1 = "Segoe UI"; ClockColor = "#000000"; DateAboveTime = $false; Quote1Italic = $true
    Quote2Bold = $false; SizeTime = 48; SizeQuote1 = 18; ShadowEnabled = $false
    FontQuote2 = "Segoe UI"; DateItalic = $false; Quote1Bold = $false; ColorDay = "#FFFFFF"
    DayItalic = $true; Quote2Italic = $false; Quote1AllCaps = $false; AmPmItalic = $false
    FontTime = "Segoe UI"; SizeQuote2 = 14; LineSpacing = 0; DateAllCaps = $false
    DayAllCaps = $false; ShowDay = $true; LimitOffset = 200; Alignment = "Center"
    SizeDay = 266.40000406901044; ShowBackground = $false; DateBold = $false; ColorDate = "#FFFFFF"
    DateDaySameLine = $false; QuoteSpacing = 10; StartupMethod = "Disabled"; TimeItalic = $false
    PositionMode = "Centered"; TimeBold = $false; ColorQuote1 = "#FFFFFF"; ShowSeconds = $false
    AmPmAllCaps = $false; Quote2AllCaps = $false; UseIndividualColors = $false; ColorAmPm = "#FFFFFF"
    ShowTime = $false; ShowQuote2 = $false; TextOpacity = 100; DayBold = $true
    BgOpacity = 50; AmPmSpacing = 5; FontDate = "Segoe UI"; SizeDate = 20
    FontAmPm = "Segoe UI"; SizeAmPm = 20; IncludeTaskbarInCenter = $false; ShowDate = $false
    AmPmOffsetY = 0; ColorTime = "#FFFFFF"; AmPmBold = $false; FontDay = "Brush Script MT"
    ColorQuote2 = "#FFFFFF"; AlwaysOnTop = $false; TimeAllCaps = $false; ShowAmPm = $true
    LockPosition = $false; LimitSpacing = 50; UseAmPm = $false; BackgroundColor = "#FFFFFF"
    Quote2Text = "Make it count."; Quote1Text = "Stay Focused"; ShowQuote1 = $false; DateDaySpacing = 10
}

function Load-Settings {
    if (Test-Path $settingsFile) {
        try {
            $loaded = Get-Content $settingsFile -Raw | ConvertFrom-Json
            foreach ($key in $defaultSettings.Keys) { if ($null -eq $loaded.$key) { $loaded | Add-Member -MemberType NoteProperty -Name $key -Value $defaultSettings[$key] } }
            return $loaded
        } catch { return $defaultSettings }
    }
    return $defaultSettings
}

function Save-Settings ($SettingsObj) { $SettingsObj | ConvertTo-Json -Depth 2 | Set-Content $settingsFile -Force }
$global:Settings = Load-Settings

$clockXAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Kloc" Background="Transparent" AllowsTransparency="True" WindowStyle="None" 
        SizeToContent="WidthAndHeight" ShowInTaskbar="False" Opacity="0">
    <Grid Name="RootGrid" Background="Transparent">
        <StackPanel Name="MainPanel" Margin="15" Background="Transparent" HorizontalAlignment="Center" VerticalAlignment="Center">
            <StackPanel Name="TimePanel" Orientation="Horizontal" Background="Transparent" VerticalAlignment="Center">
                <TextBlock Name="TimeText" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
                <TextBlock Name="AmPmText" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
            </StackPanel>
            <StackPanel Name="DateDayPanel">
                <TextBlock Name="DateText" Margin="0,0,10,0" Typography.NumeralAlignment="Tabular"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
                <TextBlock Name="DayText" Typography.NumeralAlignment="Tabular"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
            </StackPanel>
            <StackPanel Name="QuotePanel">
                <TextBlock Name="Quote1Text" TextWrapping="Wrap"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
                <TextBlock Name="Quote2Text" TextWrapping="Wrap" Margin="0,5,0,0"><TextBlock.Effect><DropShadowEffect Color="Black" BlurRadius="5" ShadowDepth="2" Opacity="0.8"/></TextBlock.Effect></TextBlock>
            </StackPanel>
        </StackPanel>
    </Grid>
</Window>
"@
$stringReader = New-Object System.IO.StringReader($clockXAML)
$xmlReader = [System.Xml.XmlReader]::Create($stringReader)
$window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
$xmlReader.Close()
$stringReader.Dispose()

$RootGrid = $window.FindName("RootGrid")
$MainPanel = $window.FindName("MainPanel")
$DateDayPanel = $window.FindName("DateDayPanel")
$TimePanel = $window.FindName("TimePanel")
$QuotePanel = $window.FindName("QuotePanel")
$TimeText = $window.FindName("TimeText"); $AmPmText = $window.FindName("AmPmText"); $DateText = $window.FindName("DateText"); $DayText = $window.FindName("DayText")
$Quote1Text = $window.FindName("Quote1Text"); $Quote2Text = $window.FindName("Quote2Text")

$window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"file:///C:/Program Files/Detaroxz/Kloc/icon.ico")

$window.Add_MouseLeftButtonDown({ 
    if ($global:Settings.PositionMode -eq "Fixed" -and -not $global:Settings.LockPosition) { $this.DragMove() }
})

function Get-FormattedCase ($str, $isCaps, $isAmPm = $false) {
    if ([string]::IsNullOrEmpty($str)) { return "" }
    if ($isCaps) { return $str.ToUpper() } 
    else { if ($isAmPm) { return $str.ToLower() }; return $str }
}

function Apply-Layout {
    $shadowOp = if ($global:Settings.ShadowEnabled) { 0.8 } else { 0.0 }
    if ($null -ne $TimeText.Effect) { $TimeText.Effect.Opacity = $shadowOp }
    if ($null -ne $AmPmText.Effect) { $AmPmText.Effect.Opacity = $shadowOp }
    if ($null -ne $DateText.Effect) { $DateText.Effect.Opacity = $shadowOp }
    if ($null -ne $DayText.Effect) { $DayText.Effect.Opacity = $shadowOp }
    if ($null -ne $Quote1Text.Effect) { $Quote1Text.Effect.Opacity = $shadowOp }
    if ($null -ne $Quote2Text.Effect) { $Quote2Text.Effect.Opacity = $shadowOp }

    $opac = $global:Settings.TextOpacity / 100.0
    $TimeText.Opacity = $opac; $AmPmText.Opacity = $opac; $DateText.Opacity = $opac
    $DayText.Opacity = $opac; $Quote1Text.Opacity = $opac; $Quote2Text.Opacity = $opac

    $TimePanel.Visibility = if ($global:Settings.ShowTime) { 'Visible' } else { 'Collapsed' }
    $TimeText.FontFamily = $global:Settings.FontTime; $TimeText.FontSize = $global:Settings.SizeTime
    $TimeText.FontWeight = if ($global:Settings.TimeBold) { 'Bold' } else { 'Normal' }
    $TimeText.FontStyle = if ($global:Settings.TimeItalic) { 'Italic' } else { 'Normal' }
    
    $AmPmText.Visibility = if ($global:Settings.ShowAmPm -and $global:Settings.UseAmPm -and $global:Settings.ShowTime) { 'Visible' } else { 'Collapsed' }
    $AmPmText.FontFamily = $global:Settings.FontAmPm; $AmPmText.FontSize = $global:Settings.SizeAmPm
    $AmPmText.FontWeight = if ($global:Settings.AmPmBold) { 'Bold' } else { 'Normal' }
    $AmPmText.FontStyle = if ($global:Settings.AmPmItalic) { 'Italic' } else { 'Normal' }
    $AmPmText.Margin = New-Object System.Windows.Thickness($global:Settings.AmPmSpacing, $global:Settings.AmPmOffsetY, 0, 0)
    
    $DateText.Visibility = if ($global:Settings.ShowDate) { 'Visible' } else { 'Collapsed' }
    $DateText.FontFamily = $global:Settings.FontDate; $DateText.FontSize = $global:Settings.SizeDate
    $DateText.FontWeight = if ($global:Settings.DateBold) { 'Bold' } else { 'Normal' }
    $DateText.FontStyle = if ($global:Settings.DateItalic) { 'Italic' } else { 'Normal' }
    
    $DayText.Visibility = if ($global:Settings.ShowDay) { 'Visible' } else { 'Collapsed' }
    $DayText.FontFamily = $global:Settings.FontDay; $DayText.FontSize = $global:Settings.SizeDay
    $DayText.FontWeight = if ($global:Settings.DayBold) { 'Bold' } else { 'Normal' }
    $DayText.FontStyle = if ($global:Settings.DayItalic) { 'Italic' } else { 'Normal' }

    $QuotePanel.Visibility = if ($global:Settings.ShowQuote1 -or $global:Settings.ShowQuote2) { 'Visible' } else { 'Collapsed' }
    
    $Quote1Text.Visibility = if ($global:Settings.ShowQuote1) { 'Visible' } else { 'Collapsed' }
    $Quote1Text.FontFamily = $global:Settings.FontQuote1; $Quote1Text.FontSize = $global:Settings.SizeQuote1
    $Quote1Text.FontWeight = if ($global:Settings.Quote1Bold) { 'Bold' } else { 'Normal' }
    $Quote1Text.FontStyle = if ($global:Settings.Quote1Italic) { 'Italic' } else { 'Normal' }
    $Quote1Text.Text = Get-FormattedCase ($global:Settings.Quote1Text.Replace("\n", "`n")) $global:Settings.Quote1AllCaps $false

    $Quote2Text.Visibility = if ($global:Settings.ShowQuote2) { 'Visible' } else { 'Collapsed' }
    $Quote2Text.FontFamily = $global:Settings.FontQuote2; $Quote2Text.FontSize = $global:Settings.SizeQuote2
    $Quote2Text.FontWeight = if ($global:Settings.Quote2Bold) { 'Bold' } else { 'Normal' }
    $Quote2Text.FontStyle = if ($global:Settings.Quote2Italic) { 'Italic' } else { 'Normal' }
    $Quote2Text.Text = Get-FormattedCase ($global:Settings.Quote2Text.Replace("\n", "`n")) $global:Settings.Quote2AllCaps $false
    
    try {
        $conv = New-Object System.Windows.Media.BrushConverter
        if ($global:Settings.UseIndividualColors) {
            $TimeText.Foreground = $conv.ConvertFromString($global:Settings.ColorTime)
            $AmPmText.Foreground = $conv.ConvertFromString($global:Settings.ColorAmPm)
            $DateText.Foreground = $conv.ConvertFromString($global:Settings.ColorDate)
            $DayText.Foreground = $conv.ConvertFromString($global:Settings.ColorDay)
            $Quote1Text.Foreground = $conv.ConvertFromString($global:Settings.ColorQuote1)
            $Quote2Text.Foreground = $conv.ConvertFromString($global:Settings.ColorQuote2)
        } else {
            $brush = $conv.ConvertFromString($global:Settings.ClockColor)
            $TimeText.Foreground = $brush; $AmPmText.Foreground = $brush; $DateText.Foreground = $brush; $DayText.Foreground = $brush
            $Quote1Text.Foreground = $brush; $Quote2Text.Foreground = $brush
        }
    } catch { }

    try {
        if ($global:Settings.ShowBackground) {
            $baseColor = [System.Windows.Media.ColorConverter]::ConvertFromString($global:Settings.BackgroundColor)
            $baseColor.A = [byte][math]::Round(255 * ($global:Settings.BgOpacity / 100))
            $window.Background = New-Object System.Windows.Media.SolidColorBrush($baseColor)
        } else { $window.Background = "Transparent" }
    } catch { $window.Background = "Transparent" }

    $MainPanel.HorizontalAlignment = $global:Settings.Alignment
    $TimePanel.HorizontalAlignment = $global:Settings.Alignment
    $DateDayPanel.HorizontalAlignment = $global:Settings.Alignment
    $Quote1Text.TextAlignment = $global:Settings.Alignment
    $Quote2Text.TextAlignment = $global:Settings.Alignment

    if ($global:Settings.DateDaySameLine) { 
        $DateDayPanel.Orientation = "Horizontal" 
        $DateText.Margin = New-Object System.Windows.Thickness(0, 0, $global:Settings.DateDaySpacing, 0)
    } else { 
        $DateDayPanel.Orientation = "Vertical"
        $DateText.Margin = New-Object System.Windows.Thickness(0, 0, 0, $global:Settings.DateDaySpacing)
        $DateText.HorizontalAlignment = $global:Settings.Alignment
        $DayText.HorizontalAlignment = $global:Settings.Alignment 
    }

    $MainPanel.Children.Clear()
    $TimePanel.Margin = New-Object System.Windows.Thickness(0,0,0,0)
    $DateDayPanel.Margin = New-Object System.Windows.Thickness(0,0,0,0)
    $QuotePanel.Margin = New-Object System.Windows.Thickness(0,$global:Settings.QuoteSpacing,0,0)
    
    if ($global:Settings.DateAboveTime) { 
        $DateDayPanel.Margin = New-Object System.Windows.Thickness(0,0,0,$global:Settings.LineSpacing)
        $MainPanel.Children.Add($DateDayPanel); $MainPanel.Children.Add($TimePanel); $MainPanel.Children.Add($QuotePanel)
    } else { 
        $TimePanel.Margin = New-Object System.Windows.Thickness(0,0,0,$global:Settings.LineSpacing)
        $MainPanel.Children.Add($TimePanel); $MainPanel.Children.Add($DateDayPanel); $MainPanel.Children.Add($QuotePanel)
    }

    $RootGrid.Width = [double]::NaN
    $RootGrid.Height = [double]::NaN
    
    $TimeText.Text = if ($global:Settings.ShowSeconds) { "88:88:88" } else { "88:88" }
    $AmPmText.Text = if ($global:Settings.AmPmAllCaps) { "WM" } else { "wm" }
    $DateText.Text = if ($global:Settings.DateAllCaps) { "SEPTEMBER 88, 8888" } else { "September 88, 8888" }
    $DayText.Text = if ($global:Settings.DayAllCaps) { "WEDNESDAY" } else { "Wednesday" }
    
    $window.UpdateLayout()
    $RootGrid.Measure((New-Object System.Windows.Size([Double]::PositiveInfinity, [Double]::PositiveInfinity)))
    $RootGrid.Width = $RootGrid.DesiredSize.Width + 5
    $RootGrid.Height = $RootGrid.DesiredSize.Height + 5
    
    if ($global:Settings.PositionMode -eq "Centered") {
        if ($global:Settings.IncludeTaskbarInCenter) {
            $window.Left = ([System.Windows.SystemParameters]::PrimaryScreenWidth - $RootGrid.Width) / 2
            $window.Top = ([System.Windows.SystemParameters]::PrimaryScreenHeight - $RootGrid.Height) / 2
        } else {
            $workArea = [System.Windows.SystemParameters]::WorkArea
            $window.Left = $workArea.Left + (($workArea.Width - $RootGrid.Width) / 2)
            $window.Top = $workArea.Top + (($workArea.Height - $RootGrid.Height) / 2)
        }
    }
    
    $TimeText.Text = ""; $AmPmText.Text = ""; $DateText.Text = ""; $DayText.Text = ""
}

$script:gcTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:gcTimer.Interval = [TimeSpan]::FromSeconds(10)
$script:gcTimer.Add_Tick({
    $script:gcTimer.Stop()
    [Win32]::TrimMemory()
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)

$script:tickCounter = 0
$script:TickAction = {
    $flagPath = "$env:APPDATA\Detaroxz\Kloc\open_settings.flag"
    if (Test-Path $flagPath) {
        Remove-Item $flagPath -Force -ErrorAction SilentlyContinue
        if (-not $script:isSettingsOpen) { Show-SettingsWindow }
    }

    $now = Get-Date
    $needs500ms = $false

    if ($global:Settings.ShowTime) {
        $needs500ms = $true
        $formatTime = if ($global:Settings.UseAmPm) {
            if ($global:Settings.ShowSeconds) { "hh:mm:ss" } else { "hh:mm" }
        } else {
            if ($global:Settings.ShowSeconds) { "HH:mm:ss" } else { "HH:mm" }
        }
        
        $tStr = Get-FormattedCase ($now.ToString($formatTime)) $global:Settings.TimeAllCaps
        if ($TimeText.Text -ne $tStr) { $TimeText.Text = $tStr }
        
        if ($global:Settings.UseAmPm -and $global:Settings.ShowAmPm) {
            $amPmStr = Get-FormattedCase ($now.ToString("tt")) $global:Settings.AmPmAllCaps $true
            if ($AmPmText.Text -ne $amPmStr) { $AmPmText.Text = $amPmStr }
        }
    } elseif ($global:Settings.ShowDate -or $global:Settings.ShowDay) {
        if ($now.Hour -eq 23 -and $now.Minute -ge 44) {
            $needs500ms = $true
        } else {
            if ($timer.Interval.TotalMinutes -ne 15) { $timer.Interval = [TimeSpan]::FromMinutes(15) }
        }
    } else {
        if ($timer.IsEnabled) { $timer.Stop(); [Win32]::TrimMemory() }
    }

    if ($global:Settings.ShowDate) {
        $dStr = Get-FormattedCase ($now.ToString("MMMM dd, yyyy")) $global:Settings.DateAllCaps
        if ($DateText.Text -ne $dStr) { $DateText.Text = $dStr }
    }
    if ($global:Settings.ShowDay) {
        $yStr = Get-FormattedCase ($now.ToString("dddd")) $global:Settings.DayAllCaps
        if ($DayText.Text -ne $yStr) { $DayText.Text = $yStr }
    }

    if ($needs500ms) {
        if ($timer.Interval.TotalMilliseconds -ne 500) { $timer.Interval = [TimeSpan]::FromMilliseconds(500) }
        if (-not $timer.IsEnabled) { $timer.Start() }
    } elseif (($global:Settings.ShowDate -or $global:Settings.ShowDay) -and -not $timer.IsEnabled) {
        $timer.Start()
    }

    if ($timer.Interval.TotalMinutes -eq 15 -and $timer.IsEnabled) {
        $script:gcTimer.Start()
    } elseif ($timer.IsEnabled) {
        $script:tickCounter++
        if ($script:tickCounter -ge 60) {
            $script:tickCounter = 0
            [Win32]::TrimMemory()
        }
    }
    
    if ($null -ne $script:clockHwnd -and $script:clockHwnd -ne [IntPtr]::Zero) {
        [Win32]::EnforceDesktopPosition($script:clockHwnd, $global:Settings.AlwaysOnTop)
    }
}

$timer.Add_Tick({ &$script:TickAction })

function Update-StartupManager {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Kloc.lnk"
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $taskName = "KlocDesktopClock"
    
    if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
    Remove-ItemProperty -Path $regPath -Name "Kloc" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    if ($global:Settings.StartupMethod -eq "Startup Folder (Shortcut)") {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = "wscript.exe"
        $Shortcut.Arguments = "`"C:\Program Files\Detaroxz\Kloc\Invisible.vbs`""
        $Shortcut.IconLocation = "C:\Program Files\Detaroxz\Kloc\icon.ico"
        $Shortcut.WindowStyle = 0
        $Shortcut.Save()
    } elseif ($global:Settings.StartupMethod -eq "Registry (HKCU Run)") {
        Set-ItemProperty -Path $regPath -Name "Kloc" -Value "wscript.exe `"C:\Program Files\Detaroxz\Kloc\Invisible.vbs`""
    } elseif ($global:Settings.StartupMethod -eq "Task Scheduler (Highest Privileges)") {
        try {
            $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"C:\Program Files\Detaroxz\Kloc\Invisible.vbs`""
            $trigger = New-ScheduledTaskTrigger -AtLogon
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        } catch { }
    }
}

$script:isSettingsOpen = $false

# --- Settings Window UI ---
function Show-SettingsWindow {
    if ($script:isSettingsOpen) { return }
    $script:isSettingsOpen = $true
    
    $global:Settings = Load-Settings

    $setXAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" 
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Kloc Settings (v1.0.3)" Width="600" Height="780" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize" Background="#FAFAFA" FontFamily="Segoe UI">
        <Grid Margin="5">
            <TabControl Background="#FFFFFF" BorderBrush="#DDDDDD" BorderThickness="1" Margin="5">
                <TabControl.Resources>
                    <Style TargetType="TabItem">
                        <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="TabItem">
                                    <Border Name="Border" BorderThickness="0,0,0,3" BorderBrush="Transparent" Padding="15,8" Margin="0,0,5,0" Background="Transparent" Cursor="Hand">
                                        <ContentPresenter x:Name="ContentSite" VerticalAlignment="Center" HorizontalAlignment="Center" ContentSource="Header"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="Border" Property="BorderBrush" Value="#005A9E"/>
                                            <Setter Property="TextElement.Foreground" Value="#005A9E"/>
                                            <Setter Property="FontWeight" Value="SemiBold"/>
                                        </Trigger>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="Border" Property="Background" Value="#EBEBEB"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </TabControl.Resources>
                
                <TabItem Header="General" FontSize="14" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="15,20,15,15">
                            <TextBlock Text="Typography &amp; Fonts" FontWeight="Bold" FontSize="15" Margin="0,0,0,15"/>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkTime" Content="Time" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontTime" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontTime" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsTime" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <StackPanel Margin="20,0,0,15">
                                <CheckBox Name="chkAmPm" Content="Use 12-Hour Format (AM/PM)" Margin="0,0,0,5"/>
                                <CheckBox Name="chkSeconds" Content="Show Seconds"/>
                            </StackPanel>
                            
                            <!-- AM/PM Settings -->
                            <Grid Margin="20,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="110"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkAmPmShow" Content="Show AM/PM" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontAmPm" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontAmPm" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsAmPm" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <Grid Margin="20,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Spacing:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Slider Name="sldAmPmSpacing" Minimum="-50" Maximum="50" Value="5" Grid.Column="1" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblAmPmSpacing" Text="5" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                            </Grid>
                            <Grid Margin="20,0,0,25"><Grid.ColumnDefinitions><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Vert Offset:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Slider Name="sldAmPmOffsetY" Minimum="-200" Maximum="200" Value="0" Grid.Column="1" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblAmPmOffsetY" Text="0" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                            </Grid>

                            <Grid Margin="0,5,0,15"><Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkDate" Content="Date" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontDate" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontDate" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsDate" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <Grid Margin="0,0,0,20"><Grid.ColumnDefinitions><ColumnDefinition Width="70"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkDay" Content="Day" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontDay" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontDay" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsDay" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Colors" FontSize="14" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="15,20,15,15">
                            <TextBlock Text="Colors &amp; Appearance" FontWeight="Bold" FontSize="15" Margin="0,0,0,15"/>
                            
                            <Grid Margin="0,0,0,20"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Text Opacity:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Slider Name="sldTextOpacity" Minimum="0" Maximum="100" Value="100" Grid.Column="1" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblTextOpacity" Text="100%" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                            </Grid>

                            <CheckBox Name="chkIndividualColors" Content="Use individual colors for each element" Margin="0,0,0,15"/>
                            
                            <!-- Global Color Engine -->
                            <StackPanel Name="panelGlobalColor">
                                <Grid Margin="0,0,0,15"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Clock Text Color:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnClockColor" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectClockColor" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblClockColor" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                            </StackPanel>

                            <!-- Individual Color Engine -->
                            <StackPanel Name="panelIndividualColors" Visibility="Collapsed" Margin="10,0,0,20">
                                <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Time:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorTime" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorTime" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorTime" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                                <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="AM/PM:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorAmPm" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorAmPm" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorAmPm" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                                <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Date:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorDate" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorDate" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorDate" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                                <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Day:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorDay" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorDay" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorDay" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                                <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Quote Line 1:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorQuote1" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorQuote1" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorQuote1" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                                <Grid Margin="0,0,0,15"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                    <TextBlock Text="Quote Line 2:" VerticalAlignment="Center" Grid.Column="0"/>
                                    <Button Name="btnColorQuote2" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                    <Rectangle Name="rectColorQuote2" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                    <TextBlock Name="lblColorQuote2" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                                </Grid>
                            </StackPanel>

                            <Separator Margin="0,10,0,20" />

                            <CheckBox Name="chkShadow" Content="Enable Text Drop Shadow" Margin="0,0,0,10"/>
                            <CheckBox Name="chkShowBg" Content="Enable Background" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <TextBlock Name="lblBgTitle" Text="Background Color:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Button Name="btnBgColor" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                <Rectangle Name="rectBgColor" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                <TextBlock Name="lblBgColor" Text="#000000" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <Grid Margin="0,0,0,20"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions>
                                <TextBlock Name="lblOpacityTitle" Text="Background Opacity:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Slider Name="sldBgOpacity" Minimum="0" Maximum="100" Value="50" Grid.Column="1" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblBgOpacity" Text="50%" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Quotes" FontSize="14" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="15,20,15,15">
                            <TextBlock Text="Display Quotes below the clock. Use \n for new lines." FontStyle="Italic" Margin="0,0,0,20" Foreground="#666666"/>
                            
                            <!-- Quote 1 -->
                            <TextBlock Text="Quote Line 1" FontWeight="Bold" Margin="0,0,0,10"/>
                            <CheckBox Name="chkShowQuote1" Content="Enable Quote 1" Margin="0,0,0,10"/>
                            <TextBox Name="txtQuote1" Height="60" TextWrapping="Wrap" AcceptsReturn="True" Margin="0,0,0,10" VerticalScrollBarVisibility="Auto"/>
                            <Grid Margin="0,0,0,30"><Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <Button Name="btnFontQuote1" Content="Select Font" Grid.Column="0" Padding="5,3"/>
                                <TextBlock Name="lblFontQuote1" Text="..." Grid.Column="1" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsQuote1" Content="All Caps" Grid.Column="2" VerticalAlignment="Center"/>
                            </Grid>

                            <!-- Quote 2 -->
                            <TextBlock Text="Quote Line 2" FontWeight="Bold" Margin="0,0,0,10"/>
                            <CheckBox Name="chkShowQuote2" Content="Enable Quote 2" Margin="0,0,0,10"/>
                            <TextBox Name="txtQuote2" Height="60" TextWrapping="Wrap" AcceptsReturn="True" Margin="0,0,0,10" VerticalScrollBarVisibility="Auto"/>
                            <Grid Margin="0,0,0,30"><Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <Button Name="btnFontQuote2" Content="Select Font" Grid.Column="0" Padding="5,3"/>
                                <TextBlock Name="lblFontQuote2" Text="..." Grid.Column="1" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsQuote2" Content="All Caps" Grid.Column="2" VerticalAlignment="Center"/>
                            </Grid>

                            <Separator Margin="0,0,0,20"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Quote Vertical Spacing:" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtQuoteSpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnQuoteSpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="Advanced" FontSize="14" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="15,20,15,15">
                            
                            <TextBlock Text="Configuration Management" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,25">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button Name="btnImport" Content="Import" Margin="0,0,5,0" Grid.Column="0" Padding="5"/>
                                <Button Name="btnExport" Content="Export" Margin="5,0,5,0" Grid.Column="1" Padding="5"/>
                                <Button Name="btnEdit" Content="Edit JSON" Margin="5,0,5,0" Grid.Column="2" Padding="5"/>
                                <Button Name="btnRefresh" Content="Refresh" Margin="5,0,0,0" Grid.Column="3" Padding="5"/>
                            </Grid>

                            <TextBlock Text="Custom Layout &amp; Slider Limits" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Spacing between lines (Time &amp; Date):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLineSpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLineSpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Spacing between Date &amp; Day:" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtDateDaySpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnDateDaySpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="AM/PM Vertical Offset Limit (+/-):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLimitOffset" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLimitOffset" Content="Apply" Grid.Column="2"/>
                            </Grid>
                            <Grid Margin="0,0,0,25"><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="AM/PM Spacing Limit (+/-):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLimitSpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLimitSpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                        
                            <TextBlock Text="Positioning" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Position Mode:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbPositionMode" Grid.Column="1">
                                    <ComboBoxItem Content="Fixed (Custom)"/>
                                    <ComboBoxItem Content="Centered"/>
                                </ComboBox>
                            </Grid>
                            <CheckBox Name="chkLock" Content="Lock Position (Disable Dragging in Fixed Mode)" Margin="0,0,0,5"/>
                            <CheckBox Name="chkIncludeTaskbar" Content="Include Taskbar in Center Calculation" Margin="0,0,0,25"/>

                            <TextBlock Text="Window &amp; Layout" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Window Behavior:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbMode" Grid.Column="1">
                                    <ComboBoxItem Content="Only on desktop"/>
                                    <ComboBoxItem Content="Always on top"/>
                                </ComboBox>
                            </Grid>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Text Alignment:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbAlign" Grid.Column="1">
                                    <ComboBoxItem Content="Left"/><ComboBoxItem Content="Center"/><ComboBoxItem Content="Right"/>
                                </ComboBox>
                            </Grid>
                            <CheckBox Name="chkSameLine" Content="Date and Day on same line" Margin="0,0,0,5"/>
                            <CheckBox Name="chkDateAbove" Content="Display Date/Day above Time" Margin="0,0,0,25"/>

                            <TextBlock Text="System" FontWeight="Bold" FontSize="15" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Startup Method:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbStartup" Grid.Column="1">
                                    <ComboBoxItem Content="Disabled"/>
                                    <ComboBoxItem Content="Startup Folder (Shortcut)"/>
                                    <ComboBoxItem Content="Registry (HKCU Run)"/>
                                    <ComboBoxItem Content="Task Scheduler"/>
                                </ComboBox>
                            </Grid>
                            
                            <Button Name="btnGC" Content="Trigger Garbage Collector" Padding="15,6" Margin="0,10,0,10" HorizontalAlignment="Left"/>
                            
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>

                <TabItem Header="About" FontSize="14" Padding="15,5">
                    <StackPanel Margin="10,15,10,10" HorizontalAlignment="Center" VerticalAlignment="Center">
                        <TextBlock Text="Kloc Desktop Clock" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,30,0,5"/>
                        <TextBlock Text="v1.0.3 by Detaroxz" FontSize="14" HorizontalAlignment="Center" Margin="0,0,0,30"/>
                        
                        <Button Name="btnRepo" Content="Project Repo (GitHub)" Padding="10,8" Margin="0,5" Width="260" Cursor="Hand" Background="#E5E5E5" BorderThickness="0"/>
                        <Button Name="btnWeb" Content="Developer Website" Padding="10,8" Margin="0,5" Width="260" Cursor="Hand" Background="#E5E5E5" BorderThickness="0"/>
                        
                        <Separator Margin="0,25" Width="320"/>
                        
                        <TextBlock Text="Also try these apps by Detaroxz:" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,10"/>
                        <Button Name="btnDarkSwitch" Content="DarkSwitch" Padding="10,8" Margin="0,5" Width="260" Cursor="Hand" Background="#E5E5E5" BorderThickness="0"/>
                        <Button Name="btnSortFE" Content="SortFE" Padding="10,8" Margin="0,5" Width="260" Cursor="Hand" Background="#E5E5E5" BorderThickness="0"/>
                    </StackPanel>
                </TabItem>
            </TabControl>
        </Grid>
    </Window>
"@
    try {
        $setStringReader = New-Object System.IO.StringReader($setXAML)
        $setXmlReader = [System.Xml.XmlReader]::Create($setStringReader)
        $setWindow = [System.Windows.Markup.XamlReader]::Load($setXmlReader)
        $setXmlReader.Close()
        $setStringReader.Dispose()
    } catch {
        $script:isSettingsOpen = $false
        [System.Windows.MessageBox]::Show("UI Rendering Error: $_", "Kloc Setup Error", 0, 16) | Out-Null
        return
    }
    
    $setWindow.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"file:///C:/Program Files/Detaroxz/Kloc/icon.ico")

    function Update-FontLabel($lbl, $tag) {
        $b = if ($tag.Bold) { " Bold" } else { "" }; $i = if ($tag.Italic) { " Italic" } else { "" }
        $lbl.Text = "$($tag.Name), $([math]::Round($tag.Size))pt$b$i"; $lbl.Tag = $tag
    }
    
    function Update-ColorLabel($lbl, $rect, $hex) {
        $lbl.Text = $hex; $rect.Fill = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
    }

    $script:SyncUIToSettings = {
        $setWindow.FindName("sldAmPmOffsetY").Minimum = -$global:Settings.LimitOffset
        $setWindow.FindName("sldAmPmOffsetY").Maximum = $global:Settings.LimitOffset
        $setWindow.FindName("sldAmPmSpacing").Minimum = -$global:Settings.LimitSpacing
        $setWindow.FindName("sldAmPmSpacing").Maximum = $global:Settings.LimitSpacing
        $setWindow.FindName("txtLineSpacing").Text = $global:Settings.LineSpacing.ToString()
        $setWindow.FindName("txtDateDaySpacing").Text = $global:Settings.DateDaySpacing.ToString()
        $setWindow.FindName("txtLimitOffset").Text = $global:Settings.LimitOffset.ToString()
        $setWindow.FindName("txtLimitSpacing").Text = $global:Settings.LimitSpacing.ToString()
        $setWindow.FindName("txtQuoteSpacing").Text = $global:Settings.QuoteSpacing.ToString()

        $setWindow.FindName("chkTime").IsChecked = $global:Settings.ShowTime; $setWindow.FindName("chkCapsTime").IsChecked = $global:Settings.TimeAllCaps
        Update-FontLabel $setWindow.FindName("lblFontTime") @{ Name=$global:Settings.FontTime; Size=$global:Settings.SizeTime; Bold=$global:Settings.TimeBold; Italic=$global:Settings.TimeItalic }
        
        $setWindow.FindName("chkAmPm").IsChecked = $global:Settings.UseAmPm; $setWindow.FindName("chkSeconds").IsChecked = $global:Settings.ShowSeconds
        $setWindow.FindName("chkAmPmShow").IsChecked = $global:Settings.ShowAmPm; $setWindow.FindName("chkCapsAmPm").IsChecked = $global:Settings.AmPmAllCaps
        Update-FontLabel $setWindow.FindName("lblFontAmPm") @{ Name=$global:Settings.FontAmPm; Size=$global:Settings.SizeAmPm; Bold=$global:Settings.AmPmBold; Italic=$global:Settings.AmPmItalic }
        $setWindow.FindName("sldAmPmOffsetY").Value = $global:Settings.AmPmOffsetY; $setWindow.FindName("lblAmPmOffsetY").Text = "$($global:Settings.AmPmOffsetY)"
        $setWindow.FindName("sldAmPmSpacing").Value = $global:Settings.AmPmSpacing; $setWindow.FindName("lblAmPmSpacing").Text = "$($global:Settings.AmPmSpacing)"

        $setWindow.FindName("chkDate").IsChecked = $global:Settings.ShowDate; $setWindow.FindName("chkCapsDate").IsChecked = $global:Settings.DateAllCaps
        Update-FontLabel $setWindow.FindName("lblFontDate") @{ Name=$global:Settings.FontDate; Size=$global:Settings.SizeDate; Bold=$global:Settings.DateBold; Italic=$global:Settings.DateItalic }
        
        $setWindow.FindName("chkDay").IsChecked = $global:Settings.ShowDay; $setWindow.FindName("chkCapsDay").IsChecked = $global:Settings.DayAllCaps
        Update-FontLabel $setWindow.FindName("lblFontDay") @{ Name=$global:Settings.FontDay; Size=$global:Settings.SizeDay; Bold=$global:Settings.DayBold; Italic=$global:Settings.DayItalic }
        
        $setWindow.FindName("chkShowQuote1").IsChecked = $global:Settings.ShowQuote1; $setWindow.FindName("chkCapsQuote1").IsChecked = $global:Settings.Quote1AllCaps; $setWindow.FindName("txtQuote1").Text = $global:Settings.Quote1Text
        Update-FontLabel $setWindow.FindName("lblFontQuote1") @{ Name=$global:Settings.FontQuote1; Size=$global:Settings.SizeQuote1; Bold=$global:Settings.Quote1Bold; Italic=$global:Settings.Quote1Italic }

        $setWindow.FindName("chkShowQuote2").IsChecked = $global:Settings.ShowQuote2; $setWindow.FindName("chkCapsQuote2").IsChecked = $global:Settings.Quote2AllCaps; $setWindow.FindName("txtQuote2").Text = $global:Settings.Quote2Text
        Update-FontLabel $setWindow.FindName("lblFontQuote2") @{ Name=$global:Settings.FontQuote2; Size=$global:Settings.SizeQuote2; Bold=$global:Settings.Quote2Bold; Italic=$global:Settings.Quote2Italic }

        $setWindow.FindName("sldTextOpacity").Value = $global:Settings.TextOpacity; $setWindow.FindName("lblTextOpacity").Text = "$($global:Settings.TextOpacity)%"
        $setWindow.FindName("chkIndividualColors").IsChecked = $global:Settings.UseIndividualColors
        Update-ColorLabel $setWindow.FindName("lblClockColor") $setWindow.FindName("rectClockColor") $global:Settings.ClockColor
        Update-ColorLabel $setWindow.FindName("lblColorTime") $setWindow.FindName("rectColorTime") $global:Settings.ColorTime
        Update-ColorLabel $setWindow.FindName("lblColorAmPm") $setWindow.FindName("rectColorAmPm") $global:Settings.ColorAmPm
        Update-ColorLabel $setWindow.FindName("lblColorDate") $setWindow.FindName("rectColorDate") $global:Settings.ColorDate
        Update-ColorLabel $setWindow.FindName("lblColorDay") $setWindow.FindName("rectColorDay") $global:Settings.ColorDay
        Update-ColorLabel $setWindow.FindName("lblColorQuote1") $setWindow.FindName("rectColorQuote1") $global:Settings.ColorQuote1
        Update-ColorLabel $setWindow.FindName("lblColorQuote2") $setWindow.FindName("rectColorQuote2") $global:Settings.ColorQuote2

        $setWindow.FindName("chkShadow").IsChecked = $global:Settings.ShadowEnabled
        $setWindow.FindName("chkShowBg").IsChecked = $global:Settings.ShowBackground
        Update-ColorLabel $setWindow.FindName("lblBgColor") $setWindow.FindName("rectBgColor") $global:Settings.BackgroundColor
        $setWindow.FindName("sldBgOpacity").Value = $global:Settings.BgOpacity; $setWindow.FindName("lblBgOpacity").Text = "$($global:Settings.BgOpacity)%"
        
        $setWindow.FindName("cmbPositionMode").SelectedIndex = if ($global:Settings.PositionMode -eq "Centered") { 1 } else { 0 }
        $setWindow.FindName("cmbMode").SelectedIndex = if ($global:Settings.AlwaysOnTop) { 1 } else { 0 }
        $setWindow.FindName("cmbAlign").Text = $global:Settings.Alignment; $setWindow.FindName("chkLock").IsChecked = $global:Settings.LockPosition
        $setWindow.FindName("chkIncludeTaskbar").IsChecked = $global:Settings.IncludeTaskbarInCenter
        $setWindow.FindName("chkSameLine").IsChecked = $global:Settings.DateDaySameLine; $setWindow.FindName("chkDateAbove").IsChecked = $global:Settings.DateAboveTime
        $setWindow.FindName("cmbStartup").Text = $global:Settings.StartupMethod

        # Time-based active dependencies
        $timeIsOn = $global:Settings.ShowTime
        $setWindow.FindName("chkAmPm").IsEnabled = $timeIsOn
        $setWindow.FindName("chkSeconds").IsEnabled = $timeIsOn
        $amPmEnabled = ($global:Settings.UseAmPm -and $timeIsOn)
        $setWindow.FindName("chkAmPmShow").IsEnabled = $amPmEnabled
        $setWindow.FindName("btnFontAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("chkCapsAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("sldAmPmOffsetY").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("sldAmPmSpacing").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("lblFontAmPm").Opacity = if($amPmEnabled -and $global:Settings.ShowAmPm){1}else{0.5}

        $setWindow.FindName("btnFontTime").IsEnabled = $timeIsOn; $setWindow.FindName("chkCapsTime").IsEnabled = $timeIsOn; $setWindow.FindName("lblFontTime").Opacity = if($timeIsOn){1}else{0.5}
        $setWindow.FindName("btnFontDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("chkCapsDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("lblFontDate").Opacity = if($global:Settings.ShowDate){1}else{0.5}
        $setWindow.FindName("btnFontDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("chkCapsDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("lblFontDay").Opacity = if($global:Settings.ShowDay){1}else{0.5}
        
        $setWindow.FindName("txtQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("btnFontQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("chkCapsQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("lblFontQuote1").Opacity = if($global:Settings.ShowQuote1){1}else{0.5}
        $setWindow.FindName("txtQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("btnFontQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("chkCapsQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("lblFontQuote2").Opacity = if($global:Settings.ShowQuote2){1}else{0.5}

        $setWindow.FindName("panelIndividualColors").Visibility = if ($global:Settings.UseIndividualColors) { 'Visible' } else { 'Collapsed' }
        $setWindow.FindName("panelGlobalColor").Visibility = if ($global:Settings.UseIndividualColors) { 'Collapsed' } else { 'Visible' }

        $setWindow.FindName("btnBgColor").IsEnabled = $global:Settings.ShowBackground; $setWindow.FindName("sldBgOpacity").IsEnabled = $global:Settings.ShowBackground
        $setWindow.FindName("lblBgTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}; $setWindow.FindName("lblOpacityTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}
        $setWindow.FindName("chkLock").IsEnabled = ($global:Settings.PositionMode -eq "Fixed"); $setWindow.FindName("chkIncludeTaskbar").IsEnabled = ($global:Settings.PositionMode -eq "Centered")
    }

    $script:UpdateState = {
        $global:Settings.ShowTime = ($setWindow.FindName("chkTime").IsChecked -eq $true)
        $global:Settings.TimeAllCaps = ($setWindow.FindName("chkCapsTime").IsChecked -eq $true)
        $global:Settings.FontTime = $setWindow.FindName("lblFontTime").Tag.Name; $global:Settings.SizeTime = $setWindow.FindName("lblFontTime").Tag.Size; $global:Settings.TimeBold = $setWindow.FindName("lblFontTime").Tag.Bold; $global:Settings.TimeItalic = $setWindow.FindName("lblFontTime").Tag.Italic
        
        $global:Settings.ShowAmPm = ($setWindow.FindName("chkAmPmShow").IsChecked -eq $true)
        $global:Settings.AmPmAllCaps = ($setWindow.FindName("chkCapsAmPm").IsChecked -eq $true)
        $global:Settings.FontAmPm = $setWindow.FindName("lblFontAmPm").Tag.Name; $global:Settings.SizeAmPm = $setWindow.FindName("lblFontAmPm").Tag.Size; $global:Settings.AmPmBold = $setWindow.FindName("lblFontAmPm").Tag.Bold; $global:Settings.AmPmItalic = $setWindow.FindName("lblFontAmPm").Tag.Italic
        $global:Settings.AmPmOffsetY = [int]$setWindow.FindName("sldAmPmOffsetY").Value
        $global:Settings.AmPmSpacing = [int]$setWindow.FindName("sldAmPmSpacing").Value

        $global:Settings.ShowDate = ($setWindow.FindName("chkDate").IsChecked -eq $true)
        $global:Settings.DateAllCaps = ($setWindow.FindName("chkCapsDate").IsChecked -eq $true)
        $global:Settings.FontDate = $setWindow.FindName("lblFontDate").Tag.Name; $global:Settings.SizeDate = $setWindow.FindName("lblFontDate").Tag.Size; $global:Settings.DateBold = $setWindow.FindName("lblFontDate").Tag.Bold; $global:Settings.DateItalic = $setWindow.FindName("lblFontDate").Tag.Italic
        
        $global:Settings.ShowDay = ($setWindow.FindName("chkDay").IsChecked -eq $true)
        $global:Settings.DayAllCaps = ($setWindow.FindName("chkCapsDay").IsChecked -eq $true)
        $global:Settings.FontDay = $setWindow.FindName("lblFontDay").Tag.Name; $global:Settings.SizeDay = $setWindow.FindName("lblFontDay").Tag.Size; $global:Settings.DayBold = $setWindow.FindName("lblFontDay").Tag.Bold; $global:Settings.DayItalic = $setWindow.FindName("lblFontDay").Tag.Italic
        
        $global:Settings.ShowQuote1 = ($setWindow.FindName("chkShowQuote1").IsChecked -eq $true)
        $global:Settings.Quote1Text = $setWindow.FindName("txtQuote1").Text
        $global:Settings.Quote1AllCaps = ($setWindow.FindName("chkCapsQuote1").IsChecked -eq $true)
        $global:Settings.FontQuote1 = $setWindow.FindName("lblFontQuote1").Tag.Name; $global:Settings.SizeQuote1 = $setWindow.FindName("lblFontQuote1").Tag.Size; $global:Settings.Quote1Bold = $setWindow.FindName("lblFontQuote1").Tag.Bold; $global:Settings.Quote1Italic = $setWindow.FindName("lblFontQuote1").Tag.Italic
        
        $global:Settings.ShowQuote2 = ($setWindow.FindName("chkShowQuote2").IsChecked -eq $true)
        $global:Settings.Quote2Text = $setWindow.FindName("txtQuote2").Text
        $global:Settings.Quote2AllCaps = ($setWindow.FindName("chkCapsQuote2").IsChecked -eq $true)
        $global:Settings.FontQuote2 = $setWindow.FindName("lblFontQuote2").Tag.Name; $global:Settings.SizeQuote2 = $setWindow.FindName("lblFontQuote2").Tag.Size; $global:Settings.Quote2Bold = $setWindow.FindName("lblFontQuote2").Tag.Bold; $global:Settings.Quote2Italic = $setWindow.FindName("lblFontQuote2").Tag.Italic

        $global:Settings.TextOpacity = [int]$setWindow.FindName("sldTextOpacity").Value
        $global:Settings.UseIndividualColors = ($setWindow.FindName("chkIndividualColors").IsChecked -eq $true)
        $global:Settings.ClockColor = $setWindow.FindName("lblClockColor").Text
        $global:Settings.ColorTime = $setWindow.FindName("lblColorTime").Text
        $global:Settings.ColorAmPm = $setWindow.FindName("lblColorAmPm").Text
        $global:Settings.ColorDate = $setWindow.FindName("lblColorDate").Text
        $global:Settings.ColorDay = $setWindow.FindName("lblColorDay").Text
        $global:Settings.ColorQuote1 = $setWindow.FindName("lblColorQuote1").Text
        $global:Settings.ColorQuote2 = $setWindow.FindName("lblColorQuote2").Text

        $global:Settings.ShadowEnabled = ($setWindow.FindName("chkShadow").IsChecked -eq $true)
        $global:Settings.ShowBackground = ($setWindow.FindName("chkShowBg").IsChecked -eq $true)
        $global:Settings.BackgroundColor = $setWindow.FindName("lblBgColor").Text; $global:Settings.BgOpacity = [int]$setWindow.FindName("sldBgOpacity").Value
        $global:Settings.UseAmPm = ($setWindow.FindName("chkAmPm").IsChecked -eq $true); $global:Settings.ShowSeconds = ($setWindow.FindName("chkSeconds").IsChecked -eq $true)
        $global:Settings.PositionMode = if ($setWindow.FindName("cmbPositionMode").SelectedIndex -eq 1) { "Centered" } else { "Fixed" }
        $global:Settings.AlwaysOnTop = if ($setWindow.FindName("cmbMode").SelectedIndex -eq 1) { $true } else { $false }
        $global:Settings.Alignment = $setWindow.FindName("cmbAlign").Text; $global:Settings.LockPosition = ($setWindow.FindName("chkLock").IsChecked -eq $true)
        $global:Settings.IncludeTaskbarInCenter = ($setWindow.FindName("chkIncludeTaskbar").IsChecked -eq $true); $global:Settings.DateDaySameLine = ($setWindow.FindName("chkSameLine").IsChecked -eq $true)
        $global:Settings.DateAboveTime = ($setWindow.FindName("chkDateAbove").IsChecked -eq $true); $global:Settings.StartupMethod = $setWindow.FindName("cmbStartup").Text

        # Update Visuals inside Settings Window Dynamically
        $timeIsOn = $global:Settings.ShowTime
        $setWindow.FindName("chkAmPm").IsEnabled = $timeIsOn
        $setWindow.FindName("chkSeconds").IsEnabled = $timeIsOn
        $amPmEnabled = ($global:Settings.UseAmPm -and $timeIsOn)
        $setWindow.FindName("chkAmPmShow").IsEnabled = $amPmEnabled
        $setWindow.FindName("btnFontAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("chkCapsAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("sldAmPmOffsetY").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("sldAmPmSpacing").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("lblFontAmPm").Opacity = if($amPmEnabled -and $global:Settings.ShowAmPm){1}else{0.5}

        $setWindow.FindName("btnFontTime").IsEnabled = $timeIsOn; $setWindow.FindName("chkCapsTime").IsEnabled = $timeIsOn; $setWindow.FindName("lblFontTime").Opacity = if($timeIsOn){1}else{0.5}
        $setWindow.FindName("btnFontDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("chkCapsDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("lblFontDate").Opacity = if($global:Settings.ShowDate){1}else{0.5}
        $setWindow.FindName("btnFontDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("chkCapsDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("lblFontDay").Opacity = if($global:Settings.ShowDay){1}else{0.5}
        
        $setWindow.FindName("txtQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("btnFontQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("chkCapsQuote1").IsEnabled = $global:Settings.ShowQuote1; $setWindow.FindName("lblFontQuote1").Opacity = if($global:Settings.ShowQuote1){1}else{0.5}
        $setWindow.FindName("txtQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("btnFontQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("chkCapsQuote2").IsEnabled = $global:Settings.ShowQuote2; $setWindow.FindName("lblFontQuote2").Opacity = if($global:Settings.ShowQuote2){1}else{0.5}

        $setWindow.FindName("panelIndividualColors").Visibility = if ($global:Settings.UseIndividualColors) { 'Visible' } else { 'Collapsed' }
        $setWindow.FindName("panelGlobalColor").Visibility = if ($global:Settings.UseIndividualColors) { 'Collapsed' } else { 'Visible' }

        $setWindow.FindName("btnBgColor").IsEnabled = $global:Settings.ShowBackground; $setWindow.FindName("sldBgOpacity").IsEnabled = $global:Settings.ShowBackground
        $setWindow.FindName("lblBgTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}; $setWindow.FindName("lblOpacityTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}
        $setWindow.FindName("chkLock").IsEnabled = ($global:Settings.PositionMode -eq "Fixed"); $setWindow.FindName("chkIncludeTaskbar").IsEnabled = ($global:Settings.PositionMode -eq "Centered")

        Save-Settings $global:Settings
        Update-StartupManager
        Apply-Layout
        &$script:TickAction
        
        if ($null -ne $script:clockHwnd -and $script:clockHwnd -ne [IntPtr]::Zero) {
            if ($global:Settings.AlwaysOnTop) {
                [Win32]::UnbindFromDesktop($script:clockHwnd)
                $window.Topmost = $true
            } else {
                $window.Topmost = $false
                [Win32]::BindToDesktop($script:clockHwnd)
            }
        }
        [Win32]::TrimMemory()
    }

    function Prompt-Font($currentTag) {
        $dlg = New-Object System.Windows.Forms.FontDialog; $dlg.ShowEffects = $false
        $style = [System.Drawing.FontStyle]::Regular
        if ($currentTag.Bold) { $style = $style -bor [System.Drawing.FontStyle]::Bold }
        if ($currentTag.Italic) { $style = $style -bor [System.Drawing.FontStyle]::Italic }
        
        $ptSize = [float][math]::Round($currentTag.Size * 0.75)
        if ($ptSize -lt 1) { $ptSize = 12 }

        try { $dlg.Font = New-Object System.Drawing.Font($currentTag.Name, $ptSize, $style) } 
        catch { try { $dlg.Font = New-Object System.Drawing.Font("Arial", $ptSize, $style) } catch {} }
        
        $res = $currentTag
        if ($dlg.ShowDialog() -eq 'OK') { $res = @{ Name=$dlg.Font.FontFamily.Name; Size=($dlg.Font.Size / 0.75); Bold=$dlg.Font.Bold; Italic=$dlg.Font.Italic } }
        $dlg.Dispose()
        return $res
    }
    
    function Prompt-Color($hexStr) {
        $dlg = New-Object System.Windows.Forms.ColorDialog; $dlg.FullOpen = $true
        try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($hexStr) } catch {}
        $res = $hexStr
        if ($dlg.ShowDialog() -eq 'OK') { $res = "#$($dlg.Color.R.ToString('X2'))$($dlg.Color.G.ToString('X2'))$($dlg.Color.B.ToString('X2'))" }
        $dlg.Dispose()
        return $res
    }

    # First load explicit sync
    &$script:SyncUIToSettings

    # --- ADVANCED CONFIGURATION HANDLERS ---
    $setWindow.FindName("btnImport").Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "JSON Files|*.json|All Files|*.*"
        if ($dlg.ShowDialog() -eq 'OK') {
            Copy-Item -Path $dlg.FileName -Destination $settingsFile -Force
            $global:Settings = Load-Settings
            &$script:SyncUIToSettings
            &$script:UpdateState
        }
        $dlg.Dispose()
    })
    $setWindow.FindName("btnExport").Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "JSON Files|*.json|All Files|*.*"
        $dlg.FileName = "KlocSettings.json"
        if ($dlg.ShowDialog() -eq 'OK') { Copy-Item -Path $settingsFile -Destination $dlg.FileName -Force }
        $dlg.Dispose()
    })
    $setWindow.FindName("btnEdit").Add_Click({ Start-Process notepad.exe $settingsFile })
    $setWindow.FindName("btnRefresh").Add_Click({ $global:Settings = Load-Settings; &$script:SyncUIToSettings; &$script:UpdateState })
    $setWindow.FindName("btnGC").Add_Click({ 
        [Win32]::TrimMemory()
        [System.Windows.MessageBox]::Show("Garbage Collection Triggered Successfully!`nUnused RAM has been returned to the system.", "Kloc Optimizer", 0, 64) | Out-Null
    })

    # --- LIMIT MODIFIERS LOGIC ---
    $setWindow.FindName("btnLineSpacing").Add_Click({
        $val = 0; if ([int]::TryParse($setWindow.FindName("txtLineSpacing").Text, [ref]$val)) { $global:Settings.LineSpacing = $val; &$script:UpdateState }
    })
    $setWindow.FindName("btnDateDaySpacing").Add_Click({
        $val = 10; if ([int]::TryParse($setWindow.FindName("txtDateDaySpacing").Text, [ref]$val)) { $global:Settings.DateDaySpacing = $val; &$script:UpdateState }
    })
    $setWindow.FindName("btnQuoteSpacing").Add_Click({
        $val = 10; if ([int]::TryParse($setWindow.FindName("txtQuoteSpacing").Text, [ref]$val)) { $global:Settings.QuoteSpacing = $val; &$script:UpdateState }
    })
    $setWindow.FindName("btnLimitOffset").Add_Click({
        $val = 200; if ([int]::TryParse($setWindow.FindName("txtLimitOffset").Text, [ref]$val)) { 
            $global:Settings.LimitOffset = [math]::Abs($val)
            $setWindow.FindName("sldAmPmOffsetY").Minimum = -$global:Settings.LimitOffset
            $setWindow.FindName("sldAmPmOffsetY").Maximum = $global:Settings.LimitOffset
            &$script:UpdateState 
        }
    })
    $setWindow.FindName("btnLimitSpacing").Add_Click({
        $val = 50; if ([int]::TryParse($setWindow.FindName("txtLimitSpacing").Text, [ref]$val)) { 
            $global:Settings.LimitSpacing = [math]::Abs($val)
            $setWindow.FindName("sldAmPmSpacing").Minimum = -$global:Settings.LimitSpacing
            $setWindow.FindName("sldAmPmSpacing").Maximum = $global:Settings.LimitSpacing
            &$script:UpdateState 
        }
    })

    # --- TEXT BOXES ---
    $setWindow.FindName("txtQuote1").Add_LostFocus({ $global:Settings.Quote1Text = $this.Text; Apply-Layout; [Win32]::TrimMemory() })
    $setWindow.FindName("txtQuote2").Add_LostFocus({ $global:Settings.Quote2Text = $this.Text; Apply-Layout; [Win32]::TrimMemory() })

    # --- CHECKBOXES ---
    $chkNames = @("chkTime", "chkCapsTime", "chkAmPmShow", "chkCapsAmPm", "chkDate", "chkCapsDate", "chkDay", "chkCapsDay", "chkShadow", "chkShowBg", "chkAmPm", "chkSeconds", "chkLock", "chkIncludeTaskbar", "chkSameLine", "chkDateAbove", "chkShowQuote1", "chkCapsQuote1", "chkShowQuote2", "chkCapsQuote2", "chkIndividualColors")
    foreach ($cName in $chkNames) {
        $cObj = $setWindow.FindName($cName)
        if ($null -ne $cObj) {
            $cObj.Add_Checked({ &$script:UpdateState })
            $cObj.Add_Unchecked({ &$script:UpdateState })
        }
    }

    # --- COMBO BOXES ---
    $setWindow.FindName("cmbPositionMode").Add_DropDownClosed({ &$script:UpdateState })
    $setWindow.FindName("cmbMode").Add_DropDownClosed({ &$script:UpdateState })
    $setWindow.FindName("cmbAlign").Add_DropDownClosed({ &$script:UpdateState })
    $setWindow.FindName("cmbStartup").Add_DropDownClosed({ &$script:UpdateState })

    # --- SLIDERS ---
    $sldOp = $setWindow.FindName("sldTextOpacity"); $sldOp.Add_ValueChanged({ $setWindow.FindName("lblTextOpacity").Text = "$($sldOp.Value)%" }); $sldOp.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldOp.Add_KeyUp({ &$script:UpdateState })
    $sldBgOp = $setWindow.FindName("sldBgOpacity"); $sldBgOp.Add_ValueChanged({ $setWindow.FindName("lblBgOpacity").Text = "$($sldBgOp.Value)%" }); $sldBgOp.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldBgOp.Add_KeyUp({ &$script:UpdateState })
    $sldAmPmSpace = $setWindow.FindName("sldAmPmSpacing"); $sldAmPmSpace.Add_ValueChanged({ $setWindow.FindName("lblAmPmSpacing").Text = "$($sldAmPmSpace.Value)" }); $sldAmPmSpace.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldAmPmSpace.Add_KeyUp({ &$script:UpdateState })
    $sldAmPmOffset = $setWindow.FindName("sldAmPmOffsetY"); $sldAmPmOffset.Add_ValueChanged({ $setWindow.FindName("lblAmPmOffsetY").Text = "$($sldAmPmOffset.Value)" }); $sldAmPmOffset.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldAmPmOffset.Add_KeyUp({ &$script:UpdateState })

    # --- FONT BUTTONS ---
    $setWindow.FindName("btnFontTime").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontTime") (Prompt-Font $setWindow.FindName("lblFontTime").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontAmPm").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontAmPm") (Prompt-Font $setWindow.FindName("lblFontAmPm").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontDate").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontDate") (Prompt-Font $setWindow.FindName("lblFontDate").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontDay").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontDay") (Prompt-Font $setWindow.FindName("lblFontDay").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontQuote1").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontQuote1") (Prompt-Font $setWindow.FindName("lblFontQuote1").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontQuote2").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontQuote2") (Prompt-Font $setWindow.FindName("lblFontQuote2").Tag); &$script:UpdateState })
    
    # --- COLOR BUTTONS ---
    $setWindow.FindName("btnClockColor").Add_Click({ Update-ColorLabel $setWindow.FindName("lblClockColor") $setWindow.FindName("rectClockColor") (Prompt-Color $setWindow.FindName("lblClockColor").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorTime").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorTime") $setWindow.FindName("rectColorTime") (Prompt-Color $setWindow.FindName("lblColorTime").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorAmPm").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorAmPm") $setWindow.FindName("rectColorAmPm") (Prompt-Color $setWindow.FindName("lblColorAmPm").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorDate").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorDate") $setWindow.FindName("rectColorDate") (Prompt-Color $setWindow.FindName("lblColorDate").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorDay").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorDay") $setWindow.FindName("rectColorDay") (Prompt-Color $setWindow.FindName("lblColorDay").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorQuote1").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorQuote1") $setWindow.FindName("rectColorQuote1") (Prompt-Color $setWindow.FindName("lblColorQuote1").Text); &$script:UpdateState })
    $setWindow.FindName("btnColorQuote2").Add_Click({ Update-ColorLabel $setWindow.FindName("lblColorQuote2") $setWindow.FindName("rectColorQuote2") (Prompt-Color $setWindow.FindName("lblColorQuote2").Text); &$script:UpdateState })
    $setWindow.FindName("btnBgColor").Add_Click({ Update-ColorLabel $setWindow.FindName("lblBgColor") $setWindow.FindName("rectBgColor") (Prompt-Color $setWindow.FindName("lblBgColor").Text); &$script:UpdateState })
    
    # --- LINKS ---
    $setWindow.FindName("btnRepo").Add_Click({ Start-Process "https://github.com/avm3005/Kloc" })
    $setWindow.FindName("btnWeb").Add_Click({ Start-Process "https://avm3005.github.io/portfolio/" })
    $setWindow.FindName("btnDarkSwitch").Add_Click({ Start-Process "https://github.com/avm3005/DarkSwitch" })
    $setWindow.FindName("btnSortFE").Add_Click({ Start-Process "https://github.com/avm3005/SortFE" })

    $setWindow.Add_Closed({ $script:isSettingsOpen = $false; [Win32]::TrimMemory() })
    $setWindow.ShowDialog() | Out-Null
}

$window.Add_Loaded({
    $script:clockHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    
    # Hide from Alt+Tab AND Prevent Activation Focus (fixes Win+D top-layer rendering bug)
    $exStyle = [Win32]::GetWindowLong($script:clockHwnd, -20)
    [Win32]::SetWindowLong($script:clockHwnd, -20, $exStyle -bor 0x00000080 -bor 0x08000000) | Out-Null
    
    # Win32 Event Hook to strictly intercept Win+D (WM_SHOWWINDOW) and immediately force Z-order to bottom
    $script:hookDelegate = [System.Windows.Interop.HwndSourceHook]{
        param([IntPtr]$hwnd, [int]$msg, [IntPtr]$wParam, [IntPtr]$lParam, [ref]$handled)
        if ($msg -eq 0x0018) {
            $window.Dispatcher.BeginInvoke([Action]{
                if ($null -ne $script:clockHwnd -and $script:clockHwnd -ne [IntPtr]::Zero) {
                    [Win32]::EnforceDesktopPosition($script:clockHwnd, $global:Settings.AlwaysOnTop)
                }
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
        return [IntPtr]::Zero
    }
    $source = [System.Windows.Interop.HwndSource]::FromHwnd($script:clockHwnd)
    $source.AddHook($script:hookDelegate)

    Apply-Layout
    
    if (-not $global:Settings.AlwaysOnTop) {
        [Win32]::BindToDesktop($script:clockHwnd)
    }
    
    $window.Opacity = 1
    [Win32]::TrimMemory()
})

$sysTray = New-Object System.Windows.Forms.NotifyIcon
$sysTray.Icon = New-Object System.Drawing.Icon("C:\Program Files\Detaroxz\Kloc\icon.ico")
$sysTray.Text = "Kloc Desktop Clock"
$sysTray.Visible = $true
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$itemSettings = $contextMenu.Items.Add("Settings"); $itemSettings.add_Click({ Show-SettingsWindow })
$itemExit = $contextMenu.Items.Add("Exit"); $itemExit.add_Click({ $sysTray.Visible = $false; $sysTray.Dispose(); [System.Windows.Application]::Current.Shutdown() })
$sysTray.ContextMenuStrip = $contextMenu

$timer.Start()
$app = New-Object System.Windows.Application
$app.Run($window) | Out-Null
'@

# --- 6. WRITE REMAINING FILES & START MENU ---
Set-Content -Path "$installDir\Kloc.ps1" -Value $klocContent -Encoding UTF8

$uninstallContent = @'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; Exit }
Write-Host "Uninstalling Kloc v1.0.3..." -ForegroundColor Cyan
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Kloc.ps1" -or $_.Name -match "Kloc.exe" } | Invoke-CimMethod -MethodName Terminate | Out-Null
$installDir = "C:\Program Files\Detaroxz\Kloc"; $appDataDir = "$env:APPDATA\Detaroxz\Kloc"; $commonPrograms = [Environment]::GetFolderPath('CommonPrograms')
if (Test-Path $installDir) { Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $appDataDir) { Remove-Item -Path $appDataDir -Recurse -Force -ErrorAction SilentlyContinue }

$mainShortcutPath = Join-Path $commonPrograms "Kloc.lnk"
if (Test-Path $mainShortcutPath) { Remove-Item $mainShortcutPath -Force -ErrorAction SilentlyContinue }

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Kloc" -ErrorAction SilentlyContinue
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) "Kloc.lnk"
if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName "KlocDesktopClock" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Kloc" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Uninstallation Complete!" -ForegroundColor Green; Start-Sleep -Seconds 2
'@
Set-Content -Path "$installDir\Uninstall.ps1" -Value $uninstallContent -Encoding UTF8

$WshShell = New-Object -ComObject WScript.Shell
$mainShortcutPath = Join-Path $commonPrograms "Kloc.lnk"
$shortcutStart = $WshShell.CreateShortcut($mainShortcutPath)
$shortcutStart.TargetPath = "C:\Program Files\Detaroxz\Kloc\Kloc.exe"
$shortcutStart.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Program Files\Detaroxz\Kloc\Kloc.ps1`""
$shortcutStart.IconLocation = "C:\Program Files\Detaroxz\Kloc\icon.ico"
$shortcutStart.Save()

# --- 7. REGISTRY & LAUNCH ---
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Kloc"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "DisplayName" -Value "Kloc Desktop Clock"; Set-ItemProperty -Path $regPath -Name "DisplayVersion" -Value "1.0.3"; Set-ItemProperty -Path $regPath -Name "Publisher" -Value "Detaroxz"
Set-ItemProperty -Path $regPath -Name "DisplayIcon" -Value "C:\Program Files\Detaroxz\Kloc\icon.ico"
Set-ItemProperty -Path $regPath -Name "UninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\Uninstall.ps1`""
Set-ItemProperty -Path $regPath -Name "NoModify" -Value 1; Set-ItemProperty -Path $regPath -Name "NoRepair" -Value 1

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Installation Complete! Launching Kloc v1.0.3... " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Start-Process -FilePath "$installDir\Kloc.exe" -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installDir\Kloc.ps1`"" -WindowStyle Hidden
Start-Sleep -Seconds 2
