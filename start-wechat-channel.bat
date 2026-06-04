@echo off
chcp 65001 >nul 2>&1
title Claude 微信桥接
cd /d C:\Users\shish

:loop
echo === [%date% %time%] 清理旧进程 ===
powershell -Command "Get-WmiObject Win32_Process -Filter 'Name=\"node.exe\"' | Where-Object { $_.CommandLine -match 'wechat-bridge|wechat-channel|cli\.mjs.*start' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host '已终止 PID' $_.ProcessId }"
timeout /t 2 >nul
echo === [%date% %time%] 启动微信桥接 ===
echo     桥接运行中，请勿关闭此窗口...
echo.
node .claude\wechat-bridge.mjs
echo === [%date% %time%] 桥接已停止，5秒后自动重启... ===
timeout /t 5 >nul
goto loop
