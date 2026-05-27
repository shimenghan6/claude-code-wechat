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


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: cloud-vision.py <ocr|tag|describe> <filepath>")
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
    except TencentCloudSDKException as e:
        print(f"[API错误: {e}]")
    except Exception as e:
        print(f"[处理失败: {e}]")
