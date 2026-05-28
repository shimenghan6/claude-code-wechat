# Claude Code WeChat Bridge

> 在微信里遥控你的电脑。发条消息，Claude Code 帮你写代码、搜网页、改文件、执行命令——就像坐在电脑前一样。

**协议：微信 ClawBot iLink Bot API · 会话：`claude -p --resume` 持久化 · 媒体：CDN AES-128-ECB 解密 + PaddleOCR + Whisper + FFmpeg**

```
地铁上发微信：  "帮我在项目里加一个导出功能"
                  ↓
            电脑上的 Claude Code 自动写代码、跑测试
                  ↓
              微信收到回复："已完成，commit 了"
```

**只需要一部 iPhone 和微信。不用 VPN，不用服务器，不用付费 API。扫码即用，开机自启，盒盖不休眠。**

### 能做什么

| 你发微信 | 电脑上的 Claude 做什么 |
|---------|---------------------|
| "帮我写一个爬虫" | 打开编辑器，写完代码 |
| "搜一下杭州天气" | 打开浏览器搜索，截图回复 |
| 发一张图片 | OCR 识字 + 场景识别，描述回复 |
| 发一段语音 | Whisper 转文字，处理后回复 |
| 发一个视频 | FFmpeg 提取音频+关键帧，分析回复 |
| "执行 npm run build" | 跑命令，把结果发回来 |
| "帮我把电脑休眠" | 执行休眠指令 |

### 谁需要这个

| 你 | 为什么你需要 |
|----|------------|
| 离开电脑但想继续干活 | 微信就是你的终端，随时远程 |
| 笔记本盒盖了不想打开 | 桥接后台常驻，盒盖也能响应 |
| 用的是 DeepSeek/第三方 API | 官方 Channel 要 Anthropic 订阅，这个不用 |
| 想给团队共享 AI 能力 | 一个微信 bot，全组都能用 |

---

```
微信 (iOS) → ClawBot 插件 → iLink API → wechat-bridge → Claude Code (同一会话)
```

## 目录

