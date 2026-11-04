#requires -Version 5.1
<#
.SYNOPSIS
    One-command Minecraft real-machine validation run for the Zephyr shader pack.

.DESCRIPTION
    Launch (reusing PCL's LatestLaunch.bat java command) -> quickPlay into a world
    -> wait for world load / Iris pipeline creation -> send chat commands
    -> press F2 for screenshots -> collect logs -> quit game -> restore options.txt
    -> write evidence into reports/ and shots/.

    Nothing under shaders/ is written. config/iris.properties is set to the requested
    pack and is kept afterwards (use -RestoreIris to put back the pre-run backup);
    options.txt is backed up first and restored at the end.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-test.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-test.ps1 -ShaderPack Zephyr -World "Weston City V0.3"
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\mc-test.ps1 -CloseExisting
    tools\mc-test.bat -DryRun
#>
[CmdletBinding()]
param(
    [string]$ShaderPack = 'Zephyr',
    [string]$World      = 'Weston City V0.3',
    [int]$Width         = 1280,
    [int]$Height        = 720,
    [string[]]$Commands = @('/time set 12500', '/gamerule doDaylightCycle false', '/weather rain'),
    [int]$SettleSeconds = 12,
    [int]$StartupTimeoutSeconds = 180,
    [int]$JoinTimeoutSeconds = 360,
    [int]$QuitTimeoutSeconds = 120,
    [int]$ShotCount = 2,
    [int]$ShotIntervalSeconds = 6,
    [string]$VersionDir = '',
    [string]$LaunchBat  = 'C:\Users\liubingliang\Downloads\PCL-2.12.2\PCL\LatestLaunch.bat',
    [string]$Workspace  = '',
    [switch]$CloseExisting,
    [switch]$KeepGame,
    [switch]$SkipCommands,
    [switch]$NoRestore,
    [switch]$RestoreIris,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:StartedAt = Get-Date

function Write-Utf8File {
    param([string]$Path, [string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

# ---------------------------------------------------------------- paths -----
if (-not $Workspace) { $Workspace = Split-Path -Parent $PSScriptRoot }
if (-not $VersionDir) { $VersionDir = Split-Path -Parent (Split-Path -Parent $Workspace) }

$shaderpacksDir = Join-Path $VersionDir 'shaderpacks'
$packDir        = Join-Path $shaderpacksDir $ShaderPack
$savesDir       = Join-Path $VersionDir 'saves'
$irisCfg        = Join-Path $VersionDir 'config\iris.properties'
$optionsTxt     = Join-Path $VersionDir 'options.txt'
$latestLog      = Join-Path $VersionDir 'logs\latest.log'
$screenshotsDir = Join-Path $VersionDir 'screenshots'

$reportsDir     = Join-Path $Workspace 'reports'
$shotsDir       = Join-Path $Workspace 'shots'
$toolsDir       = Join-Path $Workspace 'tools'
$backupDir      = Join-Path $reportsDir 'backup'
foreach ($d in @($reportsDir, $shotsDir, $toolsDir, $backupDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

$stamp      = $script:StartedAt.ToString('yyyyMMdd-HHmmss')
$runDir     = Join-Path $reportsDir ("run-$stamp")
if (-not (Test-Path -LiteralPath $runDir)) { New-Item -ItemType Directory -Force -Path $runDir | Out-Null }
$runLog     = Join-Path $runDir 'run.log'
$consoleLog = Join-Path $reportsDir 'mc-console.log'
$consoleErr = Join-Path $reportsDir 'mc-console.err.log'

$script:LogLines = New-Object System.Collections.Generic.List[string]
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    $script:LogLines.Add($line)
    Write-Host $line
}

# ------------------------------------------------------------ win32 glue -----
$cs = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class MCWin {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static string ClassName(IntPtr h) {
        var sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }

    public static List<IntPtr> FindWindowsForPid(uint pid) {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h) && GetWindowTextLength(h) > 0) list.Add(h);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static string Title(IntPtr h) {
        var sb = new StringBuilder(GetWindowTextLength(h) + 2);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }

    public static bool Focus(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9);   // SW_RESTORE
        ShowWindow(h, 5);                    // SW_SHOW
        IntPtr fg = GetForegroundWindow();
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(fg, out fgPid);
        uint myThread = GetCurrentThreadId();
        bool attached = false;
        try {
            if (fgThread != 0 && fgThread != myThread) attached = AttachThreadInput(myThread, fgThread, true);
            SetForegroundWindow(h);
            SetFocus(h);
        } finally {
            if (attached) AttachThreadInput(myThread, fgThread, false);
        }
        Thread.Sleep(400);
        return GetForegroundWindow() == h;
    }

    public static IntPtr Foreground() { return GetForegroundWindow(); }

    public static void KeyDown(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
    public static void KeyUp(byte vk)   { keybd_event(vk, 0, 2, UIntPtr.Zero); }
    public static void KeyPress(byte vk, int holdMs) {
        KeyDown(vk); Thread.Sleep(holdMs); KeyUp(vk); Thread.Sleep(100);
    }
    public static void KeyCombo(byte mod, byte vk) {
        KeyDown(mod); Thread.Sleep(70); KeyPress(vk, 40); KeyUp(mod); Thread.Sleep(100);
    }
    public static void TypeUnicodeChar(char c) {
        keybd_event(0, (byte)(c & 0xFF), 4, UIntPtr.Zero);  // KEYEVENTF_UNICODE down
        Thread.Sleep(20);
        keybd_event(0, (byte)(c & 0xFF), 6, UIntPtr.Zero);  // KEYEVENTF_UNICODE up
        Thread.Sleep(20);
    }
    public static void TypeAscii(string s) { foreach (char c in s) TypeUnicodeChar(c); }
    public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }  // WM_CLOSE
}
'@
Add-Type -TypeDefinition $cs -Language CSharp | Out-Null

# -------------------------------------------------------------- helpers -----
function Get-LogText {
    param([string]$Path, [int]$MaxBytes = 800000)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($fs.Length -gt $MaxBytes) { [void]$fs.Seek($fs.Length - $MaxBytes, [System.IO.SeekOrigin]::Begin) }
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            return $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return '' }
}

function Get-KnotClientProcesses {
    $list = @()
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            if ($p.CommandLine -and ($p.CommandLine -match 'KnotClient')) {
                $np = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
                $h = [IntPtr]::Zero
                if ($np) { $h = $np.MainWindowHandle }
                $list += New-Object PSObject -Property @{
                    Pid          = [int]$p.ProcessId
                    CreationDate = $p.CreationDate
                    Cmd          = [string]$p.CommandLine
                    Handle       = $h
                    Title        = if ($np) { [string]$np.MainWindowTitle } else { '' }
                }
            }
        }
    } catch { }
    return @($list)
}

function Get-McWindow {
    param([int]$ProcessId, [int]$TimeoutSeconds = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $proc) { return [IntPtr]::Zero }
        $best = [IntPtr]::Zero
        foreach ($wh in [MCWin]::FindWindowsForPid([uint32]$ProcessId)) {
            $title = [MCWin]::Title($wh)
            $class = [MCWin]::ClassName($wh)
            $isGameWindow = ($title -match '(?i)minecraft') -or ($class -match '(?i)^(GLFW|LWJGL)') -or ($class -match '(?i)GLFW')
            if ($isGameWindow) { return $wh }
            if ($best -eq [IntPtr]::Zero) { $best = $wh }
        }
        if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
            $title = [MCWin]::Title($proc.MainWindowHandle)
            $class = [MCWin]::ClassName($proc.MainWindowHandle)
            if (($title -match '(?i)minecraft') -or ($class -match '(?i)GLFW|LWJGL')) { return $proc.MainWindowHandle }
        }
        Start-Sleep -Milliseconds 500
    }
    return [IntPtr]::Zero
}

