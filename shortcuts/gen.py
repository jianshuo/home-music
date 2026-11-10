#!/usr/bin/env python3
# 生成 iPhone 快捷指令：HM_HOST=Pro.local python3 shortcuts/gen.py 名字 路径 [颜色] [图标号]
#   → shortcuts/名字.shortcut（已签名，含接口密钥，别公开）。路径：play / stop / volup / voldown
#   在任意登录了同一 iCloud 的 Mac 上运行，双击生成的文件导入，会同步到 iPhone
import plistlib, sys, uuid, os, subprocess
D = os.path.dirname(os.path.abspath(__file__))
T = open(os.path.join(D, "..", ".token")).read().strip()
HOST = os.environ.get("HM_HOST", "Pro.local")   # 放音乐那台 Mac 的 Bonjour 名
name, path = sys.argv[1], sys.argv[2]
color = int(sys.argv[3]) if len(sys.argv) > 3 else 4282601983
glyph = int(sys.argv[4]) if len(sys.argv) > 4 else 59446
u = str(uuid.uuid4()).upper()
wf = {
  "WFWorkflowClientVersion": "2605.0.5", "WFWorkflowMinimumClientVersion": 900,
  "WFWorkflowIcon": {"WFWorkflowIconStartColor": color, "WFWorkflowIconGlyphNumber": glyph},
  "WFWorkflowImportQuestions": [], "WFWorkflowInputContentItemClasses": [], "WFWorkflowOutputContentItemClasses": [],
  "WFWorkflowTypes": ["Watch"], "WFWorkflowHasShortcutInputVariables": False,
  "WFWorkflowActions": [
    {"WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
     "WFWorkflowActionParameters": {"UUID": u, "WFURL": f"http://{HOST}:8765/{path}?k={T}", "WFHTTPMethod": "GET"}},
    {"WFWorkflowActionIdentifier": "is.workflow.actions.notification",
     "WFWorkflowActionParameters": {"WFNotificationActionTitle": "家里的 pro",
       "WFNotificationActionBody": {"WFSerializationType": "WFTextTokenString", "Value": {"string": "￼",
         "attachmentsByRange": {"{0, 1}": {"OutputUUID": u, "Type": "ActionOutput", "OutputName": "URL 的内容"}}}}}},
  ]}
raw = os.path.join(D, f"{name}-unsigned.shortcut"); out = os.path.join(D, f"{name}.shortcut")
plistlib.dump(wf, open(raw, "wb"), fmt=plistlib.FMT_BINARY)
subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", raw, "--output", out], check=True, capture_output=True)
print(out)
