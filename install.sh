#!/bin/bash
set -e
echo "============================================="
echo "  Claude Code WeChat Bridge - Install"
echo "============================================="

# Install Node deps
echo "[1/3] Installing Node.js packages..."
npm install -g claude-code-wechat-channel @weixin-claw/core

# Install Python deps
echo "[2/3] Installing Python packages..."
pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python

# Copy files
echo "[3/3] Copying bridge files..."
cp wechat-bridge.mjs ~/.claude/
cp media-processor.py ~/.claude/
cp cloud_vision.py ~/.claude/
cp cloud-vision.py ~/.claude/

echo ""
echo "Done. Next: scan QR code & start bridge."
echo "  curl -s https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3"
echo "  node ~/.claude/wechat-bridge.mjs"