function Get-LogSessionMarker {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $txt = Get-LogText -Path $Path
    if (-not $txt) { return '' }
    $lines = @($txt -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -eq 0) { return '' }
    return $lines[0].Trim()
}

function Test-NewLogSession {
    param([string]$Path, [string]$OldMarker)
    if (-not $OldMarker) { return $true }
    $txt = Get-LogText -Path $Path
    if (-not $txt) { return $false }
    return (-not ($txt.Contains($OldMarker)))
}

function Focus-McWindow {
    param([IntPtr]$Handle)
    for ($i = 1; $i -le 6; $i++) {
        if ([MCWin]::Focus($Handle)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    return ([MCWin]::Foreground() -eq $Handle)
}

function Send-ChatCommand {
    param([IntPtr]$Handle, [string]$Text, [switch]$UseClipboard)
    [void](Focus-McWindow -Handle $Handle)
    Start-Sleep -Milliseconds 500
    [MCWin]::KeyPress(0xBF, 40)      # '/' opens the command chat with a slash pre-filled
    Start-Sleep -Milliseconds 800
    if ($UseClipboard) {
        try { Set-Clipboard -Value $Text } catch { }
        [MCWin]::KeyCombo(0x11, 0x56)  # Ctrl+V
        Start-Sleep -Milliseconds 600
    } else {
        [MCWin]::TypeAscii($Text)
        Start-Sleep -Milliseconds 500
    }
    [MCWin]::KeyPress(0x0D, 40)      # Enter
    Start-Sleep -Milliseconds 900
}

function Get-NewestScreenshot {
    param([datetime]$After, [string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    $items = @(Get-ChildItem -LiteralPath $Dir -Filter '*.png' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $After } | Sort-Object LastWriteTime -Descending)
    if ($items.Count -gt 0) { return $items[0] }
    return $null
}

function Save-WindowShot {
    param([IntPtr]$Handle, [string]$OutPath)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $r = [MCWin+RECT]::new()
        [void][MCWin]::GetWindowRect($Handle, [ref]$r)
        $w = [Math]::Max(1, $r.Right - $r.Left); $h = [Math]::Max(1, $r.Bottom - $r.Top)
        $bmp = New-Object System.Drawing.Bitmap $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
        $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        return $true
    } catch { Write-Log ("window screenshot failed: " + $_.Exception.Message) 'WARN'; return $false }
}

function Save-DesktopShot {
    param([string]$OutPath)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        return $true
    } catch { Write-Log ("desktop screenshot failed: " + $_.Exception.Message) 'WARN'; return $false }
}

function Stop-OwnGame {
    param([int]$ProcessId, [IntPtr]$Handle, [int]$TimeoutSeconds = 120)
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) { return 'already-exited' }
    Write-Log 'requesting graceful quit (CloseMainWindow / WM_CLOSE)'
    $closed = $false
    try { if ($proc.CloseMainWindow()) { $closed = $true } } catch { }
    if ($Handle -ne [IntPtr]::Zero) { [MCWin]::CloseWindow($Handle) }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 700
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $proc) { if ($closed) { return 'close-main-window' } else { return 'wm-close' } }
    }
    # last resort: only kill our own java (verify PID -> KnotClient + game dir)
    $ci = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $ProcessId) -ErrorAction SilentlyContinue
    $isOurs = ($ci -and $ci.CommandLine -and ($ci.CommandLine -match 'KnotClient') -and ($ci.CommandLine -match [regex]::Escape($VersionDir)))
    if (-not $isOurs) {
        Write-Log 'refusing Stop-Process: PID does not match our Minecraft launch' 'WARN'
        return 'not-ours'
    }
    Write-Log 'game did not exit after graceful close, forcing Stop-Process (verified KnotClient PID)' 'WARN'
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Seconds 2
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($proc) { return 'force-failed' }
    return 'forced'
}

