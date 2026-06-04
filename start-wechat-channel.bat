@echo off
chcp 65001 >nul 2>&1
title Claude 微信桥接
cd /d C:\Users\shish

echo === [%date% %time%] 启动看门狗 ===
echo     看门狗会自动清理旧进程 + 崩溃重启
echo     请勿关闭此窗口...
echo.
python .claude\watchdog.py
echo === [%date% %time%] 看门狗停止 ===
pause >nul
