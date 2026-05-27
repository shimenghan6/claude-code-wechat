@echo off
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

:: Install Node.js dependencies
echo.
echo [1/3] Installing Node.js packages...
call npm install -g claude-code-wechat-channel @weixin-claw/core
if %errorlevel% neq 0 (
    echo [WARN] npm install failed, continuing...
)

:: Install Python dependencies
echo.
echo [2/3] Installing Python packages...
call pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python
if %errorlevel% neq 0 (
    echo [WARN] pip install failed, continuing...
)

:: Install FFmpeg (optional)
echo.
echo [3/3] Installing FFmpeg...
where ffmpeg >nul 2>&1
if %errorlevel% neq 0 (
    echo FFmpeg not found. Attempting auto-install...
    winget install ffmpeg
    if %errorlevel% neq 0 (
        echo [WARN] FFmpeg auto-install failed.
        echo Please install manually: https://ffmpeg.org/download.html
        echo Then add ffmpeg to your system PATH.
    ) else (
        echo [OK] FFmpeg installed
    )
) else (
    echo [OK] FFmpeg already installed
)

:: Copy files
echo.
echo Copying files...
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
copy /Y "wechat-bridge.mjs" "%USERPROFILE%\.claude\wechat-bridge.mjs" >nul
copy /Y "media-processor.py" "%USERPROFILE%\.claude\media-processor.py" >nul
copy /Y "cloud_vision.py" "%USERPROFILE%\.claude\cloud_vision.py" >nul
copy /Y "cloud-vision.py" "%USERPROFILE%\.claude\cloud-vision.py" >nul
echo [OK] Files copied to %USERPROFILE%\.claude\

:: Create startup scripts
echo.
echo Creating startup scripts...

:: Batch file
(
echo @echo off
echo title Claude WeChat Bridge
echo cd /d "%USERPROFILE%"
echo node .claude\wechat-bridge.mjs
echo echo Bridge stopped.
echo pause ^>nul
) > "%USERPROFILE%\.claude\start-wechat-channel.bat"
echo [OK] Created start-wechat-channel.bat

:: VBS auto-start
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "%STARTUP_DIR%" (
    echo CreateObject^("Wscript.Shell"^).Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False > "%STARTUP_DIR%\claude-wechat.vbs"
    echo [OK] Created startup VBS
) else (
    echo [WARN] Startup folder not found, skipped auto-start
)

echo.
echo =============================================
echo  Installation Complete!
echo.
echo  Next steps:
echo   1. Scan QR code: run 'curl -s https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3'
echo   2. Save credentials to %USERPROFILE%\.claude\channels\wechat\account.json
echo   3. Start bridge: node %USERPROFILE%\.claude\wechat-bridge.mjs
echo.
echo  For image description, also:
echo   4. Register Tencent Cloud and save API keys
echo   5. See README.md for details
echo =============================================
pause
