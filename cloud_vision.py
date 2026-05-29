#!/usr/bin/env python3
"""Tencent Cloud Vision API integration for WeChat Bridge."""
import sys, os, json, base64
from pathlib import Path

CRED_FILE = os.path.expanduser("~/.claude/tencent-cloud/credentials.json")
if not os.path.exists(CRED_FILE):
    print("[错误: 未找到腾讯云凭证，请先运行注册流程]")
    sys.exit(1)

with open(CRED_FILE) as f:
    cred = json.load(f)

from tencentcloud.common import credential
from tencentcloud.common.exception.tencent_cloud_sdk_exception import TencentCloudSDKException

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')


def image_to_base64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def ocr_general(path):
    """通用印刷体识别 — 1000次/月免费"""
    from tencentcloud.ocr.v20181119 import ocr_client, models as ocr_models
    c = credential.Credential(cred["SecretId"], cred["SecretKey"])
    client = ocr_client.OcrClient(c, "ap-guangzhou")
    req = ocr_models.GeneralBasicOCRRequest()
    req.ImageBase64 = image_to_base64(path)
    resp = client.GeneralBasicOCR(req)
    texts = [d.DetectedText for d in resp.TextDetections] if resp.TextDetections else []
    return "\n".join(texts) if texts else "[OCR: 未识别到文字]"


def image_tag(path):
    """图像标签识别 — 识别场景/物体，1000次/月免费"""
    from tencentcloud.tiia.v20190529 import tiia_client, models as tiia_models
    c = credential.Credential(cred["SecretId"], cred["SecretKey"])
    client = tiia_client.TiiaClient(c, "ap-guangzhou")
    req = tiia_models.DetectLabelRequest()
    req.ImageBase64 = image_to_base64(path)
    resp = client.DetectLabel(req)
    labels = []
    if resp.Labels:
        for l in resp.Labels[:10]:
            labels.append(f"{l.Name}({int(l.Confidence)}%)")
    return ", ".join(labels) if labels else "[未识别到标签]"


def image_describe(path):
    """图片综合描述：OCR文字 + 图像标签"""
    parts = []
    try:
        tags = image_tag(path)
        if tags and "[未识别到标签]" not in tags:
            parts.append(f"[图片场景] {tags}")
    except Exception as e:
        parts.append(f"[标签识别失败: {e}]")

    try:
        ocr_text = ocr_general(path)
        if ocr_text and "[OCR: 未识别到文字]" not in ocr_text:
            parts.append(f"[图片文字]\n{ocr_text}")
    except Exception as e:
        parts.append(f"[OCR失败: {e}]")

    return "\n".join(parts) if parts else "[未识别到内容]"


