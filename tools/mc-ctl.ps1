# mc-ctl.ps1 - 对正在运行的 Minecraft 窗口做无侵入操作：聚焦、按键、聊天命令、截图
#
# 用法（Windows PowerShell 5.1）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-ctl.ps1 -Action shot
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-ctl.ps1 -Action reload
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-ctl.ps1 -Action chat -Text "/time set 12500"
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-ctl.ps1 -Action key -Key F3
#
# 设计要点：
# - 不重新启动游戏，直接接管已运行的 MC 窗口（用户同意实机操控）
# - 截图优先 F2（游戏原生截图，带 UI 无黑边），失败则用 GDI 截窗口
# - 聊天命令走「剪贴板 + Ctrl+V」，绕开中文输入法
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("shot", "reload", "chat", "key", "capture", "focus", "info", "look", "session")]
    [string]$Action,

    [string]$Text = "",
    [string]$Key = "",
    [string]$OutDir = "",
    [string]$Chats = "",
    [switch]$Resume,
    [switch]$ReloadFirst,
    [int]$ReloadWait = 13000,
    [int]$DX = 0,
    [int]$DY = 0,
    [int]$WaitMs = 4000
)

$ErrorActionPreference = "Stop"

if (-not ("Win32Mc" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32Mc {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);

    public static bool Focus(IntPtr hWnd) {
        if (IsIconic(hWnd)) ShowWindow(hWnd, 9);
        ShowWindow(hWnd, 5);
        uint pid; uint tid = GetWindowThreadProcessId(hWnd, out pid);
        uint cur = GetCurrentThreadId();
        for (int attempt = 0; attempt < 3; attempt++) {
            AttachThreadInput(cur, tid, true);
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            AttachThreadInput(cur, tid, false);
            // ALT tap unlock: allows SetForegroundWindow from background apps
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            keybd_event(0x12, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            System.Threading.Thread.Sleep(150);
            if (GetForegroundWindow() == hWnd) return true;
        }
        return GetForegroundWindow() == hWnd;
    }

    public static void Tap(byte vk) {
        keybd_event(vk, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        System.Threading.Thread.Sleep(60);
    }
}
"@
}

function Get-McWindow {
    $procs = Get-Process java, javaw -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match "Minecraft"
    }
    if (-not $procs) { return $null }
    return ($procs | Sort-Object StartTime -Descending | Select-Object -First 1)
}

function Focus-Mc($proc) {
    [Win32Mc]::Focus($proc.MainWindowHandle)
}

function Send-TextToChat([string]$message) {
    Set-Clipboard -Value $message
    Start-Sleep -Milliseconds 150
    # T 打开聊天栏（中文界面同样是 T）
    [Win32Mc]::Tap(0x54)
    Start-Sleep -Milliseconds 350
    # Ctrl+V 粘贴
    [Win32Mc]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)      # Ctrl down
    [Win32Mc]::Tap(0x56)                                      # V
    [Win32Mc]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)      # Ctrl up
    Start-Sleep -Milliseconds 250
    [Win32Mc]::Tap(0x0D)                                      # Enter
    Start-Sleep -Milliseconds 250
}

function New-Screenshot([string]$dir) {
    $proc = Get-McWindow
    if (-not $proc) { throw "Minecraft window not found" }
    Focus-Mc $proc
    Start-Sleep -Milliseconds 400

    $shotsDir = "C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4\screenshots"
    New-Item -ItemType Directory -Force -Path $shotsDir | Out-Null
    $before = @(Get-ChildItem $shotsDir -Filter *.png -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

    [Win32Mc]::Tap(0x71)  # F2
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        $after = Get-ChildItem $shotsDir -Filter *.png -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($after -and ($before -notcontains $after.FullName)) {
            # wait until the PNG is fully written (MC writes async, file can be 0 bytes)
            $stable = 0
            $lastLen = -1
            for ($i = 0; $i -lt 40; $i++) {
                Start-Sleep -Milliseconds 250
                $len = (Get-Item $after.FullName -ErrorAction SilentlyContinue).Length
                if ($len -gt 0 -and $len -eq $lastLen) { $stable++; if ($stable -ge 2) { break } } else { $stable = 0 }
                $lastLen = $len
            }
            Start-Sleep -Milliseconds 200
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            $dest = Join-Path $dir ("game-" + $after.LastWriteTime.ToString("HHmmss") + ".png")
            Copy-Item $after.FullName $dest -Force
            return $dest
        }
    }

    # 回退：截窗口
    return (Capture-Window $proc $dir)
}

