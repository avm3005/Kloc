Take a small survey if you want to: https://forms.gle/6cGvSZkkysyzptkWA
# 🕒 Kloc Desktop Clock

![Windows Support](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?style=flat-square&logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

**Kloc** is a beautiful, ultra-lightweight, and fully customizable desktop clock and quote widget for Windows. 

Unlike Electron-based widgets or heavy customization engines like Rainmeter, Kloc requires **zero external dependencies**. It uses native PowerShell, C#, and WPF to dynamically compile itself directly onto your machine, resulting in a near-zero CPU footprint and aggressive RAM optimization (~10–15 MB).

<div align="center">
  <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/51723eeb-07ef-4bea-af0e-d6719f94935f" />
  <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/bf35f3d2-5a92-47cd-9608-900e63e4f6ec" />
  <img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/89cb183a-6497-4a9c-8b31-b3ffde3f911c" />
  <img src="https://via.placeholder.com/800x400.png?text=Screenshot+of+Kloc+on+Desktop" alt="Kloc Screenshots" width="800"/>
</div>

---

## ✨ Features

* **Immune to `Win + D`:** Kloc anchors itself directly to the Windows Desktop layer (`WorkerW` handle), meaning it stays beautifully pinned behind your icons and ignores "Show Desktop" commands.
* **Aggressive Memory Management:** Uses native Win32 garbage collection hooks (`SetProcessWorkingSetSize`) and a dynamic tick-rate engine to keep RAM usage incredibly low. It even goes to "sleep" (suspending timers) if you choose to only display static text like dates or quotes.
* **Silent Execution:** Includes a native VBScript wrapper that entirely bypasses the annoying Windows 11 Terminal popups upon launch.
* **Fully Customizable UI:** A sleek, built-in settings panel lets you adjust:
  * Fonts, styles (Bold/Italic/All Caps), and sizes independently for Time, AM/PM, Date, Day, and Quotes.
  * Colors (Global or individual per element) and background opacity.
  * Custom X/Y coordinate limits, alignments, and specific pixel spacing.
* **Zero Bloat Installer:** The single-file `Install-Kloc.ps1` script handles everything. It dynamically renders SVG data into high-fidelity `.ico` files via native GDI+, compiles a background C# `.exe` wrapper, and sets up your environment automatically.
* **Import / Export Settings:** Save your perfect layout as a JSON file and share it with others.

## 🚀 Installation

1. Open Terminal(powershell) as administrator
2. Paste the following command and click enter
   ```
   iex (irm https://raw.githubusercontent.com/avm3005/Kloc/main/Setup/setup.ps1)
   ```
3. The console will prompt you to pick a starting preset:
   * `[1]` Only big day (Black)
   * `[2]` Only big time (White)
   * `[3]` Balanced Default (Day, Date, and Time)
4. Done! Kloc will automatically launch and place an icon in your System Tray.

## ⚙️ Configuration & Usage

Once running, Kloc lives quietly in your System Tray (bottom right of your taskbar). 
* **To open Settings:** Right-click the green Kloc tray icon and select **Settings**.
* **To move the clock:** In Settings, change *Position Mode* to "Fixed (Custom)" and ensure "Lock Position" is unchecked. You can now click and drag the clock anywhere on your screen.

Kloc natively supports adding itself to your startup routine via the Advanced tab (Startup Folder, Registry, or Scheduled Task).

## 🛠️ Architecture & Under the Hood

Kloc is an experiment in pushing the limits of what a raw PowerShell script can do without relying on heavy visual frameworks:
* **UI Rendering:** Pure XAML read dynamically via `XmlReader` into `[System.Windows.Markup.XamlReader]`.
* **C# Integration:** Uses `Add-Type` and `[DllImport]` to hook into deep Windows user32/kernel32 DLLs.
* **Dual Icon Engine:** The installer parses raw SVG markup, scales it using `HighQualityBicubic` interpolation, and writes raw binary `byte[]` arrays to generate both a 256x256 application icon and an ultra-crisp 64x64 system tray icon.

## 🗑️ Uninstallation

If you wish to remove Kloc from your system:
1. Open Windows Settings > **Apps** > **Installed Apps**.
2. Search for **Kloc Desktop Clock** and click Uninstall.
3. The uninstaller will safely clean up all app data, registry keys, scheduled tasks, and program files.

---

### Author
Created by **[Detaroxz](https://github.com/avm3005)**. 
Also check out my other tools: [DarkSwitch](https://github.com/avm3005/DarkSwitch) | [SortFE](https://github.com/avm3005/SortFE)
