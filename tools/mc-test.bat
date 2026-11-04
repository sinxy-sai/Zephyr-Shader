@echo off
rem One-command Minecraft real-machine validation for the Zephyr shader pack.
rem Usage: tools\mc-test.bat [-ShaderPack Zephyr] [-World "Weston City V0.3"] [-CloseExisting] [-DryRun]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mc-test.ps1" %*
exit /b %ERRORLEVEL%
