@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code 微信桥接 — 一键安装

echo.
echo   =============================================
echo    Claude Code 微信桥接 — 一键安装
echo   =============================================
echo.
echo   全自动安装，无需手动操作，请耐心等待...
echo.

:: ================================================
:: 环境检测（缺环境自动 winget 安装，不中断）
:: ================================================
set OK_NODE=1
set OK_PYTHON=1
set OK_FFMPEG=1

echo [1/5] 环境检测...
echo.

echo   [检测] Node.js...
where node >nul 2>&1
if !errorlevel! neq 0 (
    echo   [警告] 未找到 Node.js，尝试 winget 安装...
    call winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
    where node >nul 2>&1
    if !errorlevel! neq 0 (
        echo   [警告] Node.js 安装失败，npm 依赖将跳过
        set OK_NODE=0
    ) else (
        echo   [完成] Node.js 已安装
    )
) else (
    for /f "tokens=*" %%i in ('node -v') do echo   [完成] Node.js %%i
)

echo   [检测] Python...
where python >nul 2>&1
if !errorlevel! neq 0 (
    echo   [警告] 未找到 Python，尝试 winget 安装...
    call winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements
    where python >nul 2>&1
    if !errorlevel! neq 0 (
        echo   [警告] Python 安装失败，pip 依赖将跳过
        set OK_PYTHON=0
    ) else (
        echo   [完成] Python 已安装
    )
) else (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do echo   [完成] Python %%i
)

echo   [检测] FFmpeg...
where ffmpeg >nul 2>&1
if !errorlevel! neq 0 (
    echo   [警告] 未找到 FFmpeg，尝试 winget 安装...
    call winget install Gyan.FFmpeg --accept-package-agreements --accept-source-agreements
    where ffmpeg >nul 2>&1
    if !errorlevel! neq 0 (
        echo   [警告] FFmpeg 安装失败，语音/视频功能不可用
        set OK_FFMPEG=0
    ) else (
        echo   [完成] FFmpeg 已安装
    )
) else (
    echo   [完成] FFmpeg 已安装
)

:: ================================================
:: 依赖安装（失败仅警告，继续后续步骤）
:: ================================================
echo.
echo [2/5] 安装依赖...

if !OK_NODE! equ 1 (
    echo   [npm] 安装 claude-code-wechat-channel @weixin-claw/core...
    call npm install -g claude-code-wechat-channel @weixin-claw/core
    if !errorlevel! neq 0 (
        echo   [警告] npm 安装失败，桥接可能无法启动
    ) else (
        echo   [完成] npm 依赖已安装
    )
)

if !OK_PYTHON! equ 1 (
    echo   [pip] 安装 paddleocr paddlepaddle openai-whisper tencentcloud-sdk-python...
    call pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python -q
    if !errorlevel! neq 0 (
        echo   [警告] pip 安装失败，图片/语音识别不可用
    ) else (
        echo   [完成] pip 依赖已安装
    )
)

:: ================================================
:: 复制文件
:: ================================================
echo.
echo [3/5] 复制文件...
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
if not exist "%USERPROFILE%\.claude\channels\wechat" mkdir "%USERPROFILE%\.claude\channels\wechat"

copy /Y "%~dp0wechat-bridge.mjs" "%USERPROFILE%\.claude\wechat-bridge.mjs" >nul 2>&1
echo   [完成] wechat-bridge.mjs

copy /Y "%~dp0media-processor.py" "%USERPROFILE%\.claude\media-processor.py" >nul 2>&1
echo   [完成] media-processor.py

copy /Y "%~dp0cloud_vision.py" "%USERPROFILE%\.claude\cloud_vision.py" >nul 2>&1
echo   [完成] cloud_vision.py

if exist "%~dp0cloud-vision.py" (
    copy /Y "%~dp0cloud-vision.py" "%USERPROFILE%\.claude\cloud-vision.py" >nul 2>&1
    echo   [完成] cloud-vision.py
)

copy /Y "%~dp0start-wechat-channel.bat" "%USERPROFILE%\.claude\start-wechat-channel.bat" >nul 2>&1
echo   [完成] start-wechat-channel.bat ^(自动重启+防重复^)

if exist "%~dp0SKILL.md" (
    if not exist "%USERPROFILE%\.claude\skills\claude-code-wechat" mkdir "%USERPROFILE%\.claude\skills\claude-code-wechat" 2>nul
    copy /Y "%~dp0SKILL.md" "%USERPROFILE%\.claude\skills\claude-code-wechat\SKILL.md" >nul 2>&1
    echo   [完成] SKILL.md
)

:: ================================================
:: 开机自启
:: ================================================
echo.
echo [4/5] 配置开机自启...
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "!STARTUP_DIR!" (
    echo CreateObject^("Wscript.Shell"^).Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False > "!STARTUP_DIR!\claude-wechat.vbs"
    echo   [完成] 开机自启已配置 ^(关机重启自动恢复^)
) else (
    echo   [警告] 未找到启动文件夹，跳过开机自启
)

:: ================================================
:: 启动桥接
:: ================================================
echo.
echo [5/5] 启动微信桥接...
echo   [提示] 如果尚未绑定微信，请先运行以下命令获取扫码链接：
echo   curl -s https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3
echo.
echo   正在启动桥接...
start "Claude 微信桥接" cmd /k "%USERPROFILE%\.claude\start-wechat-channel.bat"
echo   [完成] 桥接已启动 ^(崩溃自动重启^)

:: ================================================
:: 完成（窗口不自动关闭，用户可查看结果）
:: ================================================
echo.
echo   =============================================
echo    安装完成！
echo   =============================================
echo.
echo    已安装：
echo    - 微信桥接 ^(wechat-bridge^)     [已启动]
echo    - 开机自启               [已配置]
echo    - 崩溃自动重启            [已启用]
echo    - 图片识别 ^(PaddleOCR^)    [!OK_PYTHON! equ 1 && echo OK || echo 跳过]
echo    - 语音识别 ^(Whisper^)      [!OK_PYTHON! equ 1 && echo OK || echo 跳过]
echo    - 图片识景 ^(腾讯云^)      [需手动配置 API Key]
echo    - 视频分析 ^(FFmpeg^)       [!OK_FFMPEG! equ 1 && echo OK || echo 跳过]
echo.
echo    首次使用需绑定微信：
echo    运行: node %USERPROFILE%\.claude\wechat-bridge.mjs
echo.
echo    微信内置命令：
echo    "重新打开会话" - 刷新会话
echo    "让电脑睡眠"   - 远程睡眠
echo.
echo   =============================================
echo    [提示] 安装完成，请查看上方结果。按任意键关闭。
echo   =============================================
pause >nul

endlocal
