Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
Set colProcs = objWMI.ExecQuery("Select * from Win32_Process Where CommandLine Like '%Kloc.ps1%' OR Name Like '%Kloc.exe%'")
For Each proc in colProcs: proc.Terminate(): Next
WScript.Sleep 800
CreateObject("WScript.Shell").Run """C:\Program Files\Detaroxz\Kloc\Kloc.exe""", 0, False
