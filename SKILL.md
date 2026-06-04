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
watchdog.py                              ← 外部守护（杀旧进程 + 自愈）
  └─ node wechat-bridge.mjs              ← 内部自愈（runWithRestart）
       └─ main()                         ← 微信 iLink API 长轮询
            ├─ PaddleOCR (识字)
            ├─ 腾讯云 TIIA (识景)
            ├─ Whisper (语音→文字)
            └─ FFmpeg (视频分离)
```

**双层防护**：
- 内部：`runWithRestart()` 包裹 main()，JS 异常 5 秒自动恢复
- 外部：`watchdog.py` 监控 node 进程，被杀/崩溃 10 秒拉新，启动前杀旧进程保唯一

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
python ~/.claude/watchdog.py
```

或用 `start-wechat-channel.bat`（双击即跑）。

### 7. 开机自启

运行 `install.bat` 自动配置 VBS 到启动文件夹。

## 踩坑记录（19 个）

### 1-12（历史坑）

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

### 13. MSYS2 start 命令无法启动 CMD 窗口（2026-06-04）

**现象**：在 MSYS2/Git Bash 中执行 `start "title" cmd /k "batch.bat"` 时，`/k` 被 MSYS2 路径转换吞掉，变成 `C:/Program Files/Git/k`，导致 CMD 窗口无法正常启动。

**根因**：MSYS2 自动将 `/k`、`/F` 等以 `/` 开头的参数当成 Unix 路径转换。

**解决**：
- 用 `MSYS_NO_PATHCONV=1` 前缀禁用路径转换
- 或用 Python `subprocess.Popen` 直接启动 Windows 进程
- 或用 PowerShell `Start-Process` 启动
- **最可靠**：用 VBS + `CreateObject("Wscript.Shell").Run` 启动

### 14. HP Modern Standby (S0) 导致反复休眠（2026-06-04）

**现象**：电脑反复进入睡眠状态，设置 `standby-timeout-ac 0` 无效。

**根因**：HP 笔记本使用 Modern Standby (S0 低电量待机)，传统 S3 睡眠超时对其无效。HP Optimized 电源方案会主动触发 S0 空闲。

**解决**：
```bash
# 切换到高性能电源方案（压制 Modern Standby）
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
# 所有睡眠超时设为 0（从不）
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
```

**铁律**：安装/修复微信桥接时，必须同时把电源方案切到高性能。

### 15. Python 子进程多重启动 → 6+ 进程（2026-06-04）

**现象**：用多种方式启动桥接（`nohup &`、`os.startfile`、`subprocess.Popen`、VBS、直接 `node`）后，出现 6 个以上 node 进程同时回复。

**根因**：每种启动方式都绕过 `wechat-bridge.mjs` 的旧进程清理逻辑。桥接的清理代码只在自身启动时执行一次，多实例同时启动时互不可见。

**解决**：
- 统一入口：`watchdog.py` 是唯一启动方式
- watchdog 启动前先 `powercfg` 杀所有旧 node
- 桥接内部 `runWithRestart()` 自愈
- **铁律**：永远不要直接 `node wechat-bridge.mjs`，只用 `python watchdog.py`

### 16. 桥接自愈双层架构（2026-06-04）

**现象**：桥接崩溃后不会自动恢复，必须手动重启。

**解决**：
- 外部层 `watchdog.py`：`while True: kill_old() → start node → wait → restart`
- 内部层 `wechat-bridge.mjs`：`runWithRestart() { while(true) { try { await main() } catch { sleep 5 } } }`
- 外部 kill 进程 → watchdog 10 秒拉新
- JS 内部崩溃 → runWithRestart 5 秒自愈
- 始终单进程（启动前强制杀旧）

### 17. install.bat 全自动铁律（2026-06-04）

**禁止**：
- `pause` — 会卡住安装流程
- `set /p` — 交互式输入，无法全自动
- `exit /b 1` — 直接关窗口，用户看不到错误
- `start cmd /k` — 弹出新终端窗口

**必须**：
- 缺环境用 `winget` 自动安装，不跳网页
- 失败用 `[警告]` 标记，继续执行
- 末尾 `pause >nul` 保持窗口不关闭
- 安装完自动启动 watchdog

### 18. 打包前必须同步本地 skill（2026-06-04）

**铁律**：打包 ZIP 前，必须先把最新源文件同步到 `~/.claude/skills/<name>/`，否则 ZIP 内是旧版本。

```python
# 微信文件从 ~/.claude/ 同步到 skill 目录
wechat_files = ['wechat-bridge.mjs', 'watchdog.py', 'media-processor.py', 
                'cloud_vision.py', 'start-wechat-channel.bat']
for f in wechat_files:
    shutil.copy(f'~/.claude/{f}', f'~/.claude/skills/claude-code-wechat/{f}')
```

### 19. Claude Code auto classifier 连锁封锁（2026-06-04）

**现象**：编辑 `settings.json` 添加白名单后，auto classifier 开始拒绝大量后续命令（taskkill、写 .claude 文件等）。

**教训**：settings.json 的白名单修改会被 classifier 标记为"self-modification"，导致后续操作被连锁拦截。修改 settings.json 前需要用户明确授权。如果 classifier 封锁，只能让用户在桌面端批准。

## 多媒体管线

| 图片识字 | `python media-processor.py image <path>` → PaddleOCR |
| 图片识景 | `python cloud-vision.py describe <path>` → 腾讯云 TIIA |
| 语音转文 | `python media-processor.py voice <path>` → Whisper |
| 视频分析 | `python media-processor.py video <path>` → FFmpeg + Whisper + OCR |

### FFmpeg 路径

安装后找到 `ffmpeg.exe` 绝对路径，更新 `media-processor.py` 中 `_FFMPEG_BASE` 或加入系统 PATH。

### 腾讯云 API

每月 1000 次免费，需实名认证。密钥保存到 `~/.claude/tencent-cloud/credentials.json`。