1. [前提条件](#前提条件)
2. [一键安装](#一键安装)
3. [工作原理](#工作原理)
4. [踩坑记录](#踩坑记录)
5. [多媒体管线](#多媒体管线)
6. [开机自启与电源管理](#开机自启与电源管理)
7. [架构详解](#架构详解)
8. [故障排查](#故障排查)

---

## 前提条件

| 条件 | 说明 |
|------|------|
| 微信 iOS | ClawBot 插件（我 → 设置 → 插件） |
| Node.js >= 18 | `https://nodejs.org` |
| Claude Code >= 2.1.80 | `npm install -g @anthropic-ai/claude-code` |
| Python >= 3.10 | 多媒体处理脚本 |
| 网络畅通 | 可访问 `ilinkai.weixin.qq.com` |
| Windows 10/11 | 开机自启脚本适用 |

---

## 一键安装

### Windows

1. 下载 `install.bat` → **双击运行**
2. 按提示扫码 → 粘贴凭证 → 完成

```bash
# 或者一行命令
curl -fsSL https://raw.githubusercontent.com/shimenghan6/claude-code-wechat/master/install.bat -o install.bat && install.bat
```

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/shimenghan6/claude-code-wechat/master/install.sh | bash
```

### 手动安装

```bash
git clone https://github.com/shimenghan6/claude-code-wechat.git ~/.claude/skills/claude-code-wechat
cd ~/.claude/skills/claude-code-wechat
npm install -g claude-code-wechat-channel @weixin-claw/core
pip install paddleocr openai-whisper tencentcloud-sdk-python
```

### 扫码认证

```bash
# 获取扫码链接
curl -s "https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3"
```

手机打开返回的 `qrcode_img_content` 链接，自动跳微信授权。

扫码后轮询凭证（`status` 变为 `confirmed`）：

```bash
curl -s "https://ilinkai.weixin.qq.com/ilink/bot/get_qrcode_status?qrcode={qrcode}" \
  -H "iLink-App-ClientVersion: 1"
```

保存凭证（**key 名必须是 `token` 不是 `botToken`**）：

```bash
mkdir -p ~/.claude/channels/wechat
cat > ~/.claude/channels/wechat/account.json << EOF
{
  "baseUrl": "https://ilinkai.weixin.qq.com",
  "token": "{bot_token}",
  "accountId": "{ilink_bot_id}",
  "userId": "{ilink_user_id}",
  "savedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
}
EOF
```

### 4. 配置 Claude Code

创建 `~/.mcp.json`：
```json
{
  "mcpServers": {
    "wechat": {
      "command": "npx",
      "args": ["-y", "claude-code-wechat-channel", "start"]
    }
  }
}
```

在 `~/.claude/settings.local.json` 禁用 MCP channel（防止双重回复）：
```json
{
  "enabledMcpjsonServers": [],
  "enableAllProjectMcpServers": false
}
```

在 `~/.claude/settings.json` 的 `env` 中删除 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`。

### 5. 启动

```bash
node wechat-bridge.mjs
```

看到 `[wechat-bridge] 开始监听微信消息...` 即可。

### 6. (可选) 图片识景功能

图片描述需要腾讯云 API（1000次/月免费）：

1. 注册 [腾讯云](https://cloud.tencent.com)，完成实名认证
2. 进入 [API 密钥管理](https://console.cloud.tencent.com/cam/capi) 创建密钥
3. 在 [OCR 控制台](https://console.cloud.tencent.com/ocr/overview) 点击"立即开通"
4. 保存密钥到 `~/.claude/tencent-cloud/credentials.json`：
```json
{
  "SecretId": "AKIDxxxxxxxx",
  "SecretKey": "xxxxxxxx"
}
```

### 7. (可选) 开机自启

运行 `install.bat` 或以管理员身份手动创建：

创建 `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-wechat.vbs`：
```vbscript
CreateObject("Wscript.Shell").Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False
```

创建 `~/.claude/start-wechat-channel.bat`：
```batch
@echo off
title Claude WeChat Bridge
cd /d %USERPROFILE%
node wechat-bridge.mjs
echo Bridge stopped.
pause >nul
```

### 8. (可选) 盒盖不休眠

```bash
powercfg -SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -SETACTIVE SCHEME_CURRENT
```

---

## 工作原理

```
┌──────────┐    ┌─────────────┐    ┌──────────────┐    ┌────────────────┐
│ 微信 iOS │───▶│ ClawBot 插件 │───▶│ iLink API     │───▶│ wechat-bridge  │
│          │◀───│ (我→设置→   │◀───│ (ilinkai.     │◀───│ (Node.js 常驻) │
│          │    │  插件)      │    │  weixin.      │    │                │
└──────────┘    └─────────────┘    │  qq.com)      │    └───────┬────────┘
                                   └──────────────┘            │
                                                         claude -p
                                              --resume <session-uuid>
                                                               │
                                                      ┌────────▼────────┐
                                                      │  Claude Code    │
                                                      │  同一会话       │
                                                      │  上下文连续     │
                                                      └────────┬────────┘
                                                               │
                                          ┌────────────────────┼────────────────────┐
                                          │                    │                    │
                                     PaddleOCR            Whisper              FFmpeg
                                     (图片识字)          (语音转文)          (视频分离)
                                          │                    │                    │
                                    腾讯云 TIIA                                   OCR+Whisper
                                     (图片识景)                                   (帧+音频)
```

### 消息流程

```
1. 微信用户发消息 → ClawBot 插件 → iLink API 长轮询
2. wechat-bridge 收到消息 → 分析 item_list:
   - type 1 (文字) → 直接提取
   - type 2 (图片) → CDN AES解密下载 → media-processor.py → OCR + 标签
   - type 3 (语音) → CDN AES解密下载 → media-processor.py → Whisper 转文字
   - type 4 (视频) → CDN AES解密下载 → media-processor.py → FFmpeg 分离 + Whisper + OCR
   - type 5 (文件) → CDN AES解密下载 → 路径传递给 Claude
3. 组装 prompt → claude -p --resume <UUID> → Claude 处理
4. 回复分段（>2000字自动拆分） → sendMessage → 微信用户收到回复
```

### Session 管理

```
第一条消息:  --resume → "No conversation found" → fallback --session-id → 创建
第二条起:    --resume → 续接同一会话
并发消息:    进入队列，同一时间只跑一个 Claude 进程
```

---

## 踩坑记录

以下是整个接入过程遇到的全部致命坑：

### 1. token key 名错误 → `session timeout`
凭证 key 必须是 `token`，不是 `botToken`。错误写法会导致每次 API 调用返回 `errcode=-14`。

### 2. AuthorizationType header 无横杠
iLink API 要求 `AuthorizationType: ilink_bot_token`。写成 `Authorization-Type`（加横杠）会导致鉴权失败。

### 3. 消息文本结构不对
文本在 `msg.item_list[0].text_item.text`，不是 `msg.msg_content`。找错字段导致所有消息被静默丢弃。

### 4. 发送消息需要完整格式
发送需 `message_type: 2`（BOT）、`message_state: 2`（FINISH）、`item_list` 结构，必须带 `context_token` 和 `base_info`。

### 5. --session-id 并发冲突
`claude -p --session-id <UUID>` 不能并发调用。同一 session 两个进程 → `Session already in use`。

### 6. --resume / --session-id 双保险
首次 `--resume` 报 "No conversation found" → `--session-id` 创建。之后 `--resume` 续接。bridge 内置此逻辑。

### 7. --channels 需要 Anthropic 订阅
`--dangerously-load-development-channels` 功能需要 claude.ai Pro/Max 订阅。DeepSeek 等第三方 API 用户不可用，必须用 bridge 模式。

### 8. NONESSENTIAL_TRAFFIC 拦截
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` 关闭 GrowthBook → Channels 功能全部返回 false。需从 settings.json 删除。

### 9. 双重/多重回复
多个 bridge 进程或 MCP channel + bridge 同时消费消息 → 重复回复。确保 settings.local.json 中 enabledMcpjsonServers 为空，且只有一个 bridge 进程。

### 10. 多媒体 CDN 加密
图片/语音/视频通过 CDN AES-128-ECB 加密传输。字段名为 `media.encrypt_query_param` + `aes_key`，不是简单的 `url`。需用 `@weixin-claw/core` 的 `downloadMediaFromItem` 解密。

### 11. PaddlePaddle 3.0 Windows 不支持
PaddlePaddle 3.0 的 oneDNN 后端在 Windows 上有 bug。需降级到 PaddlePaddle 2.6 + PaddleOCR 2.9。

### 12. 重启产生重复进程
多次运行 `node wechat-bridge.mjs` 而不先 kill 旧进程会导致多个 bridge 同时跑 → 多重回复。启动前确保旧进程已停止。

---

## 多媒体管线

| 媒体类型 | 处理器 | 输出 | 需要额外安装 |
|---------|--------|------|------------|
| 图片识字 | PaddleOCR (本地) | 图片中的文字 | `pip install paddleocr paddlepaddle==2.6.2` |
| 图片识景 | 腾讯云 TIIA (云端) | 场景/物体标签 | 腾讯云账号 + API 密钥 |
| 语音转文 | Whisper (本地) | 语音转文字 | `pip install openai-whisper` |
| 视频分析 | FFmpeg + Whisper + PaddleOCR | 音频转写 + 关键帧标签 | `pip install openai-whisper` |

### FFmpeg 安装

```bash
winget install ffmpeg
```

安装后记下路径（通常在 `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin\`），更新 `media-processor.py` 中的 `_FFMPEG_BASE` 或添加到系统 PATH。

### 腾讯云 API 配置

1. 注册腾讯云并实名认证
2. [API 密钥管理](https://console.cloud.tencent.com/cam/capi) 创建 SecretId + SecretKey
3. [OCR 控制台](https://console.cloud.tencent.com/ocr/overview) 点击"立即开通"
4. 保存到 `~/.claude/tencent-cloud/credentials.json`

每月 1000 次免费额度，个人够用。

---

## 开机自启与电源管理

### Windows 开机自启

`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-wechat.vbs`：
```vbscript
CreateObject("Wscript.Shell").Run "cmd /c %USERPROFILE%\.claude\start-wechat-channel.bat", 0, False
```

| mode | 效果 |
|------|------|
| 0 | 完全隐藏 |
| 7 | 最小化（可点开查看） |

### 盒盖不休眠

```bash
powercfg -SETACVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -SETDCVALUEINDEX SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -SETACTIVE SCHEME_CURRENT
```

### 远程休眠

```bash
rundll32.exe powrprof.dll,SetSuspendState 0,1,0
```

---

## 架构详解

### iLink API

腾讯官方 Bot API (`ilinkai.weixin.qq.com`)：

| 端点 | 方法 | 用途 |
|------|------|------|
| `ilink/bot/get_bot_qrcode?bot_type=3` | GET | 获取登录二维码 |
| `ilink/bot/get_qrcode_status?qrcode=xxx` | GET | 轮询扫码状态 |
| `ilink/bot/getupdates` | POST | 长轮询接收消息 (35s timeout) |
| `ilink/bot/sendmessage` | POST | 发送回复 |

### 消息格式

**接收**：
```json
{
  "msgs": [{
    "message_type": 1,
    "from_user_id": "xxx@im.wechat",
    "item_list": [
      { "type": 1, "text_item": { "text": "你好" } },
      { "type": 2, "image_item": { "media": { "encrypt_query_param": "...", "aes_key": "..." } } },
      { "type": 3, "voice_item": { "text": "语音ASR结果", "media": { ... } } }
    ],
    "context_token": "..."
  }]
}
```

**发送**：
```json
{
  "msg": {
    "from_user_id": "",
    "to_user_id": "xxx@im.wechat",
    "client_id": "claude-code-wechat:...",
    "message_type": 2,
    "message_state": 2,
    "item_list": [{ "type": 1, "text_item": { "text": "回复" } }],
    "context_token": "..."
  },
  "base_info": { "channel_version": "0.1.0" }
}
```

### 文件布局

```
~/.claude/
├── channels/wechat/
│   ├── account.json              # 微信 bot 凭证
│   ├── sync_buf.txt              # 长轮询同步状态
│   └── media/inbound/            # 收到的多媒体文件
├── wechat-bridge.mjs             # 核心桥接脚本
├── media-processor.py            # 多媒体处理 (OCR/Whisper/FFmpeg)
├── cloud_vision.py               # 腾讯云图片标签模块
├── cloud-vision.py               # 腾讯云视觉 CLI
├── tencent-cloud/
│   └── credentials.json          # 腾讯云 API 密钥
├── start-wechat-channel.bat      # Windows 启动脚本
└── settings.local.json           # enabledMcpjsonServers: []
```

---

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| `session timeout` (errcode=-14) | 凭证 key 名 `botToken` 应为 `token` | 修改 account.json |
| `session timeout` | 重复扫码创建新 bot | 用最初扫码的 token |
| 收不到消息 | 微信连了错误的 bot | 扫码后确认在最新 ClawBot 对话 |
| 双重/多重回复 | 多个 bridge 进程 | `taskkill /F /IM node.exe` 后重启 |
| `already in use` | session 并发冲突 | 确认 bridge 消息队列生效 |
| `No conversation found` | 首次用 `--resume` | bridge 自动回退 `--session-id` |
| `Channels not available` | 非 Anthropic 官方 API | 用 bridge 模式，不依赖 Channels |
| 图片识别无结果 | PaddleOCR 引擎故障 | 降级 PaddlePaddle 2.6 + PaddleOCR 2.9 |
| 图片识景报错 | 腾讯云未开通 | 控制台开通 OCR + TIIA |
| 语音识别报错 | FFmpeg 不在 PATH | 添加 FFmpeg bin 目录到系统 PATH |
| 消息超长 | 微信限制 2000 字 | bridge 自动分段 |
| 桥接进程退出 | token 过期 | 重新扫码获取新 token |
| 停止桥接 | — | `taskkill /F /IM node.exe` |
| 重启桥接 | — | `node ~/.claude/wechat-bridge.mjs` |

---

## 相关项目

- [claude-code-wechat-channel](https://www.npmjs.com/package/claude-code-wechat-channel) — iLink API npm 封装
- [@weixin-claw/core](https://www.npmjs.com/package/@weixin-claw/core) — CDN 多媒体加解密
- [OpenClaw](https://github.com/openclaw/openclaw) — 多通道 AI Agent 网关
- [ClawBot 协议分析](https://docs.openclaw.ai) — OpenClaw 官方文档

## License

MIT
