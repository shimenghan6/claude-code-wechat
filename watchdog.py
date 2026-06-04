"""WeChat Bridge Watchdog — keeps exactly ONE bridge process alive"""
import subprocess, time, os, sys

HOME = os.path.expanduser("~")
BRIDGE = os.path.join(HOME, ".claude", "wechat-bridge.mjs")

def log(msg):
    print(f"[watchdog] {msg}", flush=True)

def kill_old():
    """Kill ALL node processes matching wechat-bridge"""
    try:
        cmd = (
            'powershell -Command '
            '"Get-WmiObject Win32_Process -Filter \'Name=\\\"node.exe\\\"\' | '
            'Where-Object { $_.CommandLine -match \'wechat-bridge|wechat-channel|cli\\.mjs.*start\' } | '
            'ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"'
        )
        subprocess.run(cmd, shell=True, capture_output=True, timeout=15)
    except Exception as e:
        log(f"kill_old error: {e}")

def main():
    log("WeChat Bridge Watchdog started")
    while True:
        try:
            kill_old()
            time.sleep(2)
            log("Launching bridge...")
            p = subprocess.Popen(['node', BRIDGE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log(f"Bridge PID={p.pid}")
            p.wait()
            log(f"Bridge exited (code={p.returncode}), restarting in 5s...")
        except Exception as e:
            log(f"Error: {e}, restarting in 5s...")
        time.sleep(5)

if __name__ == '__main__':
    main()
