param(
    [string]$World = "Weston City V0.3",
    [int]$Width = 1920,
    [int]$Height = 1080
)
$ErrorActionPreference = "Stop"
$bat = "C:\Users\liubingliang\Downloads\PCL-2.12.2\PCL\LatestLaunch.bat"
$cmdLine = (Get-Content $bat) | Where-Object { $_ -match "KnotClient" } | Select-Object -First 1
if (-not $cmdLine) { throw "java command not found in LatestLaunch.bat" }
$cmdLine = $cmdLine -replace '\$\{clientid\}', '0' -replace '\$\{auth_xuid\}', '0'
if ($cmdLine -match '--width \d+ --height \d+') {
    $cmdLine = $cmdLine -replace '--width \d+ --height \d+', "--width $Width --height $Height"
} else {
    $cmdLine += " --width $Width --height $Height"
}
if ($World) { $cmdLine += ' --quickPlaySingleplayer "' + $World + '"' }
$gameDir = "C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4"
$tmp = Join-Path $env:TEMP "zephyr-launch.bat"
$content = "@echo off`r`ncd /D `"$gameDir`"`r`n" + $cmdLine + "`r`n"
[System.IO.File]::WriteAllText($tmp, $content, [System.Text.Encoding]::Default)
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$tmp`"" -WindowStyle Hidden -PassThru
Write-Output ("LAUNCHED cmd_pid=" + $proc.Id)
Write-Output ("WORLD=" + $World + " SIZE=" + $Width + "x" + $Height)
