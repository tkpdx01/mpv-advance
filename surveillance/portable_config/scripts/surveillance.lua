--[[
================================================================================
 surveillance.lua — mpv-advance 监控播放器核心脚本
================================================================================

 把 mpv 变成一个增强版的多路视频监控播放器（NVR 风格）：

   * 多路播放      —— 单窗口内 1 / 4 / 9 分割网格，基于 --lavfi-complex + xstack
   * 菜单唤起切换  —— 内置可搜索菜单（input.select，输入即模糊过滤）
   * 摄像头列表    —— 从本地 mock API 拉取（curl），失效时回退读 cameras.json
   * 实时 / 回放   —— 同一路可在 live 与 playback 之间切换，回放支持跳转
   * 画格覆盖层    —— 每个画格显示编号 / 名称 / 状态，高亮当前选中画格

 本脚本不修改 mpv C 核心，作为普通用户脚本加载即可，Windows 友好。

 关键绑定见 input.conf；可配置项见 script-opts/surveillance.conf。
================================================================================
]]

local utils = require "mp.utils"
local input = require "mp.input"
local msg   = require "mp.msg"

--------------------------------------------------------------------------------
-- 配置
--------------------------------------------------------------------------------

local opts = {
    api_base        = "http://127.0.0.1:8777", -- mock 摄像头 API 地址
    data_file       = "",                       -- cameras.json；空=自动定位到 ../data
    samples_dir     = "",                       -- 样本目录；空=自动定位到仓库 test/samples
    canvas_w        = 1280,                     -- 网格合成画布宽
    canvas_h        = 720,                      -- 网格合成画布高
    grid_fps        = 25,                       -- 网格各路归一化帧率
    default_layout  = 4,                        -- 启动布局：1 / 4 / 9
    autofill        = true,                     -- 启动时自动用前若干路填满网格
    request_timeout = 1.5,                      -- API 请求超时（秒）
    overlay         = true,                     -- 是否绘制画格覆盖层
}
require "mp.options".read_options(opts, "surveillance")

-- 解析相对默认路径（相对于 mpv 配置目录，即 portable_config/）
local config_dir = mp.command_native({"expand-path", "~~/"})
if opts.data_file == "" then
    opts.data_file = config_dir .. "/../data/cameras.json"
end
if opts.samples_dir == "" then
    -- portable_config/../../test/samples == <仓库根>/test/samples
    opts.samples_dir = config_dir .. "/../../test/samples"
end

local LAYOUTS = {
    [1] = { cols = 1, rows = 1, label = "单画面" },
    [4] = { cols = 2, rows = 2, label = "四分割" },
    [9] = { cols = 3, rows = 3, label = "九分割" },
}

--------------------------------------------------------------------------------
-- 运行状态
--------------------------------------------------------------------------------

local state = {
    layout   = LAYOUTS[opts.default_layout] and opts.default_layout or 4,
    slots    = {},        -- slots[i] = 摄像头对象 或 nil
    active   = 1,         -- 当前选中画格（用于赋值 / 单画面）
    mode     = "live",    -- "live" | "playback"
    cameras  = {},        -- 最近一次拉取的摄像头列表
    api_ok   = false,     -- 上次是否成功命中 API
}

local pending_lavfi = nil  -- 待 file-loaded 后应用的滤镜图
local pending_seek_percent = nil -- 待 file-loaded 后跳转的百分比位置（回放时段）
local apply_token   = 0

--------------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------------

local function ncells()
    local L = LAYOUTS[state.layout]
    return L.cols * L.rows
end

local function osd(text, dur)
    mp.osd_message(text, dur or 2)
end

--------------------------------------------------------------------------------
-- API 客户端：优先 HTTP（curl），失败回退本地 JSON
--------------------------------------------------------------------------------

local function http_get_json(path)
    local r = mp.command_native({
        name          = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = { "curl", "-s", "--max-time", tostring(opts.request_timeout),
                 opts.api_base .. path },
    })
    if r and r.status == 0 and r.stdout and r.stdout ~= "" then
        local data = utils.parse_json(r.stdout)
        if data then return data end
    end
    return nil
end

local function read_local_db()
    local path = mp.command_native({"expand-path", opts.data_file})
    local f = io.open(path, "r")
    if not f then
        msg.warn("无法打开本地摄像头数据: " .. path)
        return {}
    end
    local content = f:read("*a")
    f:close()
    local data = utils.parse_json(content)
    if not data or not data.cameras then
        msg.warn("cameras.json 解析失败: " .. path)
        return {}
    end
    return data.cameras
