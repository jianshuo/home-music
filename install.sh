#!/bin/bash
# 在放音乐的那台 Mac 上运行：生成 launchd 配置并（重新）启动两个常驻服务
#   <前缀>.home-music         探测手机、回家放歌、超时停歌
#   <前缀>.home-music-server  给 iPhone 快捷指令用的 HTTP 接口（:8765）
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${LABEL_PREFIX:-com.$(whoami)}"
[ -f "${DIR}/config.sh" ] || { echo "先复制 config.example.sh 为 config.sh 并填好 PHONE_HOST"; exit 1; }
[ -s "${DIR}/.token" ] || { openssl rand -hex 12 > "${DIR}/.token"; chmod 600 "${DIR}/.token"; echo "已生成接口密钥 ${DIR}/.token"; }

install_agent() {   # $1=label  $2..=程序参数
  local label="$1"; shift
  local plist="${HOME}/Library/LaunchAgents/${label}.plist" args="" a
  for a in "$@"; do args="${args}<string>${a}</string>"; done
  cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array>${args}</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/${label#${PREFIX}.}.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/${label#${PREFIX}.}.log</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)" "${plist}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "${plist}"
}

install_agent "${PREFIX}.home-music" /bin/bash "${DIR}/home-music.sh" loop
install_agent "${PREFIX}.home-music-server" /usr/bin/python3 "${DIR}/server.py"
echo "已启动。日志：~/Library/Logs/home-music.log、home-music-server.log、home-music-presence.log"
echo "快捷指令接口：http://$(scutil --get LocalHostName).local:8765"
