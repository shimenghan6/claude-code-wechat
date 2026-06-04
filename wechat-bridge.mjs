#!/usr/bin/env node
/**
 * WeChat → Claude Code bridge
 * Uses @weixin-claw/core for proper media handling (image/voice/file/video).
 * All messages feed into a single Claude Code session via --resume.
 */

import { spawn, execSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { homedir } from "node:os";

// Kill old bridge AND channel instances on startup (prevent duplicate replies)
const PID_FILE = resolve(homedir(), ".claude", "channels", "wechat", "bridge.pid");
try {
  const oldPid = parseInt(readFileSync(PID_FILE, "utf-8").trim(), 10);
  if (oldPid && oldPid !== process.pid) {
    try { process.kill(oldPid); } catch {}
  }
} catch {}
// Kill old wechat/node processes EXCEPT current one
try {
  execSync(`powershell -Command "Get-WmiObject Win32_Process -Filter 'Name=\\"node.exe\\"' | Where-Object { $_.CommandLine -match 'wechat-bridge|wechat-channel|cli\\\\.mjs.*start' -and $_.ProcessId -ne ${process.pid} } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"`, { stdio: "ignore", timeout: 5000 });
} catch {}
// Small delay to ensure ports are freed
await new Promise(r => setTimeout(r, 1000));
writeFileSync(PID_FILE, String(process.pid));
process.on("exit", () => { try { require("fs").unlinkSync(PID_FILE); } catch {} });

// Auto-detect npm global path (cross-platform)
function getNpmGlobalPath() {
  try { return execSync("npm root -g", { encoding: "utf-8", stdio: ["pipe","pipe","pipe"] }).trim(); } catch {}
  const home = homedir();
  for (const p of [
    `${home}/AppData/Roaming/npm/node_modules`,  // Windows
    "/usr/local/lib/node_modules",                // macOS
    "/usr/lib/node_modules",                      // Linux
  ]) { try { if (existsSync(p)) return p; } catch {} }
  return null;
}
const GNM = getNpmGlobalPath();
if (!GNM) { console.error("ERROR: Cannot find npm global node_modules."); process.exit(1); }
const { downloadMediaFromItem } = await import(`file://${GNM}/@weixin-claw/core/dist/media/media-download.js`);
const { CDN_BASE_URL } = await import(`file://${GNM}/@weixin-claw/core/dist/auth/accounts.js`);

const HOME = homedir();
const CREDENTIALS_FILE = resolve(HOME, ".claude", "channels", "wechat", "account.json");
const SYNC_BUF_FILE = resolve(HOME, ".claude", "channels", "wechat", "sync_buf.txt");
const DEFAULT_BASE_URL = "https://ilinkai.weixin.qq.com";
const LONG_POLL_TIMEOUT = 35000;
const MAX_RETRIES = 3;
const RETRY_DELAY = 30000;

function log(msg) {
  console.log(`[wechat-bridge] ${msg}`);
}

function logError(msg) {
  console.error(`[wechat-bridge] ERROR: ${msg}`);
}

// Load credentials
let account;
try {
  account = JSON.parse(readFileSync(CREDENTIALS_FILE, "utf-8"));
  log(`已加载账号: ${account.accountId}`);
} catch (e) {
  logError(`无法加载凭证: ${e.message}`);
  process.exit(1);
}

const baseUrl = account.baseUrl || DEFAULT_BASE_URL;
const token = account.token;

function buildHeaders(body) {
  const headers = {
    "Content-Type": "application/json",
    "AuthorizationType": "ilink_bot_token",
    "X-WECHAT-UIN": String(Math.floor(Math.random() * 100000000)),
  };
  if (body) {
    headers["Content-Length"] = String(Buffer.byteLength(body, "utf-8"));
  }
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

async function apiFetch(endpoint, body, timeoutMs = 30000) {
  const url = `${baseUrl.replace(/\/$/, "")}/${endpoint}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      method: body ? "POST" : "GET",
      headers: buildHeaders(body),
      body,
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!res.ok) {
      throw new Error(`HTTP ${res.status}`);
    }
    return await res.text();
  } catch (err) {
    clearTimeout(timer);
    if (err.name === "AbortError") return null;
    throw err;
  }
}

async function getUpdates(buf) {
  const raw = await apiFetch(
    "ilink/bot/getupdates",
    JSON.stringify({
      get_updates_buf: buf,
      base_info: { channel_version: "0.1.0" },
    }),
    LONG_POLL_TIMEOUT
  );
  if (!raw) return { ret: 0, msgs: [], get_updates_buf: buf };
  return JSON.parse(raw);
}

function stripMarkdown(text) {
  return text
    .replace(/```[\s\S]*?```/g, '')     // code blocks → remove
    .replace(/`([^`]+)`/g, '$1')        // inline code → plain
    .replace(/\*\*([^*]+)\*\*/g, '$1')  // bold → plain
    .replace(/\*([^*]+)\*/g, '$1')      // italic → plain
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1') // links → text only
    .replace(/^[#]{1,6}\s+/gm, '')      // headings → plain
    .replace(/^[-*+]\s+/gm, '· ')       // bullet points → dot
    .replace(/^\d+\.\s+/gm, '')         // numbered lists → plain
    .replace(/\n{3,}/g, '\n\n')         // collapse multiple newlines
    .trim();
}

async function sendMessage(to, text, contextToken) {
  text = stripMarkdown(text);
  const clientId = `claude-code-wechat:${Date.now()}-${Math.random().toString(16).slice(2, 10)}`;
  const body = JSON.stringify({
    msg: {
      from_user_id: "",
      to_user_id: to,
      client_id: clientId,
      message_type: 2, // MSG_TYPE_BOT
      message_state: 2, // MSG_STATE_FINISH
      item_list: [{ type: 1, text_item: { text } }], // MSG_ITEM_TEXT = 1
      context_token: contextToken || "",
    },
    base_info: { channel_version: "0.1.0" },
  });
  await apiFetch("ilink/bot/sendmessage", body, 15000);
  log(`已回复: ${text.slice(0, 50)}...`);
}

const SESSION_ID = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";

// Auto-detect Python (use forward slashes for cross-platform spawn compatibility)
function getPython() {
  const home = homedir().replace(/\\/g, "/");
  const paths = [
    `${home}/AppData/Local/Programs/Python/Python312/python.exe`,
    `${home}/AppData/Local/Programs/Python/Python311/python.exe`,
    "python3", "python",
  ];
  for (const cmd of paths) {
    try {
      if (existsSync(cmd)) { execSync(`"${cmd}" --version`, { stdio: "pipe" }); return cmd; }
    } catch {}
  }
  return "python";
}
const PYTHON = getPython();
const MEDIA_PROC = resolve(HOME, ".claude", "media-processor.py");

async function ocrOrTranscribe(type, filepath) {
  return new Promise((resolve) => {
    const child = spawn(PYTHON, [MEDIA_PROC, type, filepath], {
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 120000,
    });
    let out = "", err = "";
    child.stdout.on("data", (d) => out += d);
    child.stderr.on("data", (d) => err += d);
    child.on("close", () => resolve(out.trim() || `[${type}: ${filepath}]`));
    child.on("error", (e) => resolve(`[${type}处理失败: ${e.message}]`));
  });
}
let claudeBusy = false;
const messageQueue = [];

async function callClaude(prompt) {
  // Try --resume first, fall back to --session-id if session doesn't exist
  for (const flag of ["--resume", "--session-id"]) {
    const result = await new Promise((resolve, reject) => {
      // Use stdin to pass prompt (avoids shell escaping issues with spaces/English)
      const child = spawn("claude", ["-p", flag, SESSION_ID], {
        env: { ...process.env, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "", PATH: process.env.PATH },
        stdio: ["pipe", "pipe", "pipe"],
        shell: true,
        timeout: 300000,
      });
      child.stdin.write(prompt);
      child.stdin.end();
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (d) => (stdout += d));
      child.stderr.on("data", (d) => (stderr += d));
      child.on("close", (code) => {
        if (code === 0) resolve({ ok: true, text: stdout.trim() });
        else resolve({ ok: false, error: `claude exited ${code}: ${stderr}` });
      });
      child.on("error", (e) => resolve({ ok: false, error: e.message }));
    });

    if (result.ok) return result.text;
    // Only retry if --resume failed because session doesn't exist
    if (flag === "--resume" && result.error.includes("No conversation found")) {
      log(`Session not found, creating with --session-id`);
      continue;
    }
    throw new Error(result.error);
  }
}

async function processQueue() {
  if (claudeBusy || messageQueue.length === 0) return;
  claudeBusy = true;
  const { msg, from, ctxToken } = messageQueue.shift();
  try {
    const reply = await callClaude(msg);
    if (reply) {
      const maxLen = 2000;
      for (let i = 0; i < reply.length; i += maxLen) {
        await sendMessage(from, reply.slice(i, i + maxLen), ctxToken);
      }
    }
  } catch (e) {
    logError(`处理消息失败: ${e.message}`);
    await sendMessage(from, `[错误] ${e.message}`, ctxToken);
  }
  claudeBusy = false;
  processQueue(); // Process next in queue
}

async function main() {
  // Restore sync buffer
  let buf = "";
  try {
    if (existsSync(SYNC_BUF_FILE)) {
      buf = readFileSync(SYNC_BUF_FILE, "utf-8");
    }
  } catch {}

  log("开始监听微信消息...");

  let failures = 0;
  while (true) {
    try {
      const resp = await getUpdates(buf);
      const isErr =
        (resp.ret !== undefined && resp.ret !== 0) ||
        (resp.errcode !== undefined && resp.errcode !== 0);
      if (isErr) {
        failures++;
        logError(`getUpdates 失败: ret=${resp.ret} errcode=${resp.errcode} errmsg=${resp.errmsg ?? ""}`);
        if (failures >= MAX_RETRIES) {
          logError(`连续失败 ${MAX_RETRIES} 次，等待 ${RETRY_DELAY / 1000}s`);
          failures = 0;
          await new Promise((r) => setTimeout(r, RETRY_DELAY));
        } else {
          await new Promise((r) => setTimeout(r, 2000));
        }
        continue;
      }
      failures = 0;

      if (resp.get_updates_buf) {
        buf = resp.get_updates_buf;
        try { writeFileSync(SYNC_BUF_FILE, buf, "utf-8"); } catch {}
      }

      for (const msg of resp.msgs ?? []) {
        if (msg.message_type !== 1) continue; // 1 = user message
        const from = msg.from_user_id;
        const ctxToken = msg.context_token || "";
        if (!from) continue;

        // Extract text + download media via @weixin-claw/core (handles AES decryption)
        let text = "";
        const mediaPaths = [];
        const mediaDir = resolve(HOME, ".claude", "channels", "wechat", "media");
        mkdirSync(mediaDir, { recursive: true });

        for (const item of msg.item_list ?? []) {
          if (item.type === 1) {
            if (item.text_item?.text) text += item.text_item.text;
          } else if (item.type === 3) {
            if (item.voice_item?.text) text += item.voice_item.text;
          }

          // Download media (image=2, voice=3, file=5, video=4) via @weixin-claw/core
          if ([2, 3, 4, 5].includes(item.type)) {
            try {
              const result = await downloadMediaFromItem(item, {
                cdnBaseUrl: CDN_BASE_URL,
                saveMedia: async (buf, mime, subdir, maxBytes, filename) => {
                  const ext = mime?.split("/")[1] || "bin";
                  const fname = filename || `${Date.now()}_${Math.random().toString(16).slice(2, 8)}.${ext}`;
                  const fpath = resolve(mediaDir, (subdir || "") + "/" + fname);
                  mkdirSync(resolve(mediaDir, subdir || ""), { recursive: true });
                  writeFileSync(fpath, buf.slice(0, maxBytes || buf.length));
                  return { path: fpath };
                },
                log,
                errLog: logError,
                label: "wechat",
              });
              if (result.decryptedPicPath) {
                const ocr = await ocrOrTranscribe("image", result.decryptedPicPath);
                mediaPaths.push(`[图片OCR结果]\n${ocr}`);
              }
              if (result.decryptedVoicePath) {
                const txt = await ocrOrTranscribe("voice", result.decryptedVoicePath);
                mediaPaths.push(`[语音转写]\n${txt}`);
              }
              if (result.decryptedFilePath) {
                mediaPaths.push(`[文件: ${result.decryptedFilePath}]`);
              }
              if (result.decryptedVideoPath) {
                const txt = await ocrOrTranscribe("video", result.decryptedVideoPath);
                mediaPaths.push(`[视频内容]\n${txt}`);
              }
            } catch (e) {
              logError(`媒体处理失败: ${e.message}`);
            }
          }
        }
        if (!text && mediaPaths.length === 0) continue;

        // Handle built-in commands (natural Chinese aliases)
        const normalized = text.trim();
        if (normalized === "/restart" || normalized === "重新打开会话" || normalized === "重启会话") {
          await sendMessage(from, "会话已刷新。每次微信消息都独立调用 Claude，历史记录全保留。", ctxToken);
          log(`会话刷新: ${from}`);
          continue;
        }

        const prompt = text + (mediaPaths.length ? "\n" + mediaPaths.join("\n") : "");

        log(`收到消息: from=${from} text=${text.slice(0, 100)} media=${mediaPaths.length}`);

        messageQueue.push({ msg: prompt, from, ctxToken });
        processQueue();
      }
    } catch (e) {
      failures++;
      logError(`轮询异常: ${e.message}`);
      if (failures >= MAX_RETRIES) {
        await new Promise((r) => setTimeout(r, RETRY_DELAY));
        failures = 0;
      }
    }
  }
}

// Self-healing: auto-restart on crash (prevents manual intervention)
async function runWithRestart() {
  while (true) {
    try {
      await main();
    } catch (e) {
      logError(`Bridge crashed: ${e.message}`);
      log(`Restarting in 5s...`);
      await new Promise(r => setTimeout(r, 5000));
    }
  }
}

runWithRestart();
