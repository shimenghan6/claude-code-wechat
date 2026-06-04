@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code 微信桥接 — 一键安装

echo.
echo   =============================================
echo    Claude Code 微信桥接 — 一键安装
echo   =============================================
echo.

:: ================================================
:: 环境检测
:: ================================================
echo [检测] Node.js...
where node >nul 2>&1
if !errorlevel! neq 0 (
    echo   [错误] 未找到 Node.js，请从 https://nodejs.org 安装
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('node -v') do echo   [完成] Node.js %%i

echo [检测] Python...
where python >nul 2>&1
if !errorlevel! neq 0 (
    echo   [错误] 未找到 Python，请从 https://python.org 安装
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('python --version 2^>^&1') do echo   [完成] Python %%i

:: ================================================
:: 基础安装
:: ================================================
echo.
echo [1/4] 安装 Node.js 依赖...
call npm install -g claude-code-wechat-channel @weixin-claw/core
if !errorlevel! neq 0 (
    echo   [警告] npm 安装失败，继续...
)

echo.
echo [2/4] 安装 Python 依赖...
call pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python
if !errorlevel! neq 0 (
    echo   [警告] pip 安装失败，继续...
)

echo.
echo [3/4] 检测 FFmpeg...
where ffmpeg >nul 2>&1
if !errorlevel! neq 0 (
    echo   未找到 FFmpeg，正在自动安装...
    call winget install ffmpeg
    if !errorlevel! neq 0 (
        echo   [警告] FFmpeg 自动安装失败，请手动安装：https://ffmpeg.org
    ) else (
        echo   [完成] FFmpeg 已安装
    )
) else (
    echo   [完成] FFmpeg 已安装
)

:: ================================================
:: 可选功能
:: ================================================
set "ENABLE_SLEEP=0"
set "ENABLE_VOLUME=0"

echo.
echo   -----------------------------------------------
echo    可选功能
echo   -----------------------------------------------
echo.
echo   [1] 远程睡眠 — 微信发"让电脑睡眠"即可
echo        ^(需要在 settings.json 中配置权限^)
echo.
echo   [2] 音量控制 — 微信发"音量调到50"即可
echo        ^(需要：pip install pycaw^)
echo.
set /p CHOICE="  启用哪些功能？输入数字（如 12 全开，0 跳过）："

if "!CHOICE!"=="" set CHOICE=0

set "CHECK=!CHOICE!"
if not "!CHECK:1=!"=="!CHECK!" set ENABLE_SLEEP=1
if not "!CHECK:2=!"=="!CHECK!" set ENABLE_VOLUME=1

:: 安装可选依赖
if !ENABLE_VOLUME! equ 1 (
    echo.
    echo   [可选] 安装音量控制依赖 ^(pycaw^)...
    call pip install pycaw
    if !errorlevel! neq 0 (
        echo   [警告] pycaw 安装失败，音量控制不可用
        set ENABLE_VOLUME=0
    ) else (
        echo   [完成] pycaw 已安装
    )
)

:: ================================================
:: 复制文件
:: ================================================
echo.
echo [4/4] 复制文件...
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
copy /Y "%~dp0wechat-bridge.mjs" "%USERPROFILE%\.claude\wechat-bridge.mjs" >nul 2>&1
copy /Y "%~dp0media-processor.py" "%USERPROFILE%\.claude\media-processor.py" >nul 2>&1
copy /Y "%~dp0cloud_vision.py" "%USERPROFILE%\.claude\cloud_vision.py" >nul 2>&1
if exist "%~dp0cloud-vision.py" copy /Y "%~dp0cloud-vision.py" "%USERPROFILE%\.claude\cloud-vision.py" >nul 2>&1

:: 复制 start-wechat-channel.bat（含自动清理+崩溃重启+防重复）
copy /Y "%~dp0start-wechat-channel.bat" "%USERPROFILE%\.claude\start-wechat-channel.bat" >nul 2>&1
echo   [完成] start-wechat-channel.bat ^(含自动清理+崩溃重启+防重复^)

:: 复制 SKILL.md 到 skills 目录
if exist "%~dp0SKILL.md" (
    if not exist "%USERPROFILE%\.claude\skills\claude-code-wechat" mkdir "%USERPROFILE%\.claude\skills\claude-code-wechat" 2>nul
    copy /Y "%~dp0SKILL.md" "%USERPROFILE%\.claude\skills\claude-code-wechat\SKILL.md" >nul 2>&1
    echo   [完成] SKILL.md 已安装
)

if !ENABLE_VOLUME! equ 1 (
    if exist "%~dp0tools\volume.py" (
        if not exist "%USERPROFILE%\.claude\tools" mkdir "%USERPROFILE%\.claude\tools" 2>nul
        copy /Y "%~dp0tools\volume.py" "%USERPROFILE%\.claude\tools\volume.py" >nul 2>&1
        echo   [完成] volume.py 已安装
    )
)

echo   [完成] 核心文件已复制到 %USERPROFILE%\.claude\

:: ================================================
:: 开机自启
:: ================================================
echo.
echo   配置开机自启...
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "!STARTUP_DIR!" (
    echo CreateObject^("Wscript.Shell"^).Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False > "!STARTUP_DIR!\claude-wechat.vbs"
    echo   [完成] 开机自启已配置 ^(关机重启自动恢复^)
) else (
    echo   [警告] 未找到启动文件夹，跳过开机自启
)

:: ================================================
:: 远程睡眠权限提示
:: ================================================
if !ENABLE_SLEEP! equ 1 (
    echo.
    echo   --- 远程睡眠权限 ---
    echo   在 %USERPROFILE%\.claude\settings.json 中
    echo   "permissions" -^> "allow" 下添加：
    echo     "Bash^(rundll32.exe powrprof.dll,SetSuspendState *^)"
)

:: ================================================
:: 音量控制提示
:: ================================================
if !ENABLE_VOLUME! equ 1 (
    echo.
    echo   --- 音量控制权限 ---
    echo   在 settings.json 的 "permissions" -^> "allow" 下添加：
    echo     "Bash^(python *volume.py*^)"
    echo.
    echo   命令示例：
    echo     python %USERPROFILE%\.claude\tools\volume.py mute
    echo     python %USERPROFILE%\.claude\tools\volume.py 50
)

:: ================================================
:: 微信内置命令
:: ================================================
echo.
echo   --- 微信内置命令 ---
echo   从微信发送以下指令：
echo     "重新打开会话" — 刷新会话（保留历史^)
echo     "让电脑睡眠"   — 远程睡眠（需先启用^)
echo     "音量调到50"    — 音量控制（需先启用^)

:: ================================================
:: 完成
:: ================================================
echo.
echo   =============================================
echo    安装完成！
echo.
echo    下一步：
echo    1. 扫码绑定：
echo       curl -s https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3
echo    2. 保存凭证到 %USERPROFILE%\.claude\channels\wechat\account.json
echo    3. 启动桥接：
echo       双击 start-wechat-channel.bat
echo       或：node %USERPROFILE%\.claude\wechat-bridge.mjs
echo.
echo    图片识别功能（腾讯云）：
echo    4. 注册 https://cloud.tencent.com 获取 API Key
echo       详见 README.md
echo   =============================================
echo.

endlocal
pause
