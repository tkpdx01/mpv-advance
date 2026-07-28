mpv-advance V1 便携版
====================

运行环境：Windows 7 SP1 / Windows 10 / Windows 11
运行方式：解压整个压缩包，双击 start.cmd。

本版本为单窗口单路播放：
- 启动后自动播放第一路演示视频
- 按 c 选择摄像头
- 按 l 切换实时/回放
- 按 k 打开时段回放菜单
- 按 \ 打开主菜单

播放器在非全屏窗口底部一直显示常用快捷键提示；进入全屏后隐藏全部自定义覆盖层。

无需安装 mpv、Python 或 curl，也不需要联网。不要只复制 start.cmd，必须保留
runtime、portable_config、data 和 samples 目录。

Windows 7 建议：
- 安装 SP1，并更新显卡驱动
- 若无法创建视频输出，尝试在 portable_config\mpv.conf 中加入 gpu-api=opengl
- 32 位系统请选择 win7-x86 包，64 位系统优先选择 win7-x64 包

win7-x86 候选包正式发放前，需要在真实 Windows 7 SP1 32 位机器上验收一次。
