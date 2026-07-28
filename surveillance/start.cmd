@echo off
setlocal

rem mpv-advance V1 portable launcher. ASCII-only for Windows 7 cmd.exe.
set "HERE=%~dp0"
set "MPV_EXE=%HERE%runtime\mpv.exe"
if not defined MPV_ADVANCE_SMOKE set "MPV_ADVANCE_SMOKE=no"
set "MPV_EXTRA_ARGS="
if /i "%MPV_ADVANCE_SMOKE%"=="yes" set "MPV_EXTRA_ARGS=--vo=null --ao=null"

if exist "%MPV_EXE%" goto run
if not defined MPV goto find_path
if not exist "%MPV%" goto find_path
set "MPV_EXE=%MPV%"
goto run

:find_path
where mpv.exe >nul 2>&1
if errorlevel 1 goto find_com
set "MPV_EXE=mpv.exe"
goto run

:find_com
where mpv.com >nul 2>&1
if errorlevel 1 goto missing
set "MPV_EXE=mpv.com"
goto run

:missing
echo [ERROR] Bundled mpv.exe was not found.
echo Use a portable release package, or set MPV=C:\path\to\mpv.exe.
pause
exit /b 1

:run
if not exist "%HERE%samples\channel001.mp4" (
  echo [ERROR] Demo sample files are missing from "%HERE%samples".
  pause
  exit /b 2
)

echo Starting mpv-advance V1 in local single-window mode.
"%MPV_EXE%" --config-dir="%HERE%portable_config" "--script-opts=surveillance-api_enabled=no,surveillance-single_view=yes,surveillance-smoke_test=%MPV_ADVANCE_SMOKE%,surveillance-data_file=%HERE%data\cameras.json,surveillance-samples_dir=%HERE%samples" --idle=yes %MPV_EXTRA_ARGS%
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