end

-- 拉取摄像头列表（可带搜索关键字，仅 API 生效；本地回退时在 Lua 侧过滤）
local function fetch_cameras()
    local data = http_get_json("/cameras")
    if data and data.cameras then
        state.api_ok = true
        return data.cameras
    end
    state.api_ok = false
    return read_local_db()
end

-- 解析某路摄像头在指定模式下的可播放地址
local function stream_source(cam, mode)
    if not cam then return nil end
    local data = http_get_json("/cameras/" .. cam.id .. "/stream?mode=" .. mode)
    if data and data.source then
        return data.source, data.start or 0
    end
    -- 本地回退：samples_dir + file
    local dir = mp.command_native({"expand-path", opts.samples_dir})
    return dir .. "/" .. (cam.file or ""), 0
end

-- 本地回退：无 API 时，把 epoch 确定性映射到 0..99 的样本内位置
local function local_percent_for(epoch)
    return math.floor(epoch) % 100
end

-- 按墙钟时间戳(epoch)取回放：返回 { source, start_percent, start_str, in_range }
local function playback_at(cam, epoch, duration)
    if not cam then return nil end
    local path = string.format("/cameras/%s/playback?start=%d", cam.id, math.floor(epoch))
    if duration then path = path .. "&duration=" .. math.floor(duration) end
    local data = http_get_json(path)
    if data and data.source then
        state.api_ok = true
        return {
            source        = data.source,
            start_percent = data.start_percent or local_percent_for(epoch),
            start_str     = data.start_str or os.date("%Y-%m-%d %H:%M:%S", epoch),
            in_range      = data.in_range ~= false,
        }
    end
    -- 本地回退
    state.api_ok = false
    local dir = mp.command_native({"expand-path", opts.samples_dir})
    return {
        source        = dir .. "/" .. (cam.file or ""),
        start_percent = local_percent_for(epoch),
        start_str     = os.date("%Y-%m-%d %H:%M:%S", epoch),
        in_range      = true,
    }
end

