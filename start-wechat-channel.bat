@echo off
title Claude WeChat Bridge
cd /d C:\Users\shish

:loop
echo === [%date% %time%] Cleaning old processes ===
powershell -Command "Get-WmiObject Win32_Process -Filter 'Name=\"node.exe\"' | Where-Object { $_.CommandLine -match 'wechat-bridge|wechat-channel|cli\.mjs.*start' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host 'Killed PID' $_.ProcessId }"
timeout /t 2 >nul
echo === [%date% %time%] Starting WeChat Bridge ===
node .claude\wechat-bridge.mjs
echo === [%date% %time%] Bridge stopped, restarting in 5s... ===
timeout /t 5 >nul
goto loop
