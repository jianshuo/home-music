#!/bin/bash
# 回家放音乐：每 30 秒探一次 iPhone 是否在家里 Wi-Fi；离开够久后再出现就让 Music.app 随机播一个歌单，
# 开始播放后至少放 HOLD_MIN 分钟、每见到手机就顺延。由 install.sh 装成 launchd 常驻。
set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"   # launchd 默认 PATH 没有 /usr/sbin（arp 在那）

# ---- 配置（可在 config.sh 里覆盖） ----
PHONE_HOST=""                     # iPhone 的 Bonjour 主机名（.local 前那段），在 config.sh 里填；非拉丁字母的设备名会被 iOS 音译
INTERVAL=30                       # 探测间隔（秒）
AWAY_MIN=30                       # 连续多少分钟看不到手机才算出门（之后回来才放歌）；iPhone 常掉 Wi-Fi，别设太短
QUIET_START=23                    # 安静时段开始（小时，含）
QUIET_END=7                       # 安静时段结束（小时，不含）
VOLUME=35                         # 放歌时的系统音量 0-100
PLAYLIST="回家"                   # 只放 Apple Music（Music.app）里这个歌单，随机播；没有就不放
HOLD_MIN=30                       # 音乐一开始放至少放这么多分钟；每见到一次手机就顺延到「现在+HOLD_MIN」，超时没见到手机才停（不管谁开的）
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "${DIR}/config.sh" ] && . "${DIR}/config.sh"
[ -n "${PHONE_HOST}" ] || { echo "请先在 ${DIR}/config.sh 里设置 PHONE_HOST（参考 config.example.sh）" >&2; exit 1; }

STATE="${DIR}/state"              # 内容：last_seen_epoch last_ip status(home|away) started_by_us(0|1) last_mac misses play_since
log() { echo "$(date '+%F %T') $*"; }
plog() { echo "$(date '+%F %T') $*" >> "${HOME}/Library/Logs/home-music-presence.log"; }   # 手机掉线/恢复流水，诊断用

# Music.app 弹窗/卡死时 AppleScript 会无限等待，所有调用都加超时（默认 15 秒）
osa() { perl -e 'alarm shift; exec @ARGV' "${OSA_TIMEOUT:-15}" osascript "$@"; }

# 放歌前确认 Music.app 还响应；不响应就强制重启它
ensure_music() {
  osa -e 'tell application "Music" to get player state' >/dev/null 2>&1 && return 0
  log "⚠ Music.app 不响应，重启它"
  pkill -9 -x Music; sleep 2; open -a Music; sleep 8
  osa -e 'tell application "Music" to get player state' >/dev/null 2>&1
}

mac_of() { arp -an | grep "(${1})" | awk '{print $4}' | head -1; }

# 用 Bonjour 名字解析 IP（最多等 3 秒）
resolve_name() {
  local f="${DIR}/.resolve"
  dns-sd -G v4 "${PHONE_HOST}.local" > "${f}" 2>/dev/null & local p=$!
  local i; for i in 1 2 3 4 5 6; do sleep 0.5; grep -q " Add " "${f}" && break; done
  kill "${p}" 2>/dev/null; wait "${p}" 2>/dev/null
  awk '$2=="Add" {print $6; exit}' "${f}"
}

# ping 或 iPhone 常开的 62078 端口（lockdownd）任一通就算活着；熄屏时 iPhone 有时半分钟不回 ping
alive1() { ping -c2 -W1000 "$1" >/dev/null 2>&1 || nc -z -G2 "$1" 62078 >/dev/null 2>&1; }
# iPhone 常有几秒的瞬断：不通时隔 5 秒再补测两次，三次都不通才算没探到
alive() { alive1 "$1" && return 0; sleep 5; alive1 "$1" && return 0; sleep 5; alive1 "$1"; }
GW_MAC="$(arp -an | grep "($(route -n get default 2>/dev/null | awk '/gateway/{print $2}'))" | awk '{print $4}' | head -1)"

# 手机在吗？在就打印 "IP MAC"
# 先认名字；iPhone 熄屏时可能不回 mDNS，所以上次名字认出的 IP 只要还 ping 得通且 MAC 没变，也算在
probe() {
  local ip="$1" mac="$2" nip
  nip="$(resolve_name)"
  if [ -n "${nip}" ] && alive "${nip}"; then
    local m; m="$(mac_of "${nip}")"; [ "${m}" = "${GW_MAC}" ] && m=""
    echo "${nip} ${m:--}"; return 0
  fi
  # 路由器会代答部分 IP 的 ARP（显示成路由器 MAC），那种 MAC 不可信，不拿来比对
  [ -n "${mac}" ] && [ "${mac}" = "${GW_MAC}" ] && mac=""
  if [ -n "${ip}" ] && alive "${ip}" && { [ -z "${mac}" ] || [ "$(mac_of "${ip}")" = "${mac}" ] || [ "$(mac_of "${ip}")" = "${GW_MAC}" ]; }; then
    echo "${ip} ${mac}"; return 0
  fi
  return 1
}

