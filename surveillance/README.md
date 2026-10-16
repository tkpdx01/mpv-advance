# mpv-advance V1 视频播放器

V1 收敛为**单个窗口、一次播放一路视频**。它提供摄像头切换、实时/回放、按墙钟
时间定位、事件跳转和 A-B 循环；多窗口和多路同时播放留到后续版本。

播放器由普通 mpv Lua 脚本实现，不修改 mpv C 核心。标准安装程序包含固定的 Win7
兼容版 mpv、配置、摄像头数据和合成演示视频，用户不需要安装 Python、curl 或 mpv。

## 安装使用

在 `surveillance/package/dist/` 选择系统对应的安装程序：

- `mpv-advance-v1-win7-64bit-setup.exe`：Windows 7 SP1 / Win10 / Win11 64 位
- `mpv-advance-v1-win7-32bit-setup.exe`：Windows 7 SP1 32 位

双击安装程序完成安装，然后从开始菜单启动“视频播放器”，或直接双击已关联的
媒体文件。安装向导默认提供两组可取消的文件关联：

- 常见视频和音频：MP4、MKV、AVI、MOV、WebM、MP3、FLAC 等
- 监控录像和码流：DAV、264/H264、265/H265、HEVC、PS、TS、MTS、M2TS

Windows 10/11 可能仍要求用户在“默认应用”中确认选择；Windows 7 会直接使用安装
时选中的关联。

离线发布时，将 `surveillance/package/dist/index.html` 与两个安装程序放在同一目录，
即可作为内网静态下载页使用。页面不引用任何外部资源，会在浏览器本机判断 Windows
架构并推荐 64 位或 32 位安装程序；无法准确识别时仍可手动选择。

> 64 位包已在固定版 mpv 上通过自动烟雾测试。32 位构建会验证 PE 架构和文件完整性，
> 正式发布前仍应在真实 Win7 SP1 32 位机器上做一次验收。

## 源码目录调试

本机已有 mpv 时可以直接运行：

```cmd
surveillance\start.cmd
```

`start.cmd` 仅用于源码调试和便携包校验，不作为安装版的用户启动入口。源码启动器
优先使用 `surveillance/runtime/mpv.exe`，其次读取 `MPV` 环境变量或 PATH。

播放器在非全屏窗口底部常驻显示常用快捷键提示；进入全屏后会清空自定义覆盖层，
退出全屏时自动恢复。提示栏使用 mpv 的 ASS 覆盖层绘制，不依赖 Windows 标题栏；
如需关闭，可在 `portable_config/script-opts/surveillance.conf` 中设置
`shortcut_hints=no`。

## 按键

| 键 | 功能 |
|----|------|
| `c` | 打开摄像头列表并切换当前视频 |
| `\` / `MENU` | 打开监控主菜单 |
| `l` | 实时 / 回放切换 |
| `k` | 时段回放菜单：预设时间、自定义时间、事件、A-B 循环 |
| `K` | 回放微调：±10/60 秒或百分比定位 |
| `Ctrl+r` | 刷新摄像头数据 |
| `DEL` | 清空当前视频 |

Win7 固定版 mpv 没有新版 `mp.input`，项目内置兼容菜单：方向键选择、Enter 确认、
Esc 返回；搜索支持英文、数字和摄像头编号。

## 时段回放

演示视频只有 8 秒，因此本地模式会把墙钟时间稳定映射到样本内的位置。相同时间
每次定位一致，用于展示交互流程，不代表真实 NVR 已保存数天录像。接入真实后端时，
可将 `api_enabled` 改为 `yes`，并配置 `api_base`。

## 目录结构

```text
surveillance/
├── start.cmd                 # V1 本地便携启动器
├── samples/                  # 可随包分发的合成视频
├── data/cameras.json         # 本地摄像头清单
├── portable_config/          # mpv 配置、脚本和 Win7 兼容输入模块
├── api/mock_camera_api.py    # 可选 mock API，V1 启动不依赖它
└── package/
    ├── index.html            # 无外部依赖的离线下载落地页
    ├── build-portable.ps1    # x64/x86 便携包构建器
    ├── build-installers.ps1  # 标准 Windows 安装程序构建器
    ├── installer.iss         # 安装、卸载与文件关联配置
    └── dist/                 # HTML、安装程序与中间产物，Git 忽略
```

## 构建发布包

构建器固定下载 2023-10-15 的 mpv `v0.36.0-549-g78d43740`，这是引入 Win8+
系统 API 前的最后一批 Windows 构建。下载文件必须通过固定 SHA-256 校验。

```powershell
# 构建 64 位和 32 位标准安装程序；内部会先生成对应便携内容
.\surveillance\package\build-installers.ps1 -Arch all

# 当前主机无法运行旧 i686 二进制时，跳过 32 位运行烟雾测试
.\surveillance\package\build-installers.ps1 -Arch all -SkipX86SmokeTest
```

安装器使用 Inno Setup 6.4.3 编译；可通过 `-InnoSetupCompiler` 指定 `ISCC.exe`。
默认构建不会忽略测试失败；`-SkipX86SmokeTest` 只应用于明确安排了 Win7 32 位
实机验收的候选包。

## 可选 mock API

需要演示 HTTP 接口时可以手动运行：

```cmd
python surveillance\api\mock_camera_api.py --port 8777
```

然后把 `portable_config/script-opts/surveillance.conf` 中 `api_enabled` 改为 `yes`。
mock API 只使用 Python 标准库，但它不是 V1 便携包的运行依赖。
