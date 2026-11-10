# 复制成 config.sh 再改。config.sh 不进 git。
# iPhone 的 Bonjour 主机名：在同一局域网的 Mac 上运行
#   dns-sd -B _apple-mobdev2._tcp local   或   dns-sd -Q <手机IP倒序>.in-addr.arpa PTR
# 找到形如 xxxx.local 的名字，填 .local 前面那段
PHONE_HOST="your-iphone"

# 以下可选，默认值见 home-music.sh
# PLAYLIST="回家"     # Music.app 里要随机播的歌单
# VOLUME=35           # 自动放歌时的系统音量
# HOLD_MIN=30         # 开始播放后至少放多久 / 见到手机后顺延多久（分钟）
# AWAY_MIN=30         # 离开多久才算出门（分钟）
# QUIET_START=23      # 安静时段（不自动放歌）
# QUIET_END=7