function Capture-Window($proc, [string]$dir) {
    Add-Type -AssemblyName System.Drawing
    $hwnd = $proc.MainWindowHandle
    $rect = New-Object Win32Mc+RECT
    [Win32Mc]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { throw "bad window rect" }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir ("window-" + (Get-Date).ToString("HHmmss") + ".png")
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return $dest
}

$proc = Get-McWindow
if (-not $proc) { Write-Output "NO_MC_WINDOW"; exit 2 }

if (-not $OutDir) { $OutDir = Join-Path (Split-Path $PSScriptRoot -Parent) "shots" }

switch ($Action) {
    "info" {
        Write-Output ("PID=" + $proc.Id + " TITLE=" + $proc.MainWindowTitle + " HWND=" + $proc.MainWindowHandle)
    }
    "focus" {
        $ok = [Win32Mc]::Focus($proc.MainWindowHandle)
        Start-Sleep -Milliseconds 250
        $fg = [Win32Mc]::GetForegroundWindow()
        Write-Output ("focused=" + $ok + " fg=" + $fg + " target=" + $proc.MainWindowHandle)
    }
    "reload" {
        Focus-Mc $proc
        Start-Sleep -Milliseconds 300
        [Win32Mc]::Tap(0x52)   # R = Iris reload shaders
        Write-Output "reload key sent"
    }
    "key" {
        if (-not $Key) { throw "-Key required" }
        Focus-Mc $proc
        $vk = 0
        if ($Key -eq "ESC") { $vk = 0x1B }
        elseif ($Key -eq "ENTER") { $vk = 0x0D }
        elseif ($Key -eq "TAB") { $vk = 0x09 }
        elseif ($Key -eq "SPACE") { $vk = 0x20 }
        elseif ($Key -match "^F(\d+)$") { $vk = 0x70 + [int]$Matches[1] - 1 }
        elseif ($Key.Length -eq 1) { $vk = [int][char]([char]::ToUpper($Key)) }
        else { throw "unsupported key: $Key" }
        [Win32Mc]::Tap([byte]$vk)
        Write-Output "key $Key sent"
    }
    "chat" {
        if (-not $Text) { throw "-Text required" }
        Focus-Mc $proc
        Start-Sleep -Milliseconds 300
        Send-TextToChat $Text
        Write-Output ("chat sent: " + $Text)
    }
    "look" {
        Focus-Mc $proc
        Start-Sleep -Milliseconds 250
        [Win32Mc]::mouse_event(0x0001, $DX, $DY, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 350
        Write-Output ("look dx=" + $DX + " dy=" + $DY)
    }
    "session" {
        # One shot with everything in a single focused pass: the game pauses when
        # it loses focus between script invocations, so resume + chat + reload +
        # screenshot must happen while the window is foreground.
        Focus-Mc $proc | Out-Null
        Start-Sleep -Milliseconds 400
        if ($Resume) {
            [Win32Mc]::Tap(0x1B)   # ESC closes the pause menu
            Start-Sleep -Milliseconds 800
        }
        foreach ($message in ($Chats -split "\|")) {
            if (-not $message) { continue }
            Send-TextToChat $message
            Start-Sleep -Milliseconds 350
        }
        if ($ReloadFirst) {
            [Win32Mc]::Tap(0x52)
            Start-Sleep -Milliseconds $ReloadWait
        }
        Start-Sleep -Milliseconds $WaitMs
        $path = New-Screenshot $OutDir
        Write-Output ("SHOT=" + $path)
    }
    "shot" {
        $path = New-Screenshot $OutDir
        Write-Output ("SHOT=" + $path)
    }
    "capture" {
        $path = Capture-Window $proc $OutDir
        Write-Output ("SHOT=" + $path)
    }
}