-- 拉取某路摄像头的可回放范围与事件列表
local function fetch_recordings(cam)
    if not cam then return nil end
    local data = http_get_json("/cameras/" .. cam.id .. "/recordings")
    if data and data.events then
        state.api_ok = true
        return data
    end
    -- 本地回退：合成一批事件，保证 UI 可用
    state.api_ok = false
    local now = os.time()
    local types = { "移动侦测", "人形检测", "越界告警", "车辆识别", "逗留检测" }
    local events = {}
    for i = 1, 6 do
        local t = now - i * 3600 - (i * 137 % 900)
        events[i] = {
            time = t,
            time_str = os.date("%Y-%m-%d %H:%M:%S", t),
            type = types[((i - 1) % #types) + 1],
        }
    end
    return {
        available = {
            start_str = os.date("%Y-%m-%d %H:%M:%S", now - 7 * 86400),
            end_str   = os.date("%Y-%m-%d %H:%M:%S", now),
        },
        events = events,
    }
end

--------------------------------------------------------------------------------
-- 画格覆盖层（ASS）
--------------------------------------------------------------------------------

local overlay = mp.create_osd_overlay("ass-events")

local STATUS_TEXT = {
    online    = { txt = "在线",   c = "&H4BC46B&" }, -- 绿
    recording = { txt = "录像中", c = "&H2F9BEB&" }, -- 橙
    offline   = { txt = "离线",   c = "&H4B4BEB&" }, -- 红
}

local function ass_escape(s)
    return tostring(s):gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}")
end

local function draw_overlay()
    if not opts.overlay then return end
    local L = LAYOUTS[state.layout]
    local dw = mp.get_property_number("osd-width", 0)
    local dh = mp.get_property_number("osd-height", 0)
    if dw == 0 or dh == 0 then
        dw, dh = opts.canvas_w, opts.canvas_h
    end

    local cw = dw / L.cols
    local ch = dh / L.rows
    local ev = {}

    -- 顶部状态条
    local mode_txt = state.mode == "live" and "● 实时 LIVE" or "▷ 回放 PLAYBACK"
    local api_txt  = state.api_ok and "API" or "本地"
    ev[#ev+1] = string.format(
        "{\\an7\\pos(%d,%d)\\fs20\\bord1.5\\3c&H000000&\\1c&HFFFFFF&}"
        .. "监控 · %s · %s · 数据源:%s · 画格 %d/%d",
        math.floor(cw * 0 + 10), 8, L.label, mode_txt, api_txt,
        state.active, ncells())

    for i = 1, ncells() do
        local col = (i - 1) % L.cols
        local row = math.floor((i - 1) / L.cols)
        local x = col * cw
        local y = row * ch
        local cam = state.slots[i]
        local is_active = (i == state.active)

        -- 选中画格高亮边框
        if is_active then
            ev[#ev+1] = string.format(
                "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1a&HFF&\\3c&H2F9BEB&\\bord4\\p1}"
                .. "m 0 0 l %d 0 l %d %d l 0 %d{\\p0}",
                math.floor(x + 2), math.floor(y + 2),
                math.floor(cw - 4), math.floor(cw - 4), math.floor(ch - 4),
                math.floor(ch - 4))
        end

        -- 画格标签
        local st = STATUS_TEXT[cam and cam.status] or { txt = "空", c = "&H888888&" }
        local title
        if cam then
            title = string.format("[%d] %s  {\\c%s}%s{\\c&HFFFFFF&}",
                is_active and i or i, ass_escape(cam.name), st.c, st.txt)
        else
            title = string.format("[%d] {\\c&H888888&}— 空画格 —{\\c&HFFFFFF&}", i)
        end
        ev[#ev+1] = string.format(
            "{\\an1\\pos(%d,%d)\\fs18\\bord1.5\\shad0\\3c&H000000&\\1c&HFFFFFF&}%s",
            math.floor(x + 10), math.floor(y + ch - 8), title)
    end

    overlay.data = table.concat(ev, "\n")
    overlay:update()
end

--------------------------------------------------------------------------------
-- 网格合成与播放
--------------------------------------------------------------------------------

local function set_loop_for_mode()
    if state.mode == "live" then
        mp.set_property("loop-file", "inf")
    else
        mp.set_property("loop-file", "no")
    end
end

-- 构建 lavfi-complex 滤镜图：把各路缩放/补边/归一化后 xstack 成网格
local function build_lavfi(filled_map)
    local L = LAYOUTS[state.layout]
    local cw = math.floor(opts.canvas_w / L.cols)
    local ch = math.floor(opts.canvas_h / L.rows)
    local parts = {}
    local pads  = {}
    local coords = {}
    local vidn = 0

    for i = 1, ncells() do
        local col = (i - 1) % L.cols
        local row = math.floor((i - 1) / L.cols)
        local pad = "c" .. (i - 1)
        if filled_map[i] then
            vidn = vidn + 1
            -- 缩放保持比例 + 补边到画格尺寸 + 归一化 fps/sar/像素格式
            parts[#parts+1] = string.format(
                "[vid%d]fps=%d,scale=%d:%d:force_original_aspect_ratio=decrease,"
                .. "pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=0x101418,setsar=1,format=yuv420p[%s]",
                vidn, opts.grid_fps, cw, ch, cw, ch, pad)
        else
            -- 空画格用深色填充
            parts[#parts+1] = string.format(
                "color=c=0x0A0D10:s=%dx%d:r=%d,format=yuv420p[%s]",
                cw, ch, opts.grid_fps, pad)
        end
        pads[#pads+1] = "[" .. pad .. "]"
        coords[#coords+1] = (col * cw) .. "_" .. (row * ch)
    end

    return table.concat(parts, ";") .. ";" .. table.concat(pads, "")
        .. "xstack=inputs=" .. ncells() .. ":layout=" .. table.concat(coords, "|")
        .. "[vo]"
end

-- 应用当前 state（布局/画格分配/模式）到 mpv 播放
local function apply()
    -- 收集已分配画格的取流地址（按画格顺序）
    local L = LAYOUTS[state.layout]
    local filled_order = {}     -- 顺序排列的 src（喂给 vid1..vidN）
    local filled_map   = {}     -- filled_map[cell] = true
    local first_src, first_start
    for i = 1, L.cols * L.rows do
        local cam = state.slots[i]
        if cam then
            local src, start = stream_source(cam, state.mode)
            if src then
                filled_map[i] = true
                filled_order[#filled_order+1] = { src = src, start = start }
                if not first_src then first_src, first_start = src, start end
            end
        end
    end

    set_loop_for_mode()

    if #filled_order == 0 then
        mp.set_property("lavfi-complex", "")
        mp.set_property_native("external-files", {})
        pending_lavfi = nil
        mp.commandv("stop")
        draw_overlay()
        osd("未分配任何摄像头（按 c 选择）")
        return
    end

    -- 单画面：普通播放，保留音频与流畅 seek
    if state.layout == 1 then
        local cam = state.slots[state.active] or state.slots[1]
        for i = 1, ncells() do if state.slots[i] then cam = state.slots[i]; break end end
        if state.slots[state.active] then cam = state.slots[state.active] end
        local src, start = stream_source(cam, state.mode)
        mp.set_property("lavfi-complex", "")
        mp.set_property_native("external-files", {})
        pending_lavfi = nil
        local flags = state.mode == "playback" and start and start > 0
            and ("start=" .. start) or ""
        mp.commandv("loadfile", src, "replace", "-1", flags)
        draw_overlay()
        return
    end

    -- 多画格：首路为主文件，其余作为 external-files，file-loaded 后套用 lavfi-complex
    local externals = {}
    for k = 2, #filled_order do externals[#externals+1] = filled_order[k].src end

    mp.set_property("lavfi-complex", "")            -- 先清空旧图，避免引用失效轨道
    mp.set_property_native("external-files", externals)

    pending_lavfi = build_lavfi(filled_map)
    apply_token = apply_token + 1

    local flags = ""
    if state.mode == "playback" and first_start and first_start > 0 then
        flags = "start=" .. first_start
    end
    mp.commandv("loadfile", first_src, "replace", "-1", flags)
    draw_overlay()
end

mp.register_event("file-loaded", function()
    if pending_lavfi then
        mp.set_property("lavfi-complex", pending_lavfi)
        pending_lavfi = nil
    end
    if pending_seek_percent then
        -- 时段回放：文件就绪后定位到该时段对应的样本位置
        mp.commandv("seek", pending_seek_percent, "absolute-percent")
        pending_seek_percent = nil
    end
    draw_overlay()
end)

--------------------------------------------------------------------------------
-- 摄像头选择菜单（可搜索）
--------------------------------------------------------------------------------

local function status_icon(s)
    return s == "online" and "●" or s == "recording" and "◉" or "○"
end

local function format_camera(cam)
    return string.format("%s [%s] %s — %s  ·  %s  (%s)",
        status_icon(cam.status), cam.group or "?", cam.name or "?",
        cam.location or "", cam.id or "", table.concat(cam.tags or {}, "/"))
end

-- 打开摄像头列表菜单，选中后赋给指定画格（默认当前画格）
local function open_camera_menu(target_slot)
    target_slot = target_slot or state.active
    state.cameras = fetch_cameras()
    if #state.cameras == 0 then
        osd("摄像头列表为空：检查 API 或 cameras.json")
        return
    end

    local items = {}
    for i, cam in ipairs(state.cameras) do
        items[i] = format_camera(cam)
    end

    input.select({
        prompt = string.format("为画格 [%d] 选择摄像头（输入可搜索，共 %d 路，数据源:%s）：",
                               target_slot, #state.cameras, state.api_ok and "API" or "本地"),
        items = items,
        submit = function (idx)
            local cam = state.cameras[idx]
            if not cam then return end
            state.slots[target_slot] = cam
            osd(string.format("画格 [%d] ← %s", target_slot, cam.name))
            apply()
        end,
    })
end

-- 一键填充：把在线摄像头依次填入所有画格
local function autofill_grid()
    state.cameras = fetch_cameras()
    if #state.cameras == 0 then return end
    -- 在线优先
    local ordered = {}
    for _, c in ipairs(state.cameras) do if c.status ~= "offline" then ordered[#ordered+1] = c end end
    for _, c in ipairs(state.cameras) do if c.status == "offline" then ordered[#ordered+1] = c end end
    for i = 1, ncells() do
        state.slots[i] = ordered[((i - 1) % #ordered) + 1]
    end
end

--------------------------------------------------------------------------------
-- 主菜单
--------------------------------------------------------------------------------

local set_layout, toggle_mode, open_seek_menu, open_playback_menu  -- 前置声明

--------------------------------------------------------------------------------
-- 时段回放：把当前画格切到单画面 + 指定墙钟时段
--------------------------------------------------------------------------------

-- 进入某路摄像头某个墙钟时段的回放（自动切单画面便于精确 seek）
local function enter_playback_at(cam, epoch, label, duration)
    cam = cam or state.slots[state.active]
    if not cam then
        osd("当前画格为空，请先选择摄像头（按 c）")
        return
    end
    local pb = playback_at(cam, epoch, duration)
    if not pb then
        osd("无法获取回放地址")
        return
    end

    -- 时段回放切到单画面：多路网格共用一条时间轴、无法逐路 seek
    state.mode = "playback"
    state.layout = 1
    state.slots[1] = cam
    state.active = 1

    set_loop_for_mode()
    mp.set_property("lavfi-complex", "")
    mp.set_property_native("external-files", {})
    pending_lavfi = nil
    pending_seek_percent = pb.start_percent  -- file-loaded 后跳转

    mp.commandv("loadfile", pb.source, "replace", "-1", "")

    local warn = pb.in_range and "" or "（超出录像范围，已就近定位）"
    osd(string.format("▷ 回放 %s\n%s  @ %s%s",
        cam.name or cam.id, label or "", pb.start_str, warn), 4)
    draw_overlay()
end

local function open_main_menu()
    local L = LAYOUTS[state.layout]
    local labels = {
        "① 选择摄像头 → 当前画格 [" .. state.active .. "]",
        "② 布局切换（当前：" .. L.label .. "）",
        "③ 实时 / 回放切换（当前：" .. (state.mode == "live" and "实时" or "回放") .. "）",
        "④ 时段回放（预设/自定义/事件/AB循环）",
        "⑤ 自动填充全部画格",
        "⑥ 清空当前画格 [" .. state.active .. "]",
        "⑦ 全部清空",
        "⑧ 刷新摄像头列表",
    }
    input.select({
        prompt = "监控主菜单（↑↓ 选择，回车确认）：",
        items = labels,
        submit = function (i)
            if i == 1 then open_camera_menu(state.active)
            elseif i == 2 then
                input.select({
                    prompt = "选择布局：",
                    items = { "单画面 (1)", "四分割 (2×2)", "九分割 (3×3)" },
                    submit = function (j) set_layout(({1,4,9})[j]) end,
                })
            elseif i == 3 then toggle_mode()
            elseif i == 4 then open_playback_menu()
            elseif i == 5 then autofill_grid(); apply(); osd("已自动填充")
            elseif i == 6 then state.slots[state.active] = nil; apply(); osd("已清空画格 [" .. state.active .. "]")
            elseif i == 7 then state.slots = {}; apply(); osd("已全部清空")
            elseif i == 8 then state.cameras = fetch_cameras(); osd("已刷新：" .. #state.cameras .. " 路（" .. (state.api_ok and "API" or "本地") .. "）")
            end
        end,
    })
end

--------------------------------------------------------------------------------
-- 布局 / 画格 / 模式 操作
--------------------------------------------------------------------------------

function set_layout(n)
    if not LAYOUTS[n] then return end
    state.layout = n
    if state.active > ncells() then state.active = 1 end
    if opts.autofill then
        -- 布局变化时，若有空缺则按已有分配补齐（保留已选，填充其余）
        local have = false
        for i = 1, ncells() do if state.slots[i] then have = true break end end
        if not have then autofill_grid() end
    end
    osd("布局：" .. LAYOUTS[n].label)
    apply()
end

local function cycle_layout()
    local order = { [1] = 4, [4] = 9, [9] = 1 }
    set_layout(order[state.layout] or 4)
end

local function set_active(n)
    if n < 1 or n > ncells() then
        osd("画格 " .. n .. " 不在当前布局范围")
        return
    end
    state.active = n
    osd("当前画格：[" .. n .. "]" .. (state.slots[n] and (" " .. state.slots[n].name) or " 空"))
    draw_overlay()
    -- 单画面下切换画格即切换显示
    if state.layout == 1 then apply() end
end

local function next_slot()
    state.active = (state.active % ncells()) + 1
    set_active(state.active)
end

function toggle_mode()
    state.mode = state.mode == "live" and "playback" or "live"
    osd("模式：" .. (state.mode == "live" and "实时 LIVE" or "回放 PLAYBACK"))
    apply()
end

-- 播放中的相对跳转 / 百分比定位（回放模式下微调用）
function open_seek_menu()
    if state.mode ~= "playback" then
        osd("请先切到回放模式（主菜单③ 或按 l）")
        return
    end
    input.select({
        prompt = "回放微调（seek）：",
        items = { "⏮ 回到开头", "⏪ -60 秒", "⏪ -10 秒", "⏩ +10 秒", "⏩ +60 秒",
                  "25% 位置", "50% 位置", "75% 位置" },
        submit = function (i)
            if i == 1 then mp.commandv("seek", 0, "absolute")
            elseif i == 2 then mp.commandv("seek", -60, "relative")
            elseif i == 3 then mp.commandv("seek", -10, "relative")
            elseif i == 4 then mp.commandv("seek", 10, "relative")
            elseif i == 5 then mp.commandv("seek", 60, "relative")
            elseif i == 6 then mp.commandv("seek", 25, "absolute-percent")
            elseif i == 7 then mp.commandv("seek", 50, "absolute-percent")
            elseif i == 8 then mp.commandv("seek", 75, "absolute-percent")
            end
        end,
    })
end

-- 解析 "YYYY-MM-DD HH:MM[:SS]" 或 "HH:MM" 为 epoch（后者按今天算）
local function parse_datetime(s)
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local Y, Mo, D, H, Mi, S = s:match("^(%d+)-(%d+)-(%d+)%s+(%d+):(%d+):?(%d*)$")
    if Y then
        return os.time({ year = tonumber(Y), month = tonumber(Mo), day = tonumber(D),
            hour = tonumber(H), min = tonumber(Mi), sec = tonumber(S) or 0 })
    end
    local h, m = s:match("^(%d+):(%d+)$")
    if h then
        local now = os.date("*t")
        now.hour, now.min, now.sec = tonumber(h), tonumber(m), 0
        return os.time(now)
    end
    return nil
end

-- 自定义时间输入
local function open_custom_time()
    local cam = state.slots[state.active]
    input.get({
        prompt = "输入回放时间 (YYYY-MM-DD HH:MM 或 HH:MM)：",
        default_text = os.date("%Y-%m-%d %H:%M"),
        submit = function (text)
            input.terminate()
            local epoch = parse_datetime(text)
            if not epoch then
                osd("时间格式无法识别：" .. tostring(text))
                return
            end
            enter_playback_at(cam, epoch, "自定义 " .. text)
        end,
    })
end

-- 事件列表跳转
local function open_event_menu()
    local cam = state.slots[state.active]
    if not cam then osd("当前画格为空，请先选择摄像头（按 c）"); return end
    local rec = fetch_recordings(cam)
    if not rec or not rec.events or #rec.events == 0 then
        osd("该摄像头暂无事件记录"); return
    end
    local items = {}
    for i, e in ipairs(rec.events) do
        items[i] = string.format("⚑ %s  ·  %s", e.time_str, e.type)
    end
    input.select({
        prompt = string.format("%s — 事件跳转（共 %d 条，数据源:%s）：",
            cam.name or cam.id, #rec.events, state.api_ok and "API" or "本地"),
        items = items,
        submit = function (idx)
            local e = rec.events[idx]
            if e then enter_playback_at(cam, e.time, e.type, nil) end
        end,
    })
end

-- A-B 循环片段控制
local function open_abloop_menu()
    input.select({
        prompt = "A-B 循环片段：",
        items = { "Ⓐ 设为循环起点 (A)", "Ⓑ 设为循环终点 (B)",
                  "✖ 清除 A-B 循环", "⟳ 从 A 点重播" },
        submit = function (i)
            if i == 1 then
                mp.set_property_number("ab-loop-a", mp.get_property_number("time-pos", 0))
                osd("已设 A 点：" .. string.format("%.1fs", mp.get_property_number("ab-loop-a", 0)))
            elseif i == 2 then
                mp.set_property_number("ab-loop-b", mp.get_property_number("time-pos", 0))
                osd("已设 B 点：" .. string.format("%.1fs", mp.get_property_number("ab-loop-b", 0)))
            elseif i == 3 then
                mp.set_property("ab-loop-a", "no"); mp.set_property("ab-loop-b", "no")
                osd("已清除 A-B 循环")
            elseif i == 4 then
                local a = mp.get_property_number("ab-loop-a")
                if a then mp.commandv("seek", a, "absolute"); osd("从 A 点重播") end
            end
        end,
    })
end

-- 时段回放主菜单：预设时段 / 自定义 / 事件 / A-B / 微调
function open_playback_menu()
    local cam = state.slots[state.active]
    local camname = cam and (cam.name or cam.id) or "（当前画格为空）"
    local now = os.time()
    local presets = {
        { "最近 5 分钟",  now - 300,   300 },
        { "最近 15 分钟", now - 900,   900 },
        { "最近 30 分钟", now - 1800,  1800 },
        { "最近 1 小时",  now - 3600,  3600 },
        { "今天 00:00",   parse_datetime(os.date("%Y-%m-%d") .. " 00:00"), nil },
        { "昨天 00:00",   now - 86400, nil },
    }
    local items = {}
    for i, p in ipairs(presets) do items[i] = "⏱ " .. p[1] end
    items[#items+1] = "🗓 自定义时间…"
    items[#items+1] = "⚑ 按事件跳转…"
    items[#items+1] = "🔁 A-B 循环片段…"
    items[#items+1] = "🎚 播放微调 (seek)…"
    items[#items+1] = "● 返回实时 LIVE"

    input.select({
        prompt = string.format("时段回放 — %s（画格 [%d]）：", camname, state.active),
        items = items,
        submit = function (i)
            local np = #presets
            if i <= np then
                enter_playback_at(cam, presets[i][2], presets[i][1], presets[i][3])
            elseif i == np + 1 then open_custom_time()
            elseif i == np + 2 then open_event_menu()
            elseif i == np + 3 then open_abloop_menu()
            elseif i == np + 4 then open_seek_menu()
            elseif i == np + 5 then
                if state.mode ~= "live" then toggle_mode() else osd("已是实时模式") end
            end
        end,
    })
end

--------------------------------------------------------------------------------
-- 键位绑定（脚本消息，可在 input.conf 中映射）
--------------------------------------------------------------------------------

mp.add_key_binding(nil, "menu",         open_main_menu)
mp.add_key_binding(nil, "cameras",      function () open_camera_menu(state.active) end)
mp.add_key_binding(nil, "layout-cycle", cycle_layout)
mp.add_key_binding(nil, "layout-1",     function () set_layout(1) end)
mp.add_key_binding(nil, "layout-4",     function () set_layout(4) end)
mp.add_key_binding(nil, "layout-9",     function () set_layout(9) end)
mp.add_key_binding(nil, "next-slot",    next_slot)
mp.add_key_binding(nil, "toggle-mode",  toggle_mode)
mp.add_key_binding(nil, "seek-menu",    open_seek_menu)
mp.add_key_binding(nil, "playback-menu", open_playback_menu)
mp.add_key_binding(nil, "clear-slot",   function () state.slots[state.active] = nil; apply(); osd("已清空 [" .. state.active .. "]") end)
mp.add_key_binding(nil, "clear-all",    function () state.slots = {}; apply(); osd("已全部清空") end)
mp.add_key_binding(nil, "refresh",      function () state.cameras = fetch_cameras(); osd("已刷新：" .. #state.cameras .. " 路") end)
mp.add_key_binding(nil, "autofill",     function () autofill_grid(); apply(); osd("已自动填充") end)
for n = 1, 9 do
    mp.add_key_binding(nil, "slot-" .. n, function () set_active(n) end)
end

-- 覆盖层随窗口尺寸变化重绘
mp.observe_property("osd-width",  "native", function () draw_overlay() end)
mp.observe_property("osd-height", "native", function () draw_overlay() end)

--------------------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------------------

local function init()
    state.cameras = fetch_cameras()
    msg.info(string.format("监控脚本就绪：%d 路摄像头（数据源:%s），布局:%s，模式:%s",
        #state.cameras, state.api_ok and "API" or "本地",
        LAYOUTS[state.layout].label, state.mode))
    if opts.autofill and #state.cameras > 0 then
        autofill_grid()
        apply()
    else
        draw_overlay()
    end
end

-- 等 vo 就绪后再初始化，保证覆盖层尺寸正确
if mp.get_property_native("vo-configured") then
    init()
else
    local function on_vo(name, value)
        if value then
            mp.unobserve_property(on_vo)
            init()
        end
    end
    mp.observe_property("vo-configured", "native", on_vo)
end
