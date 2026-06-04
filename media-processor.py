#!/usr/bin/env python3
"""Media processor for WeChat Bridge. All local, zero API cost.
- Image: CLIP scene detection (free) + PaddleOCR text (free)
- Voice: Whisper speech-to-text (free)
- Video: Whisper audio + frame OCR (free)
Outputs text to stdout in UTF-8."""

import sys, os, subprocess
from pathlib import Path

CACHE_DIR = os.path.expanduser("~/.claude/channels/wechat/media/processed")
os.makedirs(CACHE_DIR, exist_ok=True)

# FFmpeg path (winget install)
_FFMPEG_BASE = os.path.expanduser(
    "~/AppData/Local/Microsoft/WinGet/Packages/"
    "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.1.1-full_build/bin"
)
if os.path.isdir(_FFMPEG_BASE):
    os.environ["PATH"] = _FFMPEG_BASE + ";" + os.environ.get("PATH", "")
FFMPEG = os.path.join(_FFMPEG_BASE, "ffmpeg.exe") if os.path.isdir(_FFMPEG_BASE) else "ffmpeg"

# Force UTF-8 for stdout
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# PaddleOCR singleton
_ocr = None


def _get_ocr():
    global _ocr
    if _ocr is None:
        from paddleocr import PaddleOCR
        _ocr = PaddleOCR(lang="ch", show_log=False)
    return _ocr


def _detect_scene(path):
    """Free local scene detection via CLIP."""
    try:
        from local_vision import describe_image
        result = describe_image(path)
        return result
    except Exception:
        return None


def ocr_image(path):
    """Image analysis: CLIP scene detection + PaddleOCR text (all local, free)."""
    parts = []

    # 1. Free local scene classification (CLIP, replaces TIIA)
    try:
        scene = _detect_scene(path)
        if scene:
            parts.append(scene)
    except Exception:
        pass

    # 2. Free local OCR (PaddleOCR)
    try:
        ocr = _get_ocr()
        result = ocr.ocr(path)
        lines = []
        if result and result[0]:
            for line in result[0]:
                text = line[1][0]
                if text.strip():
                    lines.append(text.strip())
        if lines:
            parts.append(f"[图片文字]\n" + "\n".join(lines))
    except Exception:
        pass

    return "\n".join(parts) if parts else "[未识别到内容]"


def transcribe_voice(path):
    """Free local speech recognition via Whisper."""
    import whisper
    model = whisper.load_model("medium")
    result = model.transcribe(path, language="zh")
    return result["text"].strip() or "[Whisper: 未识别到语音]"


def process_video(path):
    """Video processing: Whisper audio + frame OCR (all local, free)."""
    output = []
    basename = Path(path).stem

    # Extract and transcribe audio
    audio_path = os.path.join(CACHE_DIR, f"{basename}_audio.wav")
    subprocess.run([
        FFMPEG, "-i", path, "-vn", "-acodec", "pcm_s16le",
        "-ar", "16000", "-ac", "1", audio_path, "-y"
    ], capture_output=True)

    if os.path.exists(audio_path) and os.path.getsize(audio_path) > 1000:
        try:
            text = transcribe_voice(audio_path)
            output.append(f"[语音转写]\n{text}")
        except Exception as e:
            output.append(f"[语音转写失败: {e}]")

    # Extract key frames and OCR
    frames_dir = os.path.join(CACHE_DIR, f"{basename}_frames")
    os.makedirs(frames_dir, exist_ok=True)
    subprocess.run([
        FFMPEG, "-i", path, "-vf", "fps=1/5",
        os.path.join(frames_dir, "frame_%03d.jpg"), "-y"
    ], capture_output=True)

    frames = sorted(Path(frames_dir).glob("frame_*.jpg"))
    if frames:
        output.append(f"\n[关键帧OCR ({len(frames)}帧)]")
        for f in frames[:6]:
            try:
                text = ocr_image(str(f))
                if text and "[未识别到内容]" not in text:
                    output.append(f"--- {f.name} ---\n{text}")
            except Exception as e:
                pass

    return "\n".join(output) if output else "[视频处理完成]"


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: media-processor.py <image|voice|video> <filepath>")
        sys.exit(1)

    mtype = sys.argv[1]
    fpath = sys.argv[2]

    if not os.path.exists(fpath):
        print(f"[错误: 文件不存在: {fpath}]")
        sys.exit(1)

    try:
        if mtype == "image":
            print(ocr_image(fpath))
        elif mtype == "voice":
            print(transcribe_voice(fpath))
        elif mtype == "video":
            print(process_video(fpath))
    except Exception as e:
        print(f"[处理失败: {e}]")
