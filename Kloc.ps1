Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Inject C# for WorkerW Desktop Binding & Memory Management
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

$currentProcess = Get-Process -Id $PID
$existingProcesses = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "Kloc.ps1" -and $_.ProcessId -ne $PID }
if ($existingProcesses) { Exit }

$appDataFolder = "$env:APPDATA\Detaroxz\Kloc"
$settingsFile = "$appDataFolder\settings.json"
if (-not (Test-Path $appDataFolder)) { New-Item -Path $appDataFolder -ItemType Directory -Force | Out-Null }

$defaultSettings = @{
    ShadowEnabled = $true
    ShowTime = $true; FontTime = "Segoe UI"; SizeTime = 48; TimeBold = $false; TimeItalic = $false; TimeAllCaps = $false
    ShowAmPm = $true; FontAmPm = "Segoe UI"; SizeAmPm = 20; AmPmBold = $false; AmPmItalic = $false; AmPmAllCaps = $false; AmPmOffsetY = 0; AmPmSpacing = 5
    ShowDate = $true; FontDate = "Segoe UI"; SizeDate = 20; DateBold = $false; DateItalic = $false; DateAllCaps = $false
    ShowDay = $true; FontDay = "Segoe UI Light"; SizeDay = 20; DayBold = $false; DayItalic = $false; DayAllCaps = $false
    Alignment = "Center"; DateDaySameLine = $false; DateAboveTime = $false
    AlwaysOnTop = $false; PositionMode = "Centered"; LockPosition = $false; IncludeTaskbarInCenter = $false
    ShowBackground = $false; BackgroundColor = "#000000"; BgOpacity = 50
    ClockColor = "#FFFFFF"; UseAmPm = $false; ShowSeconds = $true; RunAtStartup = $false
    LimitOffset = 200; LimitSpacing = 50; LineSpacing = 0
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

[xml]$clockXAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Kloc" Background="Transparent" AllowsTransparency="True" WindowStyle="None" 
        SizeToContent="WidthAndHeight" ShowInTaskbar="False" Opacity="0">
    <Grid Name="RootGrid" Background="Transparent">
        <StackPanel Name="MainPanel" Margin="15" Background="Transparent" HorizontalAlignment="Center" VerticalAlignment="Center">
            <StackPanel Name="TimePanel" Orientation="Horizontal" Background="Transparent" VerticalAlignment="Center">
                <TextBlock Name="TimeText" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"/>
                <TextBlock Name="AmPmText" VerticalAlignment="Center" Typography.NumeralAlignment="Tabular"/>
            </StackPanel>
            <StackPanel Name="DateDayPanel">
                <TextBlock Name="DateText" Margin="0,0,10,0" Typography.NumeralAlignment="Tabular"/>
                <TextBlock Name="DayText" Typography.NumeralAlignment="Tabular"/>
            </StackPanel>
        </StackPanel>
    </Grid>
</Window>
"@
$reader = New-Object System.Xml.XmlNodeReader $clockXAML
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$RootGrid = $window.FindName("RootGrid")
$MainPanel = $window.FindName("MainPanel")
$DateDayPanel = $window.FindName("DateDayPanel")
$TimePanel = $window.FindName("TimePanel")
$TimeText = $window.FindName("TimeText"); $AmPmText = $window.FindName("AmPmText"); $DateText = $window.FindName("DateText"); $DayText = $window.FindName("DayText")

$window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"file:///C:/Program Files/Detaroxz/Kloc/icon.ico")

$window.Add_MouseLeftButtonDown({ 
    if ($global:Settings.PositionMode -eq "Fixed" -and -not $global:Settings.LockPosition) { $this.DragMove() }
})

