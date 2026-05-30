@echo off
title Claude WeChat Bridge
cd /d %USERPROFILE%
echo === Cleaning old processes ===
powershell -Command "Get-WmiObject Win32_Process -Filter 'Name=\"node.exe\"' | Where-Object { $_.CommandLine -match 'wechat-bridge|wechat-channel|cli\.mjs.*start' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host 'Killed PID' $_.ProcessId }"
echo === Starting WeChat Bridge (persistent session) ===
node .claude\wechat-bridge.mjs
echo Bridge stopped.
pause >nul
