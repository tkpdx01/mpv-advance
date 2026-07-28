-- Win7/mpv 0.36 compatibility input module for mpv-advance.
-- Implements the subset of mp.input used by surveillance.lua.

local input = {}
local state = {
    active = false,
    mode = nil,
    request = nil,
    bindings = {},
    filtered = {},
    selected = 1,
    text = "",
}

local function remove_bindings()
    for _, name in ipairs(state.bindings) do mp.remove_key_binding(name) end
    state.bindings = {}
end

local function close_input()
    remove_bindings()
    state.active = false
    state.mode = nil
    state.request = nil
    mp.osd_message("", 0)
end

local function bind(key, suffix, fn, repeatable)
    local name = "surveillance-compat-input-" .. suffix
    mp.add_forced_key_binding(key, name, fn, { repeatable = repeatable == true })
    state.bindings[#state.bindings + 1] = name
end

local function rebuild_filter()
    state.filtered = {}
    local needle = string.lower(state.text or "")
    for index, item in ipairs(state.request.items or {}) do
        local label = tostring(item)
        if needle == "" or string.find(string.lower(label), needle, 1, true) then
            state.filtered[#state.filtered + 1] = { index = index, label = label }
        end
    end
    if #state.filtered == 0 then
        state.selected = 0
    else
        state.selected = math.max(1, math.min(state.selected, #state.filtered))
    end
end

local function redraw()
    if not state.active or not state.request then return end
    local lines = { tostring(state.request.prompt or "请选择：") }
    if state.mode == "select" then
        lines[#lines + 1] = "搜索(英文/编号): " .. state.text .. "_"
        if #state.filtered == 0 then
            lines[#lines + 1] = "  （没有匹配项）"
        else
            local rows = 9
            local first = math.max(1, state.selected - math.floor(rows / 2))
            first = math.min(first, math.max(1, #state.filtered - rows + 1))
            local last = math.min(#state.filtered, first + rows - 1)
            for i = first, last do
                local mark = i == state.selected and "> " or "  "
                lines[#lines + 1] = mark .. state.filtered[i].label
            end
        end
        lines[#lines + 1] = "↑↓选择  Enter确认  Esc返回  Backspace删除搜索"
    else
        lines[#lines + 1] = "> " .. state.text .. "_"
        lines[#lines + 1] = "Enter确认  Esc返回  Backspace删除  Ctrl+A/Del清空"
    end
    mp.osd_message(table.concat(lines, "\n"), 3600)
end

local function append_text(ch)
    state.text = state.text .. ch
    if state.mode == "select" then state.selected = 1; rebuild_filter() end
    redraw()
end

local function backspace()
    state.text = state.text:sub(1, math.max(0, #state.text - 1))
    if state.mode == "select" then state.selected = 1; rebuild_filter() end
    redraw()
end

local function clear_text(select_mode)
    state.text = ""
    if select_mode then rebuild_filter() end
    redraw()
end

local function install_text_keys(select_mode)
    for code = string.byte("0"), string.byte("9") do
        local ch = string.char(code)
        bind(ch, "char-" .. code, function () append_text(ch) end, true)
    end
    if select_mode then
        for code = string.byte("a"), string.byte("z") do
            local lower, upper = string.char(code), string.upper(string.char(code))
            bind(lower, "char-" .. code, function () append_text(lower) end, true)
            bind(upper, "char-upper-" .. code, function () append_text(upper) end, true)
        end
        bind("_", "char-underscore", function () append_text("_") end, true)
    end
    bind("-", "char-dash", function () append_text("-") end, true)
    bind(":", "char-colon", function () append_text(":") end, true)
    bind("SPACE", "char-space", function () append_text(" ") end, true)
    bind("BS", "backspace", backspace, true)
    bind("DEL", "clear", function () clear_text(select_mode) end)
    bind("Ctrl+a", "clear-all", function () clear_text(select_mode) end)
    bind("ESC", "cancel", close_input)
end

function input.select(t)
    close_input()
    state.active, state.mode, state.request = true, "select", t or {}
    state.text, state.selected = "", 1
    rebuild_filter()
    install_text_keys(true)
    bind("UP", "up", function ()
        if #state.filtered > 0 then
            state.selected = state.selected <= 1 and #state.filtered or state.selected - 1
            redraw()
        end
    end, true)
    bind("DOWN", "down", function ()
        if #state.filtered > 0 then
            state.selected = state.selected >= #state.filtered and 1 or state.selected + 1
            redraw()
        end
    end, true)
    bind("PGUP", "page-up", function () state.selected = math.max(1, state.selected - 8); redraw() end, true)
    bind("PGDWN", "page-down", function () state.selected = math.min(#state.filtered, state.selected + 8); redraw() end, true)
    bind("HOME", "home", function () state.selected = #state.filtered > 0 and 1 or 0; redraw() end)
    bind("END", "end", function () state.selected = #state.filtered; redraw() end)
    bind("ENTER", "submit", function ()
        local selected = state.filtered[state.selected]
        local submit = state.request and state.request.submit
        close_input()
        if selected and submit then submit(selected.index) end
    end)
    redraw()
end

function input.get(t)
    close_input()
    state.active, state.mode, state.request = true, "get", t or {}
    state.text = tostring(state.request.default_text or "")
    install_text_keys(false)
    bind("ENTER", "submit", function ()
        local text = state.text
        local submit = state.request and state.request.submit
        close_input()
        if submit then submit(text) end
    end)
    redraw()
end

input.terminate = close_input
return input
