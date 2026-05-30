@echo off
setlocal enabledelayedexpansion
echo =============================================
echo  Claude Code WeChat Bridge - One-Click Install
echo =============================================
echo.

:: Check Node.js
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js not found. Install from https://nodejs.org
    pause
    exit /b 1
)
echo [OK] Node.js found

:: Check Python
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found. Install from https://python.org
    pause
    exit /b 1
)
echo [OK] Python found

:: ================================================
::  BASIC INSTALL (always runs)
:: ================================================

echo.
echo [1/4] Installing Node.js packages...
call npm install -g claude-code-wechat-channel @weixin-claw/core
if %errorlevel% neq 0 (
    echo [WARN] npm install failed, continuing...
)

echo.
echo [2/4] Installing core Python packages...
call pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python
if %errorlevel% neq 0 (
    echo [WARN] pip install failed, continuing...
)

echo.
echo [3/4] Checking FFmpeg...
where ffmpeg >nul 2>&1
if %errorlevel% neq 0 (
    echo FFmpeg not found. Attempting auto-install...
    winget install ffmpeg
    if %errorlevel% neq 0 (
        echo [WARN] FFmpeg auto-install failed. Install manually: https://ffmpeg.org
    ) else (
        echo [OK] FFmpeg installed
    )
) else (
    echo [OK] FFmpeg already installed
)

:: ================================================
::  OPTIONAL FEATURES
:: ================================================

set "ENABLE_SLEEP=0"
set "ENABLE_VOLUME=0"

echo.
echo -----------------------------------------------
echo  OPTIONAL FEATURES
echo -----------------------------------------------
echo.
echo  [1] Remote Sleep - send "sleep" from WeChat to put PC to sleep
echo      (needs permission in settings.json)
echo.
echo  [2] Volume Control - mute/unmute/set volume %% from WeChat
echo      (needs: pip install pycaw)
echo.
set /p CHOICE="Enable features? Enter numbers (e.g. 12 for both, 0 to skip): "

if "%CHOICE%"=="" set CHOICE=0

echo %CHOICE% | find "1" >nul
if %errorlevel% equ 0 set ENABLE_SLEEP=1

echo %CHOICE% | find "2" >nul
if %errorlevel% equ 0 set ENABLE_VOLUME=1

:: Install optional dependencies
if %ENABLE_VOLUME% equ 1 (
    echo.
    echo [OPT] Installing volume control dependency (pycaw)...
    call pip install pycaw
    if %errorlevel% neq 0 (
        echo [WARN] pycaw install failed, volume control disabled
        set ENABLE_VOLUME=0
    ) else (
        echo [OK] pycaw installed
    )
)

:: ================================================
::  COPY FILES
:: ================================================

echo.
echo [4/4] Copying files...
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
copy /Y "wechat-bridge.mjs" "%USERPROFILE%\.claude\wechat-bridge.mjs" >nul
copy /Y "media-processor.py" "%USERPROFILE%\.claude\media-processor.py" >nul
copy /Y "cloud_vision.py" "%USERPROFILE%\.claude\cloud_vision.py" >nul
copy /Y "cloud-vision.py" "%USERPROFILE%\.claude\cloud-vision.py" >nul

:: Copy volume tool if enabled
if %ENABLE_VOLUME% equ 1 (
    if not exist "%USERPROFILE%\.claude\tools" mkdir "%USERPROFILE%\.claude\tools"
    copy /Y "tools\volume.py" "%USERPROFILE%\.claude\tools\volume.py" >nul
    echo [OK] volume.py copied to tools\
)

echo [OK] Core files copied to %USERPROFILE%\.claude\

:: ================================================
::  CREATE STARTUP SCRIPT (with pre-cleanup)
:: ================================================

echo.
echo Creating startup scripts...

(
echo @echo off
echo title Claude WeChat Bridge
echo cd /d "%USERPROFILE%"
echo echo Cleaning old processes...
echo powershell -Command "Get-WmiObject Win32_Process -Filter 'Name=\"node.exe\"' ^| Where-Object { $_.CommandLine -match 'wechat-bridge^|wechat-channel^|cli\\.mjs.*start' } ^| ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" ^>nul 2^>^&1
echo echo Starting WeChat Bridge...
echo node .claude\wechat-bridge.mjs
echo echo Bridge stopped.
echo pause ^>nul
) > "%USERPROFILE%\.claude\start-wechat-channel.bat"
echo [OK] Created start-wechat-channel.bat (with auto-cleanup)

:: VBS auto-start
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "%STARTUP_DIR%" (
    echo CreateObject^("Wscript.Shell"^).Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False > "%STARTUP_DIR%\claude-wechat.vbs"
    echo [OK] Created auto-start VBS (runs on boot)
) else (
    echo [WARN] Startup folder not found, skipped auto-start
)

:: ================================================
::  POST-INSTALL SLEEP PERMISSION
:: ================================================

if %ENABLE_SLEEP% equ 1 (
    echo.
    echo -----------------------------------------------
    echo  Remote Sleep Setup
    echo -----------------------------------------------
    echo To enable remote sleep without approval prompts,
    echo add this line to %USERPROFILE%\.claude\settings.json
    echo under "permissions" -^> "allow":
    echo.
    echo   "Bash(rundll32.exe powrprof.dll,SetSuspendState *)"
    echo.
    echo Then send "sleep" from WeChat to put PC to sleep.
    echo See README for details.
)

:: ================================================
::  VOLUME COMMANDS CHEAT SHEET
:: ================================================

if %ENABLE_VOLUME% equ 1 (
    echo.
    echo -----------------------------------------------
    echo  Volume Control Commands
    echo -----------------------------------------------
    echo   python %USERPROFILE%\.claude\tools\volume.py mute
    echo   python %USERPROFILE%\.claude\tools\volume.py unmute
    echo   python %USERPROFILE%\.claude\tools\volume.py 50
    echo   python %USERPROFILE%\.claude\tools\volume.py
    echo.
    echo Add these to settings.json allow list to skip approval.
)

:: ================================================
::  DONE
:: ================================================

echo.
echo =============================================
echo  Installation Complete!
echo.
echo  Next steps:
echo   1. Scan QR code:
echo      curl -s https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3
echo   2. Save credentials to %USERPROFILE%\.claude\channels\wechat\account.json
echo   3. Start bridge:
echo      node %USERPROFILE%\.claude\wechat-bridge.mjs
echo      OR double-click start-wechat-channel.bat
echo.
echo  For image description (Tencent Cloud):
echo   4. Register at https://cloud.tencent.com and save API keys
echo   5. See README.md for details
echo =============================================
pause
