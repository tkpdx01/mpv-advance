@echo off
rem ============================================================
rem  mpv-advance 监控播放器 — Windows 一键启动器
rem ------------------------------------------------------------
rem  流程：
rem    1) 定位 mpv（MPV 环境变量 > PATH > 常见路径）
rem    2) 检查 Python（缺失也能跑，脚本自动回退 cameras.json）
rem    3) 后台启动本地 mock 摄像头 API
rem    4) 用 portable_config 启动 mpv（监控模式，常驻窗口）
rem    5) mpv 退出后自动关闭后台 API
rem
rem  如 mpv 不在 PATH，可先设置：  set MPV=C:\path\to\mpv.exe
rem  端口默认 8777，可先设置：      set PORT=8777
rem ============================================================
setlocal enabledelayedexpansion
set "HERE=%~dp0"
if "%PORT%"=="" set "PORT=8777"

rem ---------- 1) 定位 mpv ----------
if not "%MPV%"=="" goto :have_mpv
where mpv.com >nul 2>&1 && (set "MPV=mpv.com" & goto :have_mpv)
where mpv.exe >nul 2>&1 && (set "MPV=mpv.exe" & goto :have_mpv)
rem 常见本地构建路径（按需补充）
for %%P in (
  "%HERE%..\..\vvv\night_scan\mpv\mpv.com"
  "%HERE%mpv\mpv.exe"
  "%ProgramFiles%\mpv\mpv.exe"
) do if exist "%%~P" (set "MPV=%%~P" & goto :have_mpv)

echo [错误] 未找到 mpv。请把 mpv 加入 PATH，或运行前设置：
echo        set MPV=C:\path\to\mpv.exe
echo.
pause
exit /b 1

:have_mpv
echo [信息] 使用 mpv: %MPV%

rem ---------- 2) 检查 Python ----------
set "PY="
where python >nul 2>&1 && set "PY=python"
if "%PY%"=="" where py >nul 2>&1 && set "PY=py"
if "%PY%"=="" (
  echo [提示] 未检测到 Python，跳过 mock API；脚本将回退读取 data\cameras.json。
  goto :run_mpv
)

rem ---------- 3) 后台启动 mock API ----------
echo [信息] 启动 mock 摄像头 API 于 127.0.0.1:%PORT% ...
start "mpv-advance mock API" /min %PY% "%HERE%api\mock_camera_api.py" --port %PORT%
rem 给服务一点启动时间
timeout /t 2 /nobreak >nul

:run_mpv
rem ---------- 4) 启动 mpv（监控模式） ----------
echo [信息] 启动监控播放器（关闭窗口即退出）...
"%MPV%" --config-dir="%HERE%portable_config" --script-opts=surveillance-api_base=http://127.0.0.1:%PORT% --idle=yes

rem ---------- 5) 退出清理：关闭后台 API ----------
if not "%PY%"=="" (
  echo [信息] 关闭 mock API ...
  taskkill /FI "WINDOWTITLE eq mpv-advance mock API*" /F >nul 2>&1
)
echo [信息] 已退出。
endlocal
