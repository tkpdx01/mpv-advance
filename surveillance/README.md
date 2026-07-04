# mpv-advance 监控播放器（NVR 演示）

把 mpv 变成一个增强版的多路视频监控播放器：单窗口多路分割网格、可搜索的
摄像头菜单、实时/回放切换、**按墙钟时间的时段回放**，以及常驻不退出的窗口。

纯用户脚本实现（`surveillance.lua`），不改动 mpv C 核心，Windows 友好。

## 目录结构

```
surveillance/
├── api/mock_camera_api.py       # 本地 mock 摄像头 API（Python 标准库，无依赖）
├── data/cameras.json            # 摄像头清单（API 不可用时的本地回退数据源）
├── launch.cmd                   # 一键启动（拉起 API + mpv）
├── portable_config/             # 便携配置目录（--config-dir 指向此处）
│   ├── mpv.conf                 # 常驻窗口 / 循环 / OSC 等
│   ├── input.conf               # 按键绑定
│   ├── menu.conf                # 右键菜单
│   ├── script-opts/surveillance.conf   # 脚本可配置项
│   └── scripts/surveillance.lua # 核心脚本
└── README.md
```

## 快速开始

```cmd
surveillance\launch.cmd
```

或手动分两步：

```bash
# 1) 启动 mock API（默认 127.0.0.1:8777）
python surveillance/api/mock_camera_api.py --port 8777

# 2) 用便携配置启动 mpv
mpv --config-dir=surveillance/portable_config
```

API 不可用时脚本自动回退读取 `data/cameras.json`，功能不中断（覆盖层与菜单
右上角会显示当前数据源为 `API` 还是 `本地`）。

## 按键

| 键 | 功能 |
|----|------|
| `c` | 打开摄像头列表（输入即模糊搜索）→ 赋给当前画格 |
| `\` / `MENU` | 监控主菜单 |
| `g` | 循环布局 1→4→9；`Ctrl+1/2/3` 直达单/四/九分割 |
| `TAB` / `1..9` | 选中画格 |
| `l` | 实时 / 回放切换 |
| `k` | **时段回放菜单**（预设时段 / 自定义时间 / 事件 / A-B 循环） |
| `K` | 回放微调：相对跳转 / 百分比定位 |
| `Ctrl+a` | 自动填充所有画格 |
| `Ctrl+r` | 刷新摄像头列表 |
| `DEL` / `Ctrl+DEL` | 清空当前画格 / 全部清空 |

## 时段回放

回放按**墙钟时间**组织。按 `k` 打开时段回放菜单：

- **预设时段**：最近 5/15/30 分钟、最近 1 小时、今天 00:00、昨天 00:00
- **自定义时间**：输入 `YYYY-MM-DD HH:MM`（或 `HH:MM` 表示今天）
- **按事件跳转**：从 API `/recordings` 拉取的事件列表（移动侦测 / 人形检测 /
  越界告警 / 车辆识别 / 逗留检测），选中即定位到该事件时刻
- **A-B 循环片段**：在当前位置设 A/B 点循环播放，便于反复查看某段
- **播放微调**：进入回放后用 `K` 做相对 ±10/60 秒或 25/50/75% 定位

进入时段回放会自动切到**单画面**——多路网格共用一条时间轴、无法逐路独立
seek，单画面才能精确定位。选择时段后，脚本向 API 查询
`/cameras/<id>/playback?start=<epoch>`，把墙钟时间确定性地映射到样本内的一个
可见位置（`start_percent`），文件加载完成后 seek 过去。超出录像范围的请求会被
就近 clamp 到可回放窗口并给出提示。

> 说明：样本片段只有数秒，无法真正承载数天录像。演示中用哈希把“时段”稳定地
> 映射到样本内位置，保证同一时段每次定位一致、不同时段位置不同，回放行为可见
> 且可复现。

## 常驻不退出

`mpv.conf` 通过三项叠加保证播放器常驻：

- `idle=yes` —— 无文件也保持进程与窗口存活
- `force-window=yes` —— 始终显示窗口
- `keep-open=yes` + `keep-open-pause=yes` —— 播放结束停在末帧并暂停，不退出

实时模式下脚本设 `loop-file=inf` 循环样本以模拟持续画面；回放模式下改为
`loop-file=no`，片段播完停在末帧等待下一步操作。

## mock API 端点

| 端点 | 说明 |
|------|------|
| `GET /cameras?q=<关键字>` | 摄像头列表，`q` 在名称/分组/位置/ID/标签上模糊匹配 |
| `GET /cameras/<id>` | 单路详情 |
| `GET /cameras/<id>/stream?mode=live\|playback&start=<秒>` | 取流地址 |
| `GET /cameras/<id>/recordings` | 可回放范围 + 事件列表 |
| `GET /cameras/<id>/playback?start=<epoch>&duration=<秒>` | 按墙钟时间回放定位 |

## 可配置项

见 `portable_config/script-opts/surveillance.conf`：API 地址、画布尺寸、网格
归一化帧率、默认布局、是否自动填充、请求超时、是否绘制覆盖层等。
