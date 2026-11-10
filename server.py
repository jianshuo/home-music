#!/usr/bin/python3
# 给 iPhone 快捷指令用的小接口：GET /play /stop /volup /voldown /vol?v=N，都要带 ?k=TOKEN
import os, subprocess, http.server, urllib.parse
DIR = os.path.dirname(os.path.abspath(__file__))
TOKEN = open(os.path.join(DIR, ".token")).read().strip()
PORT = 8765

def run(cmd, timeout=45):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if urllib.parse.parse_qs(u.query).get("k", [""])[0] != TOKEN:
            return self.reply(403, "forbidden")
        if u.path == "/play":
            out = run(["/bin/bash", os.path.join(DIR, "home-music.sh"), "play"])
            if "已经在放" in out: msg = "已经在放了 🎵"
            elif "TIMEOUT" in out or "不响应" in out: msg = "pro 的「音乐」App 没响应，请稍后再试 😵"
            elif "没有" in out: msg = "pro 的「音乐」里还没有「回家」歌单 🤷"
            else: msg = "开始放音乐 🎵"
            self.reply(200, msg)
        elif u.path in ("/volup", "/voldown", "/vol"):
            out = run(["osascript", "-e", "output volume of (get volume settings)"], timeout=10)
            if not out.isdigit(): return self.reply(200, "pro 没响应，音量没改 😵")
            cur = int(out)
            if u.path == "/vol":
                new = int(urllib.parse.parse_qs(u.query).get("v", [cur])[0])
            else:
                new = cur + (10 if u.path == "/volup" else -10)
            new = max(0, min(100, new))
            run(["osascript", "-e", f"set volume output volume {new} without output muted"])
            self.reply(200, f"音量 {new}% 🔊")
        elif u.path == "/stop":
            run(["osascript", "-e", 'tell application "Music" to if it is running then stop'])
            self.reply(200, "音乐已停 ⏹")
        else:
            self.reply(404, "not found")
    def reply(self, code, msg):
        b = msg.encode()
        self.send_response(code); self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

http.server.ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
