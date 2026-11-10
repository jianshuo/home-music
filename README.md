# home-music：回家自动放音乐

一台常年开着的 Mac 放在家里当音箱主机。它每 30 秒在局域网里找一次你的 iPhone：你离开够久再回来，就让「音乐」App 随机播一个 Apple Music 歌单；你出门后，过一段时间自动停。另外附带一个小 HTTP 接口，配合 iPhone 快捷指令一键放歌、停歌、调音量。

纯 bash + 系统自带的 python3，不依赖任何第三方包。

## 规则

| 场景 | 行为 |
|------|------|
| 回家 | 连续 `AWAY_MIN`（默认 30）分钟没见到手机算出门；之后再见到手机，就随机播歌单 `PLAYLIST`（默认「回家」），音量 `VOLUME` |
| 安静时段 | `QUIET_START`–`QUIET_END`（默认 23:00–07:00）不自动放 |
| 停歌 | 音乐一开始放（不管是谁开的）至少放 `HOLD_MIN`（默认 30）分钟；每见到一次手机就顺延到「现在 + HOLD_MIN」；超时都没见到手机才停 |
| 重启 | 服务启动时手机已在家，不触发放歌 |

## 怎么认出你的 iPhone

1. 用 Bonjour 主机名（`xxx.local`）解析出手机当前的 IP。不依赖 MAC，所以 iPhone 开了「私有 Wi‑Fi 地址」也照样认得出。
2. `ping`，或者连 iPhone 一直开着的 62078 端口（lockdownd），任一通就算在家。iPhone 熄屏时经常不回 ping，但 62078 端口比较稳。
3. 不通时间隔 5 秒再补测两次，过滤掉几秒的瞬断。
4. iPhone 熄屏时有时不回应 mDNS 查询，所以会记住上次认出的 IP，作为兜底。

为什么不用蓝牙：iPhone 的低功耗蓝牙广播地址会定期轮换，macOS 又不让程序读到对方的蓝牙地址，不配对很难认人；配对后定时呼叫也可以，但如果 Mac 正用蓝牙音箱放歌，轮询容易让音箱卡顿。

## 安装

```bash
git clone https://github.com/jianshuo/home-music.git ~/code/home-music
cd ~/code/home-music
cp config.example.sh config.sh     # 填 PHONE_HOST
./install.sh                       # 生成 launchd 配置并启动两个常驻服务，首次会生成接口密钥 .token
```

找 iPhone 的 Bonjour 名：`dns-sd -B _apple-mobdev2._tcp local`，或者知道手机 IP 时用 `dns-sd -Q <IP倒序>.in-addr.arpa PTR`。中文、阿拉伯文等设备名会被 iOS 音译成拉丁字母。

准备歌单：在「音乐」App 里登录有 Apple Music 订阅的账号，打开「同步资料库」，建一个叫「回家」的歌单。在 iPhone 上建也行，会同步过来。

第一次运行时，macOS 可能会问是否允许控制「音乐」App，点允许。

## iPhone 快捷指令

接口（`<主机>` 是那台 Mac 的 Bonjour 名，都要带 `?k=<.token 里的密钥>`）：

| 路径 | 作用 |
|------|------|
| `/play` | 随机播歌单（已经在放就不动） |
| `/stop` | 停 |
| `/volup` `/voldown` | 音量 ±10 |
| `/vol?v=50` | 音量设为 50 |

生成快捷指令：在登录了同一 iCloud 的 Mac 上运行

```bash
HM_HOST=Pro.local python3 shortcuts/gen.py 家里放音乐 play
HM_HOST=Pro.local python3 shortcuts/gen.py 家里停音乐 stop
HM_HOST=Pro.local python3 shortcuts/gen.py 家里音量加 volup
HM_HOST=Pro.local python3 shortcuts/gen.py 家里音量减 voldown
open shortcuts/家里放音乐.shortcut   # 依次导入，会通过 iCloud 同步到 iPhone
```

生成的 `.shortcut` 文件里带着密钥，已经在 `.gitignore` 里，别公开。接口只监听局域网，手机连着家里 Wi‑Fi 时才能用。

## 日志与排查

```bash
tail -f ~/Library/Logs/home-music.log            # 回家、停歌、启动
tail -f ~/Library/Logs/home-music-presence.log   # 手机掉线、恢复流水，诊断 Wi‑Fi 用
~/code/home-music/home-music.sh status           # 当前状态
~/code/home-music/home-music.sh play             # 手动放一次
```

踩过的坑：

- launchd 的默认 PATH 里没有 `/usr/sbin`，找不到 `arp`。脚本里自己补了。
- 「音乐」App 弹出对话框或者卡住时，AppleScript 会一直等下去。所有调用都加了 15 秒超时；放歌前发现它不响应，会自动重启它。
- 有的运营商路由器会代答 ARP，局域网里很多 IP 看到的都是路由器的 MAC，所以不能靠扫 MAC 认设备。
- iPhone 在家也可能频繁真掉 Wi‑Fi，所以出门判定和停歌都要留足余量，别设太短。

## License

MIT