def video_analyze(path):
    """Video scene analysis: extract key frames + classify via TIIA + aggregate results.
    Returns scene description like '在跳舞' or '骑行运动'."""
    import subprocess, tempfile
    tmpdir = tempfile.mkdtemp(prefix="video_frames_")

    # Extract 1 frame every 2 seconds with FFmpeg
    ffmpeg = os.path.expanduser(
        "~/AppData/Local/Microsoft/WinGet/Packages/"
        "Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/"
        "ffmpeg-8.1.1-full_build/bin/ffmpeg.exe"
    )
    if not os.path.exists(ffmpeg):
        ffmpeg = "ffmpeg"

    subprocess.run([ffmpeg, "-i", path, "-vf", "fps=1/2",
                    os.path.join(tmpdir, "f_%03d.jpg"), "-y"],
                   capture_output=True)

    frames = sorted(Path(tmpdir).glob("f_*.jpg"))
    if not frames:
        return "[视频分析: 无帧可提取]"

    # Analyze each frame via TIIA, aggregate results
    all_tags = {}
    frame_count = min(len(frames), 15)  # Max 15 frames (30 seconds)
    for f in frames[:frame_count]:
        try:
            tags_str = image_tag(str(f))
            if tags_str and "[未识别到标签]" not in tags_str:
                for tag_part in tags_str.split(", "):
                    name, conf = tag_part.rsplit("(", 1)
                    conf = int(conf.rstrip("%)"))
                    name = name.strip()
                    if name not in all_tags or all_tags[name] < conf:
                        all_tags[name] = conf
        except:
            pass

    # Cleanup
    import shutil
    shutil.rmtree(tmpdir, ignore_errors=True)

    # Sort by confidence, take top 15
    sorted_tags = sorted(all_tags.items(), key=lambda x: x[1], reverse=True)[:15]
    tag_str = ", ".join(f"{n}({c}%)" for n, c in sorted_tags) if sorted_tags else "[未识别到场景]"

    # Scene classification based on tag patterns
    scene_hints = []
    categories = {
        "舞台/演出/年会": ["舞台", "灯光", "演出", "表演", "歌手", "麦克风", "音乐会", "演唱会",
                       "卡拉ok", "ktv", "年會", "晚会", "颁奖", "典礼", "舞臺", "歌舞"],
        "运动/体育": ["运动", "跑步", "游泳", "健身", "运动员", "球场", "比赛", "篮球",
                     "足球", "乒乓球", "羽毛球", "拳击", "赛跑", "滑板", "滑雪", "冲浪"],
        "跳舞": ["舞蹈", "跳舞", "舞者", "芭蕾", "街舞", "现代舞", "民族舞", "舞厅", "disco"],
        "骑行/户外": ["自行车", "骑行", "摩托车", "骑行服", "头盔", "山地车", "公路车"],
        "广告/宣传": ["文字", "字体", "广告", "品牌", "文本", "商标", "海报", "横幅",
                     "宣传", "推广", "logo", "slogan"],
        "美食/烹饪": ["食物", "膳食", "菜肴", "厨房", "餐厅", "美食", "烹饪", "厨师",
                     "烧烤", "火锅", "甜点", "饮品"],
        "风景/旅游": ["风景", "山水", "海滩", "建筑", "塔", "自然", "日落", "日出",
                     "山脉", "湖泊", "森林", "花海"],
        "教学/会议": ["教室", "黑板", "屏幕", "讲座", "课堂", "老师", "学术", "会议",
                     "研讨会", "白板", "投影", "ppt"],
        "游戏/电竞": ["游戏", "电竞", "电脑", "主机", "手柄", "玩家", "屏幕", "键盘"],
        "宠物/动物": ["猫", "狗", "动物", "宠物", "鸟", "鱼", "兔子", "仓鼠"],
        "购物/开箱": ["商品", "包装", "开箱", "购物", "商场", "店铺", "展示", "试用"],
        "化妆/美妆": ["化妆", "口红", "眼影", "美容", "护肤", "粉底", "美甲", "发型"],
    }

    tags_lower = tag_str.lower()
    for category, keywords in categories.items():
        if any(k in tags_lower for k in keywords):
            scene_hints.append(category)

    # Always check if people present
    if any(k in tags_lower for k in ["人", "人物", "人群", "面部", "肖像"]):
        if not any("人物" in h for h in scene_hints):
            scene_hints.append("有人物出镜")

    hint_str = "；".join(scene_hints[:3]) if scene_hints else ""
    result = f"[视频场景标签] {tag_str}"
    if hint_str:
        result += f"\n[场景推断] {hint_str}"
    return result


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: cloud-vision.py <ocr|tag|describe|video> <filepath>")
        sys.exit(1)

    cmd = sys.argv[1]
    fpath = sys.argv[2]

    if not os.path.exists(fpath):
        print(f"[错误: 文件不存在: {fpath}]")
        sys.exit(1)

    try:
        if cmd == "ocr":
            print(ocr_general(fpath))
        elif cmd == "tag":
            print(image_tag(fpath))
        elif cmd == "describe":
            print(image_describe(fpath))
        elif cmd == "video":
            print(video_analyze(fpath))
    except TencentCloudSDKException as e:
        print(f"[API错误: {e}]")
    except Exception as e:
        print(f"[处理失败: {e}]")
