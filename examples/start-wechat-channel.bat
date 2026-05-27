@echo off
title Claude WeChat Bridge
cd /d %USERPROFILE%
echo Starting WeChat Bridge...
node wechat-bridge.mjs
echo Bridge stopped.
pause >/dev/null
