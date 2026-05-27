---
name: claude-code-wechat
description: |
  将 Claude Code 接入微信 ClawBot，文字/图片/语音/视频/文件全支持，上下文连续，记忆保持。
  一键安装，支持扫码登录、多媒体处理、开机自启。
  触发条件："接入微信", "微信控制Claude", "Claude Code微信",
  "clawbot连接", "微信机器人配置", "setup wechat channel",
  "微信桥接", "wechat bridge"
---

# Claude Code → 微信 ClawBot 接入技能

## 核心架构

```
微信 → iLink API → wechat-bridge → claude -p --resume (同一会话)
                       ├─ PaddleOCR (识字)
                       ├─ 腾讯云 TIIA (识景)
                       ├─ Whisper (语音→文字)
                       └─ FFmpeg (视频分离)
```

## 一键接入流程

### 1. 安装全部依赖

```bash
npm install -g claude-code-wechat-channel @weixin-claw/core
pip install paddleocr==2.9.1 paddlepaddle==2.6.2 openai-whisper tencentcloud-sdk-python
winget install ffmpeg
```

或直接运行本目录下的 `install.bat`。

### 2. 扫码认证（直接拿链接，不用 ASCII 二维码）

```bash
curl -s "https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3"
```

手机打开 `qrcode_img_content` 链接，2 分钟内扫码。

### 3. 保存凭证

```bash
curl -s "https://ilinkai.weixin.qq.com/ilink/bot/get_qrcode_status?qrcode={qrcode}" \
  -H "iLink-App-ClientVersion: 1"
```

保存到 `~/.claude/channels/wechat/account.json`（**key 名必须是 `token` 不是 `botToken`**）。

### 4. 配置 Claude Code

- 创建 `~/.mcp.json`（wechat MCP server）
- `~/.claude/settings.local.json` 设 `enabledMcpjsonServers: []`
- 删除 `~/.claude/settings.json` 中的 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`

### 5. (可选) 图片识景

注册腾讯云 → 获取 API 密钥 → 保存到 `~/.claude/tencent-cloud/credentials.json` → 开通 OCR 服务。

### 6. 启动

```bash
node ~/.claude/wechat-bridge.mjs
```

### 7. 开机自启

运行 `install.bat` 自动配置，或手动创建 VBS 到启动文件夹。

## 12 个踩坑记录

详见 README.md 踩坑记录章节。核心：
1. token vs botToken key 名
2. AuthorizationType 无横杠
3. item_list[0].text_item.text 结构
4. 发送消息完整格式 (message_type:2, message_state:2, context_token, base_info)
5. --session-id 不能并发
6. --resume + --session-id 双保险
7. Channels 需 Anthropic 订阅
8. NONESSENTIAL_TRAFFIC 拦截
9. 多进程双重回复
10. CDN AES-128-ECB 加密
11. PaddlePaddle 3.0 Windows bug → 降级 2.6
12. 重启不杀旧进程 → 多重回复

## 多媒体管线

| 图片识字 | `python media-processor.py image <path>` → PaddleOCR |
| 图片识景 | `python cloud-vision.py describe <path>` → 腾讯云 TIIA |
| 语音转文 | `python media-processor.py voice <path>` → Whisper |
| 视频分析 | `python media-processor.py video <path>` → FFmpeg + Whisper + OCR |

### FFmpeg 路径

安装后找到 `ffmpeg.exe` 绝对路径，更新 `media-processor.py` 中 `_FFMPEG_BASE` 或加入系统 PATH。

### 腾讯云 API

每月 1000 次免费，需实名认证。密钥保存到 `~/.claude/tencent-cloud/credentials.json`。