in_quiet() {
  local h; h=$((10#$(date +%H)))
  if [ "${QUIET_START}" -gt "${QUIET_END}" ]; then
    [ "${h}" -ge "${QUIET_START}" ] || [ "${h}" -lt "${QUIET_END}" ]
  else
    [ "${h}" -ge "${QUIET_START}" ] && [ "${h}" -lt "${QUIET_END}" ]
  fi
}

music_state() { osa -e 'tell application "Music" to if it is running then get player state as string' 2>/dev/null; }

play_music() {
  ensure_music || { log "✗ Music.app 重启后仍不响应"; return 3; }
  if [ "$(music_state)" = "playing" ]; then log "已经在放了，不动"; return 1; fi
  local n
  n="$(osa -e "tell application \"Music\" to if exists playlist \"${PLAYLIST}\" then get count of tracks of playlist \"${PLAYLIST}\"" 2>/dev/null)"
  if [ -n "${n}" ] && [ "${n}" -gt 0 ] 2>/dev/null; then
    osa -e "set volume output volume ${VOLUME} without output muted"
    osa -e "tell application \"Music\"" -e "set shuffle enabled to true" -e "play playlist \"${PLAYLIST}\"" -e "end tell"
    log "▶ 播放歌单「${PLAYLIST}」(${n} 首)"
  else
    log "✗ Music.app 里没有「${PLAYLIST}」歌单或歌单是空的，不放"
    return 2
  fi
  return 0
}

stop_music() { osa -e 'tell application "Music" to if it is running then stop' 2>/dev/null; log "■ 停止音乐"; }

# ---- 单次检查 ----
check() {
  local now last_seen last_ip status ours last_mac misses play_since found ip ms
  now=$(date +%s)
  [ -f "${STATE}" ] && read -r last_seen last_ip status ours last_mac misses play_since < "${STATE}"
  last_seen=${last_seen:-${now}};   # 刚启动没状态时从现在起算，免得一启动就判出门
   last_ip=${last_ip:-}; status=${status:-unknown}; ours=${ours:-0}; last_mac=${last_mac:-}; misses=${misses:-0}; play_since=${play_since:-0}
  [ "${last_ip}" = "-" ] && last_ip=""; [ "${last_mac}" = "-" ] && last_mac=""

  if found="$(probe "${last_ip}" "${last_mac}")"; then
    ip="${found%% *}"; last_mac="${found#* }"; [ "${last_mac}" = "-" ] && last_mac=""
    if [ "${status}" = "away" ]; then
      log "🏠 手机回来了 (${ip})"
      if in_quiet; then log "安静时段，不放音乐"
      elif play_music; then ours=1
      fi
    elif [ "${status}" = "unknown" ]; then
      log "启动时手机已在家 (${ip})，不触发"
    fi
    if [ "${misses}" -gt 0 ]; then plog "✓ 恢复 (掉线约 $(( (now - last_seen) / 60 )) 分 $(( (now - last_seen) % 60 )) 秒，漏探 ${misses} 次)"; fi
    status=home; last_seen=${now}; last_ip=${ip}; misses=0
  else
    misses=$((misses + 1))
    [ "${misses}" -eq 1 ] && plog "✗ 掉线"
    if [ "${status}" != "away" ] && [ $((now - last_seen)) -ge $((AWAY_MIN * 60)) ]; then
      log "🚪 ${AWAY_MIN} 分钟没见到手机，判定出门"
      status=away; ours=0
    fi
  fi
  # 保底播放 + 见手机顺延：停止时刻 = max(开始播放, 最后见到手机) + HOLD_MIN
  ms="$(music_state)"
  if [ "${ms}" = "playing" ]; then
    [ "${play_since}" -eq 0 ] && { play_since=${now}; log "♪ 检测到开始播放，至少放 ${HOLD_MIN} 分钟"; }
    local base=${last_seen}; [ "${play_since}" -gt "${base}" ] && base=${play_since}
    if [ $((now - base)) -ge $((HOLD_MIN * 60)) ]; then
      log "${HOLD_MIN} 分钟没见到手机"; stop_music; play_since=0
    fi
  elif [ -n "${ms}" ]; then
    play_since=0      # 停了/暂停了（读不到状态时不动，防 Music 卡住误清零）
  fi
  echo "${last_seen} ${last_ip:--} ${status} ${ours} ${last_mac:--} ${misses} ${play_since}" > "${STATE}"
}

case "${1:-loop}" in
  once)  check ;;
  play)  play_music ;;
  status) cat "${STATE}"; echo; music_state ;;
  loop)  log "启动：手机 ${PHONE_HOST}.local，间隔 ${INTERVAL}s，出门判定 ${AWAY_MIN}min"
         while true; do check; sleep "${INTERVAL}"; done ;;
esac