function Extract-IrisEvidence {
    param([string]$LogText, [string]$PackName)
    if ($LogText) { $lines = $LogText -split "`r?`n" } else { $lines = @() }
    $usage    = @($lines | Where-Object { $_ -match 'Using shaderpack:' })
    $pipeline = @($lines | Where-Object { $_ -match 'Creating pipeline|Destroying pipeline|Reloading pipeline on dimension change' })
    $fatal    = @($lines | Where-Object {
        ($_ -match 'Failed to create shader rendering pipeline') -or
        ($_ -match 'ShaderCompileException') -or
        ($_ -match 'Shader compilation log for') -or
        ($_ -match 'Failed to compile') -or
        ($_ -match 'Unable to load shaderpack') -or
        ($_ -match 'Shader ?pack .*(failed|invalid)') -or
        ($_ -match 'not a valid shader') -or
        ($_ -match 'Failed to load shader')
    })
    $errors   = @($lines | Where-Object { $_ -match '\[[^\]]*/ERROR\]:' })
    $warns    = @($lines | Where-Object { ($_ -match '\[[^\]]*/WARN\]:') -and ($_ -match 'hader|Iris|pipeline|uniform|program|GL |OpenGL') })
    $joined   = @($lines | Where-Object { $_ -match 'joined the game|Loaded \d+ chunks|Loaded \d+ advancements' })
    $packSeen = $false
    foreach ($l in $usage) { if ($l -match [regex]::Escape('Using shaderpack: ' + $PackName)) { $packSeen = $true } }
    $glInfo   = @($lines | Where-Object { $_ -match '\[GL\]|OpenGL|GPU|GL_VERSION|GL_RENDERER|GL_VENDOR' })
    return New-Object PSObject -Property @{
        UsageLines    = $usage
        PipelineLines = $pipeline
        FatalLines    = $fatal
        ErrorLines    = $errors
        WarnLines     = $warns
        JoinLines     = $joined
        GlLines       = $glInfo
        PackSeen      = $packSeen
        CompileFailed = ($fatal.Count -gt 0)
    }
}