function Apply-Layout {
    if ($global:Settings.ShadowEnabled) {
        $getEffect = {
            $eff = New-Object System.Windows.Media.Effects.DropShadowEffect
            $eff.Color = [System.Windows.Media.Colors]::Black; $eff.BlurRadius = 5; $eff.ShadowDepth = 2; $eff.Opacity = 0.8
            return $eff
        }
        $TimeText.Effect = &$getEffect; $AmPmText.Effect = &$getEffect; $DateText.Effect = &$getEffect; $DayText.Effect = &$getEffect
    } else {
        $TimeText.Effect = $null; $AmPmText.Effect = $null; $DateText.Effect = $null; $DayText.Effect = $null
    }

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
    
    try {
        $brush = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($global:Settings.ClockColor)
        $TimeText.Foreground = $brush; $AmPmText.Foreground = $brush; $DateText.Foreground = $brush; $DayText.Foreground = $brush
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

    if ($global:Settings.DateDaySameLine) { $DateDayPanel.Orientation = "Horizontal" } 
    else { $DateDayPanel.Orientation = "Vertical"; $DateText.HorizontalAlignment = $global:Settings.Alignment; $DayText.HorizontalAlignment = $global:Settings.Alignment }

    $MainPanel.Children.Clear()
    $TimePanel.Margin = New-Object System.Windows.Thickness(0,0,0,0)
    $DateDayPanel.Margin = New-Object System.Windows.Thickness(0,0,0,0)
    
    if ($global:Settings.DateAboveTime) { 
        $DateDayPanel.Margin = New-Object System.Windows.Thickness(0,0,0,$global:Settings.LineSpacing)
        $MainPanel.Children.Add($DateDayPanel); $MainPanel.Children.Add($TimePanel) 
    } else { 
        $TimePanel.Margin = New-Object System.Windows.Thickness(0,0,0,$global:Settings.LineSpacing)
        $MainPanel.Children.Add($TimePanel); $MainPanel.Children.Add($DateDayPanel) 
    }

    # --- CALCULATOR & MAX BOUNDS CENTERING LOGIC ---
    $RootGrid.Width = [double]::NaN
    $RootGrid.Height = [double]::NaN
    
    $TimeText.Text = if ($global:Settings.ShowSeconds) { "88:88:88" } else { "88:88" }
    $AmPmText.Text = if ($global:Settings.AmPmAllCaps) { "WM" } else { "wm" }
    $DateText.Text = if ($global:Settings.DateAllCaps) { "SEPTEMBER 88, 8888" } else { "September 88, 8888" }
    $DayText.Text = if ($global:Settings.DayAllCaps) { "WEDNESDAY" } else { "Wednesday" }
    
    $window.UpdateLayout()
    
    # Force WPF to calculate the required memory size before drawing (fixes cropped window bug)
    $RootGrid.Measure((New-Object System.Windows.Size([Double]::PositiveInfinity, [Double]::PositiveInfinity)))
    
    # Lock dimensions (+5 buffer for edge anti-aliasing)
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

function Get-FormattedCase ($str, $isCaps, $isAmPm = $false) {
    if ([string]::IsNullOrEmpty($str)) { return "" }
    if ($isCaps) {
        return $str.ToUpper()
    } else {
        if ($isAmPm) { return $str.ToLower() }
        return $str
    }
}

$script:tickCounter = 0
$script:TickAction = {
    $now = Get-Date

    if ($global:Settings.ShowTime) {
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
    }
    if ($global:Settings.ShowDate) {
        $dStr = Get-FormattedCase ($now.ToString("MMMM dd, yyyy")) $global:Settings.DateAllCaps
        if ($DateText.Text -ne $dStr) { $DateText.Text = $dStr }
    }
    if ($global:Settings.ShowDay) {
        $yStr = Get-FormattedCase ($now.ToString("dddd")) $global:Settings.DayAllCaps
        if ($DayText.Text -ne $yStr) { $DayText.Text = $yStr }
    }

    $script:tickCounter++
    if ($script:tickCounter -ge 60) {
        $script:tickCounter = 0
        [Win32]::TrimMemory()
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({ &$script:TickAction })

function Update-StartupShortcut {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Kloc.lnk"
    if ($global:Settings.RunAtStartup) {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath = "C:\Program Files\Detaroxz\Kloc\Kloc.exe"
        $Shortcut.IconLocation = "C:\Program Files\Detaroxz\Kloc\icon.ico"
        $Shortcut.WindowStyle = 0
        $Shortcut.Save()
    } else {
        if (Test-Path $shortcutPath) { Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue }
    }
}

# --- Settings Window UI ---
function Show-SettingsWindow {
    [xml]$setXAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Kloc Settings" Width="550" Height="680" WindowStartupLocation="CenterScreen" Topmost="True" ResizeMode="NoResize">
        <Grid>
            <TabControl Background="Transparent" BorderThickness="0" Margin="10">
                <TabItem Header="General" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="10">
                            <TextBlock Text="Typography &amp; Fonts" FontWeight="Bold" Margin="0,0,0,15"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="60"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkTime" Content="Time" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontTime" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontTime" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsTime" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            
                            <!-- AM/PM Settings -->
                            <Grid Margin="20,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="100"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkAmPmShow" Content="Show AM/PM" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontAmPm" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontAmPm" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsAmPm" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <Grid Margin="20,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="65"/><ColumnDefinition Width="*"/><ColumnDefinition Width="35"/><ColumnDefinition Width="80"/><ColumnDefinition Width="*"/><ColumnDefinition Width="40"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Spacing:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Slider Name="sldAmPmSpacing" Minimum="-50" Maximum="50" Value="5" Grid.Column="1" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblAmPmSpacing" Text="5" Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                                
                                <TextBlock Text="Vert Offset:" VerticalAlignment="Center" Grid.Column="3" Margin="10,0,0,0"/>
                                <Slider Name="sldAmPmOffsetY" Minimum="-200" Maximum="200" Value="0" Grid.Column="4" VerticalAlignment="Center" TickFrequency="1" IsSnapToTickEnabled="True"/>
                                <TextBlock Name="lblAmPmOffsetY" Text="0" Grid.Column="5" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                            </Grid>

                            <Grid Margin="0,5,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="60"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkDate" Content="Date" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontDate" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontDate" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsDate" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>
                            <Grid Margin="0,0,0,20"><Grid.ColumnDefinitions><ColumnDefinition Width="60"/><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
                                <CheckBox Name="chkDay" Content="Day" Grid.Column="0" VerticalAlignment="Center"/>
                                <Button Name="btnFontDay" Content="Select Font" Grid.Column="1" Padding="5,3"/>
                                <TextBlock Name="lblFontDay" Text="..." Grid.Column="2" VerticalAlignment="Center" Margin="10,0" TextTrimming="CharacterEllipsis"/>
                                <CheckBox Name="chkCapsDay" Content="All Caps" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>

                            <TextBlock Text="Colors &amp; Appearance" FontWeight="Bold" Margin="0,10,0,15"/>
                            <Grid Margin="0,0,0,15"><Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="90"/><ColumnDefinition Width="30"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Clock Text Color:" VerticalAlignment="Center" Grid.Column="0"/>
                                <Button Name="btnClockColor" Content="Pick Color" Grid.Column="1" Padding="5,3"/>
                                <Rectangle Name="rectClockColor" Width="20" Height="20" Grid.Column="2" Stroke="Black" Margin="5,0"/>
                                <TextBlock Name="lblClockColor" Text="#FFFFFF" Grid.Column="3" VerticalAlignment="Center"/>
                            </Grid>

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

                            <TextBlock Text="Time Formatting" FontWeight="Bold" Margin="0,10,0,15"/>
                            <CheckBox Name="chkAmPm" Content="Use 12-Hour Format (AM/PM)" Margin="0,0,0,5"/>
                            <CheckBox Name="chkSeconds" Content="Show Seconds" Margin="0,0,0,10"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>
                <TabItem Header="Advanced" Padding="15,5">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="10">
                            
                            <TextBlock Text="Custom Layout &amp; Slider Limits" FontWeight="Bold" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Spacing between lines (Time &amp; Date):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLineSpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLineSpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                            <Grid Margin="0,0,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="AM/PM Vertical Offset Limit (Â±):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLimitOffset" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLimitOffset" Content="Apply" Grid.Column="2"/>
                            </Grid>
                            <Grid Margin="0,0,0,25"><Grid.ColumnDefinitions><ColumnDefinition Width="220"/><ColumnDefinition Width="60"/><ColumnDefinition Width="60"/></Grid.ColumnDefinitions>
                                <TextBlock Text="AM/PM Spacing Limit (Â±):" VerticalAlignment="Center" Grid.Column="0"/>
                                <TextBox Name="txtLimitSpacing" Grid.Column="1" Margin="0,0,5,0" VerticalContentAlignment="Center"/>
                                <Button Name="btnLimitSpacing" Content="Apply" Grid.Column="2"/>
                            </Grid>
                        
                            <TextBlock Text="Positioning" FontWeight="Bold" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Position Mode:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbPositionMode" Grid.Column="1">
                                    <ComboBoxItem Content="Fixed (Custom)"/>
                                    <ComboBoxItem Content="Centered"/>
                                </ComboBox>
                            </Grid>
                            <CheckBox Name="chkLock" Content="Lock Position (Disable Dragging in Fixed Mode)" Margin="0,0,0,5"/>
                            <CheckBox Name="chkIncludeTaskbar" Content="Include Taskbar in Center Calculation (Whole Monitor)" Margin="0,0,0,25"/>

                            <TextBlock Text="Window &amp; Layout" FontWeight="Bold" Margin="0,0,0,10"/>
                            <Grid Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
                                <TextBlock Text="Window Behavior:" VerticalAlignment="Center" Grid.Column="0"/>
                                <ComboBox Name="cmbMode" Grid.Column="1">
                                    <ComboBoxItem Content="Only on desktop (Immune to Gestures)"/>
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

                            <TextBlock Text="System" FontWeight="Bold" Margin="0,0,0,10"/>
                            <CheckBox Name="chkStartup" Content="Start on Windows Startup (Appears as 'Kloc' in Task Manager)" Margin="0,0,0,10"/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>
                <TabItem Header="About" Padding="15,5">
                    <StackPanel Margin="10" HorizontalAlignment="Center" VerticalAlignment="Center">
                        <TextBlock Text="Kloc Desktop Clock" FontSize="26" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,30,0,5"/>
                        <TextBlock Text="v1.0.0 by Detaroxz" FontSize="14" HorizontalAlignment="Center" Margin="0,0,0,30"/>
                        
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
    $setReader = New-Object System.Xml.XmlNodeReader $setXAML
    $setWindow = [System.Windows.Markup.XamlReader]::Load($setReader)
    $setWindow.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]"file:///C:/Program Files/Detaroxz/Kloc/icon.ico")

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
        
        $global:Settings.ShadowEnabled = ($setWindow.FindName("chkShadow").IsChecked -eq $true)
        $global:Settings.ClockColor = $setWindow.FindName("lblClockColor").Text; $global:Settings.ShowBackground = ($setWindow.FindName("chkShowBg").IsChecked -eq $true)
        $global:Settings.BackgroundColor = $setWindow.FindName("lblBgColor").Text; $global:Settings.BgOpacity = [int]$setWindow.FindName("sldBgOpacity").Value
        $global:Settings.UseAmPm = ($setWindow.FindName("chkAmPm").IsChecked -eq $true); $global:Settings.ShowSeconds = ($setWindow.FindName("chkSeconds").IsChecked -eq $true)
        $global:Settings.PositionMode = if ($setWindow.FindName("cmbPositionMode").SelectedIndex -eq 1) { "Centered" } else { "Fixed" }
        $global:Settings.AlwaysOnTop = if ($setWindow.FindName("cmbMode").SelectedIndex -eq 1) { $true } else { $false }
        $global:Settings.Alignment = $setWindow.FindName("cmbAlign").Text; $global:Settings.LockPosition = ($setWindow.FindName("chkLock").IsChecked -eq $true)
        $global:Settings.IncludeTaskbarInCenter = ($setWindow.FindName("chkIncludeTaskbar").IsChecked -eq $true); $global:Settings.DateDaySameLine = ($setWindow.FindName("chkSameLine").IsChecked -eq $true)
        $global:Settings.DateAboveTime = ($setWindow.FindName("chkDateAbove").IsChecked -eq $true); $global:Settings.RunAtStartup = ($setWindow.FindName("chkStartup").IsChecked -eq $true)

        $setWindow.FindName("btnFontTime").IsEnabled = $global:Settings.ShowTime; $setWindow.FindName("chkCapsTime").IsEnabled = $global:Settings.ShowTime; $setWindow.FindName("lblFontTime").Opacity = if($global:Settings.ShowTime){1}else{0.5}
        
        $amPmEnabled = ($global:Settings.UseAmPm -and $global:Settings.ShowTime)
        $setWindow.FindName("chkAmPmShow").IsEnabled = $amPmEnabled
        $setWindow.FindName("btnFontAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("chkCapsAmPm").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("sldAmPmOffsetY").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm); $setWindow.FindName("sldAmPmSpacing").IsEnabled = ($amPmEnabled -and $global:Settings.ShowAmPm)
        $setWindow.FindName("lblFontAmPm").Opacity = if($amPmEnabled -and $global:Settings.ShowAmPm){1}else{0.5}

        $setWindow.FindName("btnFontDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("chkCapsDate").IsEnabled = $global:Settings.ShowDate; $setWindow.FindName("lblFontDate").Opacity = if($global:Settings.ShowDate){1}else{0.5}
        $setWindow.FindName("btnFontDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("chkCapsDay").IsEnabled = $global:Settings.ShowDay; $setWindow.FindName("lblFontDay").Opacity = if($global:Settings.ShowDay){1}else{0.5}
        $setWindow.FindName("btnBgColor").IsEnabled = $global:Settings.ShowBackground; $setWindow.FindName("sldBgOpacity").IsEnabled = $global:Settings.ShowBackground
        $setWindow.FindName("lblBgTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}; $setWindow.FindName("lblOpacityTitle").Opacity = if($global:Settings.ShowBackground){1}else{0.5}
        $setWindow.FindName("chkLock").IsEnabled = ($global:Settings.PositionMode -eq "Fixed"); $setWindow.FindName("chkIncludeTaskbar").IsEnabled = ($global:Settings.PositionMode -eq "Centered")

        Save-Settings $global:Settings
        Update-StartupShortcut
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
        
        if ($dlg.ShowDialog() -eq 'OK') { return @{ Name=$dlg.Font.FontFamily.Name; Size=($dlg.Font.Size / 0.75); Bold=$dlg.Font.Bold; Italic=$dlg.Font.Italic } }
        return $currentTag
    }
    
    function Prompt-Color($hexStr) {
        $dlg = New-Object System.Windows.Forms.ColorDialog; $dlg.FullOpen = $true
        try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($hexStr) } catch {}
        if ($dlg.ShowDialog() -eq 'OK') { return "#$($dlg.Color.R.ToString('X2'))$($dlg.Color.G.ToString('X2'))$($dlg.Color.B.ToString('X2'))" }
        return $hexStr
    }
    
    function Update-FontLabel($lbl, $tag) {
        $b = if ($tag.Bold) { " Bold" } else { "" }; $i = if ($tag.Italic) { " Italic" } else { "" }
        $lbl.Text = "$($tag.Name), $([math]::Round($tag.Size))pt$b$i"; $lbl.Tag = $tag
    }
    
    function Update-ColorLabel($lbl, $rect, $hex) {
        $lbl.Text = $hex; $rect.Fill = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
    }

    # Initialize Limits in UI
    $setWindow.FindName("sldAmPmOffsetY").Minimum = -$global:Settings.LimitOffset
    $setWindow.FindName("sldAmPmOffsetY").Maximum = $global:Settings.LimitOffset
    $setWindow.FindName("sldAmPmSpacing").Minimum = -$global:Settings.LimitSpacing
    $setWindow.FindName("sldAmPmSpacing").Maximum = $global:Settings.LimitSpacing
    $setWindow.FindName("txtLineSpacing").Text = $global:Settings.LineSpacing.ToString()
    $setWindow.FindName("txtLimitOffset").Text = $global:Settings.LimitOffset.ToString()
    $setWindow.FindName("txtLimitSpacing").Text = $global:Settings.LimitSpacing.ToString()

    $setWindow.FindName("chkTime").IsChecked = $global:Settings.ShowTime; $setWindow.FindName("chkCapsTime").IsChecked = $global:Settings.TimeAllCaps
    Update-FontLabel $setWindow.FindName("lblFontTime") @{ Name=$global:Settings.FontTime; Size=$global:Settings.SizeTime; Bold=$global:Settings.TimeBold; Italic=$global:Settings.TimeItalic }
    
    $setWindow.FindName("chkAmPmShow").IsChecked = $global:Settings.ShowAmPm; $setWindow.FindName("chkCapsAmPm").IsChecked = $global:Settings.AmPmAllCaps
    Update-FontLabel $setWindow.FindName("lblFontAmPm") @{ Name=$global:Settings.FontAmPm; Size=$global:Settings.SizeAmPm; Bold=$global:Settings.AmPmBold; Italic=$global:Settings.AmPmItalic }
    $setWindow.FindName("sldAmPmOffsetY").Value = $global:Settings.AmPmOffsetY; $setWindow.FindName("lblAmPmOffsetY").Text = "$($global:Settings.AmPmOffsetY)"
    $setWindow.FindName("sldAmPmSpacing").Value = $global:Settings.AmPmSpacing; $setWindow.FindName("lblAmPmSpacing").Text = "$($global:Settings.AmPmSpacing)"

    $setWindow.FindName("chkDate").IsChecked = $global:Settings.ShowDate; $setWindow.FindName("chkCapsDate").IsChecked = $global:Settings.DateAllCaps
    Update-FontLabel $setWindow.FindName("lblFontDate") @{ Name=$global:Settings.FontDate; Size=$global:Settings.SizeDate; Bold=$global:Settings.DateBold; Italic=$global:Settings.DateItalic }
    
    $setWindow.FindName("chkDay").IsChecked = $global:Settings.ShowDay; $setWindow.FindName("chkCapsDay").IsChecked = $global:Settings.DayAllCaps
    Update-FontLabel $setWindow.FindName("lblFontDay") @{ Name=$global:Settings.FontDay; Size=$global:Settings.SizeDay; Bold=$global:Settings.DayBold; Italic=$global:Settings.DayItalic }
    
    Update-ColorLabel $setWindow.FindName("lblClockColor") $setWindow.FindName("rectClockColor") $global:Settings.ClockColor
    $setWindow.FindName("chkShadow").IsChecked = $global:Settings.ShadowEnabled
    $setWindow.FindName("chkShowBg").IsChecked = $global:Settings.ShowBackground
    Update-ColorLabel $setWindow.FindName("lblBgColor") $setWindow.FindName("rectBgColor") $global:Settings.BackgroundColor
    $setWindow.FindName("sldBgOpacity").Value = $global:Settings.BgOpacity; $setWindow.FindName("lblBgOpacity").Text = "$($global:Settings.BgOpacity)%"
    $setWindow.FindName("chkAmPm").IsChecked = $global:Settings.UseAmPm; $setWindow.FindName("chkSeconds").IsChecked = $global:Settings.ShowSeconds
    $setWindow.FindName("cmbPositionMode").SelectedIndex = if ($global:Settings.PositionMode -eq "Centered") { 1 } else { 0 }
    $setWindow.FindName("cmbMode").SelectedIndex = if ($global:Settings.AlwaysOnTop) { 1 } else { 0 }
    $setWindow.FindName("cmbAlign").Text = $global:Settings.Alignment; $setWindow.FindName("chkLock").IsChecked = $global:Settings.LockPosition
    $setWindow.FindName("chkIncludeTaskbar").IsChecked = $global:Settings.IncludeTaskbarInCenter
    $setWindow.FindName("chkSameLine").IsChecked = $global:Settings.DateDaySameLine; $setWindow.FindName("chkDateAbove").IsChecked = $global:Settings.DateAboveTime
    $setWindow.FindName("chkStartup").IsChecked = $global:Settings.RunAtStartup

    # Limit Modifiers Logic
    $setWindow.FindName("btnLineSpacing").Add_Click({
        $val = 0; if ([int]::TryParse($setWindow.FindName("txtLineSpacing").Text, [ref]$val)) { $global:Settings.LineSpacing = $val; &$script:UpdateState }
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

    # Explicit Add_Checked/Unchecked to guarantee checkbox state evaluation
    $chkNames = @("chkTime", "chkCapsTime", "chkAmPmShow", "chkCapsAmPm", "chkDate", "chkCapsDate", "chkDay", "chkCapsDay", "chkShadow", "chkShowBg", "chkAmPm", "chkSeconds", "chkLock", "chkIncludeTaskbar", "chkSameLine", "chkDateAbove", "chkStartup")
    foreach ($cName in $chkNames) {
        $cObj = $setWindow.FindName($cName)
        if ($null -ne $cObj) {
            $cObj.Add_Checked({ &$script:UpdateState })
            $cObj.Add_Unchecked({ &$script:UpdateState })
        }
    }

    $setWindow.FindName("cmbPositionMode").Add_DropDownClosed({ &$script:UpdateState })
    $setWindow.FindName("cmbMode").Add_DropDownClosed({ &$script:UpdateState })
    $setWindow.FindName("cmbAlign").Add_DropDownClosed({ &$script:UpdateState })

    $sldOpacity = $setWindow.FindName("sldBgOpacity")
    $sldOpacity.Add_ValueChanged({ $setWindow.FindName("lblBgOpacity").Text = "$($sldOpacity.Value)%" })
    $sldOpacity.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldOpacity.Add_KeyUp({ &$script:UpdateState })
    
    $sldAmPmSpace = $setWindow.FindName("sldAmPmSpacing")
    $sldAmPmSpace.Add_ValueChanged({ $setWindow.FindName("lblAmPmSpacing").Text = "$($sldAmPmSpace.Value)" })
    $sldAmPmSpace.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldAmPmSpace.Add_KeyUp({ &$script:UpdateState })

    $sldAmPmOffset = $setWindow.FindName("sldAmPmOffsetY")
    $sldAmPmOffset.Add_ValueChanged({ $setWindow.FindName("lblAmPmOffsetY").Text = "$($sldAmPmOffset.Value)" })
    $sldAmPmOffset.Add_PreviewMouseLeftButtonUp({ &$script:UpdateState }); $sldAmPmOffset.Add_KeyUp({ &$script:UpdateState })

    $setWindow.FindName("btnFontTime").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontTime") (Prompt-Font $setWindow.FindName("lblFontTime").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontAmPm").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontAmPm") (Prompt-Font $setWindow.FindName("lblFontAmPm").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontDate").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontDate") (Prompt-Font $setWindow.FindName("lblFontDate").Tag); &$script:UpdateState })
    $setWindow.FindName("btnFontDay").Add_Click({ Update-FontLabel $setWindow.FindName("lblFontDay") (Prompt-Font $setWindow.FindName("lblFontDay").Tag); &$script:UpdateState })
    $setWindow.FindName("btnClockColor").Add_Click({ Update-ColorLabel $setWindow.FindName("lblClockColor") $setWindow.FindName("rectClockColor") (Prompt-Color $setWindow.FindName("lblClockColor").Text); &$script:UpdateState })
    $setWindow.FindName("btnBgColor").Add_Click({ Update-ColorLabel $setWindow.FindName("lblBgColor") $setWindow.FindName("rectBgColor") (Prompt-Color $setWindow.FindName("lblBgColor").Text); &$script:UpdateState })
    
    $setWindow.FindName("btnRepo").Add_Click({ Start-Process "https://github.com/avm3005/Kloc" })
    $setWindow.FindName("btnWeb").Add_Click({ Start-Process "https://avm3005.github.io/portfolio/" })
    $setWindow.FindName("btnDarkSwitch").Add_Click({ Start-Process "https://github.com/avm3005/DarkSwitch" })
    $setWindow.FindName("btnSortFE").Add_Click({ Start-Process "https://github.com/avm3005/SortFE" })

    $setWindow.Add_Closed({ [Win32]::TrimMemory() })
    $setWindow.ShowDialog() | Out-Null
}

$window.Add_Loaded({
    $script:clockHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    # Hide from Alt+Tab
    $exStyle = [Win32]::GetWindowLong($script:clockHwnd, -20)
    [Win32]::SetWindowLong($script:clockHwnd, -20, $exStyle -bor 0x00000080) | Out-Null
    
    Apply-Layout
    &$script:TickAction
    
    if ($global:Settings.AlwaysOnTop) {
        $window.Topmost = $true
    } else {
        $window.Topmost = $false
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