function Write-IrisErrorsFile {
    param([string]$Path, [object]$Evidence, [string]$PackName)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Iris shader evidence')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('- expected shaderpack: {0}' -f $PackName))
    [void]$sb.AppendLine(('- shaderpack line seen in log: {0}' -f $Evidence.PackSeen))
    [void]$sb.AppendLine(('- compile/load failure detected: {0}' -f $Evidence.CompileFailed))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [1] shaderpack load lines')
    if ($Evidence.UsageLines.Count -gt 0) { foreach ($l in $Evidence.UsageLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [2] pipeline lines')
    if ($Evidence.PipelineLines.Count -gt 0) { foreach ($l in $Evidence.PipelineLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [3] COMPILE / LOAD FAILURES (fatal)')
    if ($Evidence.FatalLines.Count -gt 0) { foreach ($l in $Evidence.FatalLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [4] other ERROR lines')
    if ($Evidence.ErrorLines.Count -gt 0) { foreach ($l in $Evidence.ErrorLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [5] shader related WARN lines')
    if ($Evidence.WarnLines.Count -gt 0) { foreach ($l in $Evidence.WarnLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [6] world join lines')
    if ($Evidence.JoinLines.Count -gt 0) { foreach ($l in $Evidence.JoinLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## [7] GL / GPU lines')
    if ($Evidence.GlLines.Count -gt 0) { foreach ($l in $Evidence.GlLines) { [void]$sb.AppendLine($l) } } else { [void]$sb.AppendLine('(none)') }
    Write-Utf8File -Path $Path -Text $sb.ToString()
}

function Write-LaunchReport {
    param([string]$Path, [object]$Result, [object]$Evidence)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Minecraft Iris real-machine validation report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
    [void]$sb.AppendLine(('- verdict: **{0}** (phase `{1}`)' -f $Result.status, $Result.phase))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Configuration')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| item | value |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine(('| shaderpack | `{0}` |' -f $Result.shaderPack))
    [void]$sb.AppendLine(('| world (quickPlaySingleplayer) | `{0}` |' -f $Result.world))
    [void]$sb.AppendLine(('| resolution | {0}x{1} |' -f $Result.width, $Result.height))
    [void]$sb.AppendLine(('| game dir | `{0}` |' -f $Result.versionDir))
    [void]$sb.AppendLine(('| java pid | {0} |' -f $Result.launchPid))
    [void]$sb.AppendLine(('| window title | {0} |' -f $Result.windowTitle))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Timeline')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| milestone | seconds since launch |')
    [void]$sb.AppendLine('|---|---|')
    foreach ($k in @('windowSeconds', 'shaderpackSeconds', 'pipelineSeconds', 'joinSeconds', 'quitSeconds', 'totalSeconds')) {
        if ($Result.timings.Contains($k)) { [void]$sb.AppendLine(('| {0} | {1} |' -f $k, $Result.timings[$k])) }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Shader verification')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- `Using shaderpack: {0}` found: {1}' -f $Result.shaderPack, $Result.shaderpackSeen))
    [void]$sb.AppendLine(('- Iris pipeline created: {0}' -f $Result.pipelineSeen))
    [void]$sb.AppendLine(('- joined world: {0}' -f $Result.joined))
    [void]$sb.AppendLine(('- compile/load failure: {0}' -f $Result.compileFailed))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Chat commands sent')
    [void]$sb.AppendLine('')
    if ($Result.commandAcks.Count -gt 0) {
        [void]$sb.AppendLine('| command | confirmed in latest.log (`issued server command`) |')
        [void]$sb.AppendLine('|---|---|')
        foreach ($c in $Result.commandAcks) { [void]$sb.AppendLine(('| `{0}` | {1} |' -f $c.command, $c.acked)) }
    } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Screenshots')
    [void]$sb.AppendLine('')
    if ($Result.screenshots.Count -gt 0) { foreach ($s in $Result.screenshots) { [void]$sb.AppendLine(('- `{0}`' -f $s)) } } else { [void]$sb.AppendLine('(none)') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Notes / issues')
    [void]$sb.AppendLine('')
    if ($Result.notes.Count -gt 0) { foreach ($n in $Result.notes) { [void]$sb.AppendLine(('- {0}' -f $n)) } } else { [void]$sb.AppendLine('(none)') }
    if ($Result.error) { [void]$sb.AppendLine(('- error: {0}' -f $Result.error)) }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Evidence files')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('- `reports/iris-errors.txt` (extracted Iris lines)'))
    [void]$sb.AppendLine(('- `reports/last-run.json` (machine readable metrics)'))
    [void]$sb.AppendLine(('- `{0}` (full game log of this run)' -f (Join-Path $runDir 'latest.log')))
    [void]$sb.AppendLine('')
    Write-Utf8File -Path $Path -Text $sb.ToString()
}

# ------------------------------------------------------------ pre-flight ----
Write-Log '=== mc-test.ps1 starting ==='
Write-Log ('powershell : ' + $PSVersionTable.PSVersion.ToString())
Write-Log ('workspace  : ' + $Workspace)
Write-Log ('versionDir : ' + $VersionDir)
Write-Log ('shaderpack : ' + $ShaderPack + '  (dir exists: ' + (Test-Path -LiteralPath $packDir) + ')')
Write-Log ('world      : ' + $World + '  (save exists: ' + (Test-Path -LiteralPath (Join-Path $savesDir $World)) + ')')
Write-Log ('latest.log : ' + $latestLog)
Write-Log ('resolution : ' + $Width + 'x' + $Height)

if (-not (Test-Path -LiteralPath $packDir)) { throw "shaderpack directory not found: $packDir" }
if (-not (Test-Path -LiteralPath (Join-Path $savesDir $World))) { throw "world save not found: $(Join-Path $savesDir $World)" }
if (-not (Test-Path -LiteralPath $LaunchBat)) { throw "launch bat not found: $LaunchBat" }

# ------------------------------------------------------------ launch line ---
$batLines = [System.IO.File]::ReadAllLines($LaunchBat, [System.Text.Encoding]::UTF8)
$javaLine = $batLines | Where-Object { $_ -match 'KnotClient' } | Select-Object -First 1
if (-not $javaLine) { throw "no KnotClient java command line found in $LaunchBat" }
$jv = [regex]::Match($javaLine, '^"([^"]+)"')
if (-not $jv.Success) { throw 'could not parse java executable from launch bat' }
$javaExe  = $jv.Groups[1].Value
$javaArgs = $javaLine.Substring($jv.Length).Trim()
$javaArgs = [regex]::Replace($javaArgs, '\s--width\s+\d+\s+--height\s+\d+\s*$', '')
$javaArgs = [regex]::Replace($javaArgs, '\s--quickPlaySingleplayer\s+("[^"]*"|\S+)', '')
$javaArgs = $javaArgs.TrimEnd() + (' --width {0} --height {1} --quickPlaySingleplayer "{2}"' -f $Width, $Height, $World)

Write-Log ('java exe   : ' + $javaExe)
Write-Log ('java cmdline length: ' + $javaArgs.Length)
if ($DryRun) {
    Write-Log 'DRY RUN - command that would be executed:'
    Write-Host ''
    Write-Host ($javaExe + ' ' + $javaArgs)
    Write-Host ''
    Write-Log 'dry run complete'
    exit 0
}

# --------------------------------------------------------- existing game ----
$existingAll = @(Get-KnotClientProcesses)
$existing = @($existingAll | Where-Object { $_.Cmd -and ($_.Cmd -match [regex]::Escape($VersionDir)) })
$others   = @($existingAll | Where-Object { -not ($_.Cmd -and ($_.Cmd -match [regex]::Escape($VersionDir))) })
if ($others.Count -gt 0) {
    Write-Log ('other Minecraft instance(s) with a different gameDir are running (left untouched): ' + (($others | ForEach-Object { $_.Pid }) -join ', ')) 'WARN'
}
$existingClosed = $false
if ($existing.Count -gt 0) {
    Write-Log ('found already running Minecraft instance(s) for this version dir: ' + (($existing | ForEach-Object { $_.Pid }) -join ', ')) 'WARN'
    foreach ($e in $existing) { Write-Log ('  pid ' + $e.Pid + ' title=' + $e.Title) 'WARN' }
    if (-not $CloseExisting) {
        throw 'another Minecraft instance is running; re-run with -CloseExisting to let the test close it gracefully'
    }
    foreach ($e in $existing) {
        $h = $e.Handle
        if ($h -eq [IntPtr]::Zero) { $h = Get-McWindow -ProcessId $e.Pid -TimeoutSeconds 5 }
        $res = Stop-OwnGame -ProcessId $e.Pid -Handle $h -TimeoutSeconds 120
        Write-Log ('existing instance pid ' + $e.Pid + ' closed: ' + $res)
        $existingClosed = $true
    }
    Start-Sleep -Seconds 2
}

# ------------------------------------------------------------ backups -------
function New-Backup {
    param([string]$Path, [string]$Tag)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $dst = Join-Path $backupDir ('{0}.{1}.bak' -f $Tag, $stamp)
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    return $dst
}
$irisBackup    = New-Backup -Path $irisCfg    -Tag 'iris.properties'
$optionsBackup = New-Backup -Path $optionsTxt -Tag 'options.txt'
Write-Log ('backups: iris=' + $irisBackup + ' options=' + $optionsBackup)

function Set-IrisShaderPack {
    param([string]$Path, [string]$Pack)
    $content = ''
    if (Test-Path -LiteralPath $Path) { $content = Get-Content -LiteralPath $Path -Raw }
    if ($content) { $lines = $content -split "`r?`n" } else { $lines = @() }
    $found = $false
    $out = @()
    foreach ($l in $lines) {
        if ($l -match '^\s*shaderPack\s*=') { $found = $true; $out += ('shaderPack=' + $Pack) }
        elseif ($l -match '^\s*enableShaders\s*=') { $out += 'enableShaders=true' }
        else { $out += $l }
    }
    if (-not $found) { $out += ('shaderPack=' + $Pack) }
    if (-not (($out -join "`n") -match 'enableShaders\s*=\s*true')) { $out += 'enableShaders=true' }
    Write-Utf8File -Path $Path -Text ($out -join "`n")
}

$proc = $null
$hwnd = [IntPtr]::Zero
$phase = 'preflight'
$result = New-Object PSObject -Property @{
    stamp = $stamp; status = 'FAIL'; phase = 'preflight'
    shaderPack = $ShaderPack; world = $World; width = $Width; height = $Height
    versionDir = $VersionDir; commands = $Commands
    startedAt = $script:StartedAt.ToString('o'); finishedAt = ''
    existingClosed = $existingClosed; launchPid = 0; windowHandle = 0; windowTitle = ''
    shaderpackSeen = $false; pipelineSeen = $false; joined = $false; compileFailed = $true
    screenshots = @(); commandAcks = @()
    timings = @{}; notes = @(); error = ''
}

try {
    # ------------------------------------------------ configure iris -------
    $phase = 'configure'
    Set-IrisShaderPack -Path $irisCfg -Pack $ShaderPack
    Write-Log ('iris.properties set: shaderPack=' + $ShaderPack + ', enableShaders=true')
    Write-Log ('iris.properties now: ' + ((Get-Content -LiteralPath $irisCfg) -join ' | '))

    # ------------------------------------------------------- launch --------
    $phase = 'launch'
    foreach ($f in @($consoleLog, $consoleErr)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
    $preLogMarker = Get-LogSessionMarker -Path $latestLog
    $result.notes += ('pre-launch latest.log first line: ' + $preLogMarker)
    Write-Log 'launching Minecraft...'
    $launchTime = Get-Date
    $spArgs = @{
        FilePath = $javaExe
        ArgumentList = $javaArgs
        WorkingDirectory = $VersionDir
        PassThru = $true
        RedirectStandardOutput = $consoleLog
        RedirectStandardError = $consoleErr
        WindowStyle = 'Hidden'
    }
    $proc = Start-Process @spArgs
    $result.launchPid = $proc.Id
    Write-Log ('launched java pid=' + $proc.Id)

    $phase = 'window'
    $hwnd = Get-McWindow -ProcessId $proc.Id -TimeoutSeconds $StartupTimeoutSeconds
    if ($hwnd -eq [IntPtr]::Zero) { throw ("game window did not appear within " + $StartupTimeoutSeconds + " s") }
    $result.windowHandle = $hwnd.ToInt64()
    $result.timings['windowSeconds'] = [math]::Round(((Get-Date) - $launchTime).TotalSeconds, 1)
    $result.windowTitle = [MCWin]::Title($hwnd)
    Write-Log ('game window hwnd=' + $hwnd + ' title=' + $result.windowTitle + ' after ' + $result.timings['windowSeconds'] + ' s')

    # ------------------------------------------------- wait world load -----
    $phase = 'world-load'
    $joinDeadline = $launchTime.AddSeconds($StartupTimeoutSeconds + $JoinTimeoutSeconds)
    $done = $false
    $lastProgressPrint = Get-Date
    $shaderpackAt = $null; $pipelineAt = $null; $joinAt = $null
    while ((Get-Date) -lt $joinDeadline) {
        $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if (-not $proc) {
            $tail = Get-LogText -Path $latestLog
            $hints = @($tail -split "`r?`n" | Where-Object { $_ -match 'crash|Exception|Failed to start|ERROR' } | Select-Object -Last 6)
            throw ('game process exited during ' + $phase + '. last log hints: ' + ($hints -join ' || '))
        }
        $log = Get-LogText -Path $latestLog
        $newSession = Test-NewLogSession -Path $latestLog -OldMarker $preLogMarker
        if (-not $newSession) {
            if (((Get-Date) - $lastProgressPrint).TotalSeconds -ge 15) {
                $lastProgressPrint = Get-Date
                Write-Log 'waiting for a fresh latest.log session (old log not rotated yet)'
            }
            Start-Sleep -Milliseconds 1500
            continue
        }
        if ($log -and (-not $script:NewSessionLogged)) {
            $script:NewSessionLogged = $true
            Write-Log 'fresh latest.log session detected'
        }
        if ($log) {
            if (-not $shaderpackAt -and ($log -match ('Using shaderpack:\s*' + [regex]::Escape($ShaderPack)))) {
                $shaderpackAt = Get-Date
                Write-Log ('shaderpack loaded: Using shaderpack: ' + $ShaderPack)
            }
            if (-not $pipelineAt -and ($log -match 'Creating pipeline for dimension')) {
                $pipelineAt = Get-Date
                Write-Log 'Iris pipeline creation started'
            }
            if (-not $joinAt -and ($log -match 'joined the game|加入了游戏|Preparing start region for dimension')) {
                $joinAt = Get-Date
                Write-Log 'world loading started (integrated server)'
            }
            if ($log -match 'Failed to create shader rendering pipeline|ShaderCompileException|Shader compilation log for|Unable to load shaderpack') {
                Write-Log 'IRIS COMPILE/LOAD FAILURE detected in latest.log' 'ERROR'
                $done = $true
                break
            }
            if ($pipelineAt -and (((Get-Date) - $pipelineAt).TotalSeconds -ge $SettleSeconds)) { $done = $true; break }
            if ($joinAt -and (((Get-Date) - $joinAt).TotalSeconds -ge ($SettleSeconds + 8))) { $done = $true; break }
        }
        if (((Get-Date) - $lastProgressPrint).TotalSeconds -ge 15) {
            $lastProgressPrint = Get-Date
            $snippet = ''
            if ($log) { $snippet = (($log -split "`r?`n") | Where-Object { $_ -match 'Preparing|Loading|Loaded|joined|加入了|Creating pipeline|Reloading|Starting' } | Select-Object -Last 1) }
            Write-Log ('still waiting for world... ' + $snippet)
        }
        Start-Sleep -Milliseconds 2500
    }
    if (-not ($shaderpackAt -or $pipelineAt -or $joinAt)) { throw 'timed out waiting for world load (no shaderpack/pipeline/join lines in latest.log)' }

    $result.shaderpackSeen = [bool]$shaderpackAt
    $result.pipelineSeen   = [bool]$pipelineAt
    $result.joined         = [bool]$joinAt
    if ($shaderpackAt) { $result.timings['shaderpackSeconds'] = [math]::Round(($shaderpackAt - $launchTime).TotalSeconds, 1) }
    if ($pipelineAt)   { $result.timings['pipelineSeconds']   = [math]::Round(($pipelineAt - $launchTime).TotalSeconds, 1) }
    if ($joinAt)       { $result.timings['joinSeconds']       = [math]::Round(($joinAt - $launchTime).TotalSeconds, 1) }

    $hwnd = Get-McWindow -ProcessId $proc.Id -TimeoutSeconds 10
    if ($hwnd -ne [IntPtr]::Zero) {
        $result.windowHandle = $hwnd.ToInt64()
        $result.windowTitle = [MCWin]::Title($hwnd)
        Write-Log ('window title now: ' + $result.windowTitle)
    }

    Start-Sleep -Seconds 3

    # ------------------------------------------------------- commands ------
    $phase = 'commands'
    if ((-not $SkipCommands) -and ($Commands.Count -gt 0) -and ($hwnd -ne [IntPtr]::Zero)) {
        $focused = Focus-McWindow -Handle $hwnd
        Write-Log ('game window focused: ' + $focused)
        if (-not $focused) { $result.notes += 'could not confirm foreground focus; keystrokes may be dropped' }
        foreach ($cmd in $Commands) {
            Write-Log ('sending chat command: ' + $cmd)
            Send-ChatCommand -Handle $hwnd -Text $cmd
            Start-Sleep -Milliseconds 700
        }
        Start-Sleep -Seconds 2
        $log = Get-LogText -Path $latestLog
        $retry = @()
        foreach ($cmd in $Commands) {
            $acked = ($log -match [regex]::Escape('issued server command: ' + $cmd))
            if (-not $acked) { $retry += $cmd }
            $result.commandAcks += New-Object PSObject -Property @{ command = $cmd; acked = [bool]$acked }
            Write-Log ('command acked in log: ' + $acked + '  <- ' + $cmd)
        }
        if ($retry.Count -gt 0) {
            Write-Log ('retrying ' + $retry.Count + ' command(s) with clipboard paste')
            foreach ($cmd in $retry) {
                Send-ChatCommand -Handle $hwnd -Text $cmd -UseClipboard
                Start-Sleep -Milliseconds 800
            }
            Start-Sleep -Seconds 2
            $log = Get-LogText -Path $latestLog
            $finalAcks = @()
            foreach ($a in $result.commandAcks) {
                $acked = ($log -match [regex]::Escape('issued server command: ' + $a.command))
                $finalAcks += New-Object PSObject -Property @{ command = $a.command; acked = [bool]$acked }
                if ($acked -and -not $a.acked) { Write-Log ('command retry succeeded: ' + $a.command) }
            }
            $result.commandAcks = $finalAcks
        }
        $notAcked = @($result.commandAcks | Where-Object { -not $_.acked })
        if ($notAcked.Count -gt 0) { $result.notes += ('chat commands not confirmed in latest.log: ' + (($notAcked | ForEach-Object { $_.command }) -join ', ')) }
    } else {
        Write-Log 'chat commands skipped'
    }

    # ------------------------------------------------------ screenshots ----
    $phase = 'screenshot'
    [void](Focus-McWindow -Handle $hwnd)
    Start-Sleep -Milliseconds 600
    $worldTag = ($World -replace '[^\w\-\.]', '_')
    for ($i = 1; $i -le $ShotCount; $i++) {
        $shotStart = Get-Date
        Write-Log ('pressing F2 (screenshot ' + $i + '/' + $ShotCount + ')')
        [MCWin]::KeyPress(0x71, 40)   # F2
        $newShot = $null
        $deadline = (Get-Date).AddSeconds(25)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 700
            $newShot = Get-NewestScreenshot -After $shotStart -Dir $screenshotsDir
            if ($newShot) { break }
        }
        if ($newShot) {
            $dest = Join-Path $shotsDir ('{0}-{1}-{2}-shot{3}.png' -f $stamp, $ShaderPack, $worldTag, $i)
            Copy-Item -LiteralPath $newShot.FullName -Destination $dest -Force
            $result.screenshots += $dest
            Write-Log ('screenshot saved: ' + $dest + '  (game file: ' + $newShot.Name + ')')
        } else {
            Write-Log 'no new screenshot file appeared after F2' 'WARN'
            $fb = Join-Path $shotsDir ('{0}-{1}-{2}-window-fallback{3}.png' -f $stamp, $ShaderPack, $worldTag, $i)
            if (Save-WindowShot -Handle $hwnd -OutPath $fb) { $result.screenshots += $fb; Write-Log ('window fallback saved: ' + $fb) }
            $result.notes += 'F2 produced no file; used window capture fallback'
            break
        }
        if ($i -lt $ShotCount) { Start-Sleep -Seconds $ShotIntervalSeconds }
    }
    $deskShot = Join-Path $runDir 'desktop.png'
    if (Save-DesktopShot -OutPath $deskShot) { Write-Log ('desktop diagnostic capture: ' + $deskShot) }

    # ------------------------------------------------------------- quit ----
    $phase = 'quit'
    if ($KeepGame) {
        Write-Log 'KeepGame set - leaving the game running' 'WARN'
        $result.notes += 'game left running (-KeepGame)'
    } else {
        $quitSent = Get-Date
        $how = Stop-OwnGame -ProcessId $proc.Id -Handle $hwnd -TimeoutSeconds $QuitTimeoutSeconds
        $result.timings['quitSeconds'] = [math]::Round(((Get-Date) - $quitSent).TotalSeconds, 1)
        Write-Log ('game quit result: ' + $how)
        $result.notes += ('game quit: ' + $how)
    }
} catch {
    $result.error = $_.Exception.Message
    Write-Log ('ERROR during phase [' + $phase + ']: ' + $_.Exception.Message) 'ERROR'
} finally {
    $result.phase = $phase
    if ($proc -and (-not $KeepGame)) {
        $alive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if ($alive) {
            $h = $hwnd
            if ($h -eq [IntPtr]::Zero) { $h = Get-McWindow -ProcessId $proc.Id -TimeoutSeconds 3 }
            $how = Stop-OwnGame -ProcessId $proc.Id -Handle $h -TimeoutSeconds 60
            Write-Log ('cleanup quit: ' + $how)
        }
    }

    try {
        $evidence = $null
        if (Test-Path -LiteralPath $latestLog) { Copy-Item -LiteralPath $latestLog -Destination (Join-Path $runDir 'latest.log') -Force }
        foreach ($f in @($consoleLog, $consoleErr)) {
            if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $runDir (Split-Path -Leaf $f)) -Force -ErrorAction SilentlyContinue }
        }
        $logText = Get-LogText -Path $latestLog
        $evidence = Extract-IrisEvidence -LogText $logText -PackName $ShaderPack
        $irisErrPath = Join-Path $reportsDir 'iris-errors.txt'
        Write-IrisErrorsFile -Path $irisErrPath -Evidence $evidence -PackName $ShaderPack
        Copy-Item -LiteralPath $irisErrPath -Destination (Join-Path $runDir 'iris-errors.txt') -Force

        $result.shaderpackSeen = [bool]$evidence.PackSeen
        $result.pipelineSeen = ($evidence.PipelineLines.Count -gt 0)
        $result.compileFailed = [bool]$evidence.CompileFailed
        if (-not $result.joined) { $result.joined = ($evidence.JoinLines.Count -gt 0) }

        $ok = ($evidence.PackSeen -and ($evidence.PipelineLines.Count -gt 0) -and (-not $evidence.CompileFailed) -and ($result.screenshots.Count -gt 0))
        $result.status = if ($ok) { 'PASS' } else { 'FAIL' }
        if ($evidence.CompileFailed) { $result.notes += 'Iris shader compile/load failure found in latest.log' }
        if (-not $evidence.PackSeen) { $result.notes += 'expected shaderpack line not found in latest.log' }
        if ($result.screenshots.Count -eq 0) { $result.notes += 'no screenshot captured' }

        if (-not $NoRestore) {
            if ($RestoreIris) {
                if ($irisBackup -and (Test-Path -LiteralPath $irisBackup)) {
                    Copy-Item -LiteralPath $irisBackup -Destination $irisCfg -Force
                    Write-Log 'iris.properties restored from pre-run backup'
                }
            } else {
                Write-Log ('iris.properties left as shaderPack=' + $ShaderPack + ' (project convention: keep Zephyr active)')
            }
            if ($optionsBackup -and (Test-Path -LiteralPath $optionsBackup)) {
                Copy-Item -LiteralPath $optionsBackup -Destination $optionsTxt -Force
                Write-Log 'options.txt restored'
            }
        } else {
            Write-Log 'NoRestore set - options.txt left untouched (iris.properties is always left as-is)' 'WARN'
        }

        $result.timings['totalSeconds'] = [math]::Round(((Get-Date) - $script:StartedAt).TotalSeconds, 1)
        $result.finishedAt = (Get-Date).ToString('o')

        $metricsPath = Join-Path $reportsDir 'last-run.json'
        Write-Utf8File -Path $metricsPath -Text ($result | ConvertTo-Json -Depth 6)
        Copy-Item -LiteralPath $metricsPath -Destination (Join-Path $runDir 'last-run.json') -Force
        Write-LaunchReport -Path (Join-Path $reportsDir 'launch-report.md') -Result $result -Evidence $evidence
        Copy-Item -LiteralPath (Join-Path $reportsDir 'launch-report.md') -Destination (Join-Path $runDir 'launch-report.md') -Force
        $script:LogLines | Set-Content -LiteralPath $runLog -Encoding UTF8

        Write-Log ('RESULT: ' + $result.status)
        Write-Host ''
        Write-Host ($result | ConvertTo-Json -Depth 6)
    } catch {
        Write-Host ('post-run bookkeeping failed: ' + $_.Exception.Message) -ForegroundColor Red
        $result.status = 'FAIL'
        $result.notes += ('bookkeeping error: ' + $_.Exception.Message)
        try { $script:LogLines | Set-Content -LiteralPath $runLog -Encoding UTF8 } catch { }
    }
}

if ($result.status -ne 'PASS') { exit 2 }
exit 0
