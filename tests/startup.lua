-- Mock KOReader boundaries while loading the shipped plugin and study widget.
local Container = {}
function Container:extend(fields)
    fields.__index = fields
    return setmetatable(fields, { __index = self })
end
function Container:new(fields)
    fields.ges_events = {}
    setmetatable(fields, self)
    fields:init()
    return fields
end
function Container:onKeyPress(key)
    for name, sequences in pairs(self.key_events) do
        for _, sequence in ipairs(sequences) do
            for _, code in ipairs(type(sequence[1]) == "table" and sequence[1] or sequence) do
                if key == code then return self["on" .. name](self) end
            end
        end
    end
end

local Screen = {
    getWidth = function() return 1264 end, getHeight = function() return 1680 end,
    isColorEnabled = function() return true end,
    scaleBySize = function(_, px) return math.floor(px * 2.1) end,
}
local bb = { paintRect = function() end, paintBorder = function() end }
local dots = {}
function bb:paintCircle(x, y) dots[x .. "," .. y] = true end
local painted = 0
function bb:paintRectRGB32() painted = painted + 1 end
local ui = {}
function ui:show(widget) self.top = widget end
function ui:close(widget)
    assert(self.top == widget)
    widget:onFlushSettings()
    widget:onCloseWidget()
    self.top = nil
end
function ui:setDirty(widget, mode, region)
    self.refresh = { widget, mode, region }
end

local function mkWidget(class, data)
    data = data or {}
    return setmetatable(data, { __index = class })
end
local image = {
    new = mkWidget, getSize = function(self) return { w = self.width } end,
    paintTo = function() end, free = function() end,
}
local labels = {}
local text = {
    new = mkWidget, getSize = function() return { w = 10, h = 10 } end,
    paintTo = function(self) labels[self.text] = true end, free = function() end,
}
local modules = {
    datastorage = { getSettingsDir = function() return test_dir end },
    device = { screen = Screen, input = { group = {
        PgBack = { "LPgBack", "RPgBack" }, PgFwd = { "LPgFwd", "RPgFwd" }, Back = { "Back" },
    } } },
    ["ffi/blitbuffer"] = { ColorRGB32 = function(...) return {...} end },
    gettext = function(s) return s end,
    ["ui/font"] = { getFace = function() end },
    ["ui/gesturerange"] = { new = mkWidget },
    ["ui/uimanager"] = ui,
    ["ui/widget/container/inputcontainer"] = Container,
    ["ui/widget/imagewidget"] = image,
    ["ui/widget/infomessage"] = { new = mkWidget },
    ["ui/widget/textwidget"] = text,
}
for name, module in pairs(modules) do
    package.loaded[name] = module
end

assert(require("_meta").fullname == "Pocket Chess Studies")
local plugin
local Plugin = require("main")
assert(not Plugin.is_doc_only)
plugin = Plugin:new{
    ui = { menu = { registerToMainMenu = function(_, item) plugin = item end } },
    path = plugin_dir,
}
local items = {}
plugin:addToMainMenu(items)
assert(items.pocketchess.sorting_hint == "more_tools")
items.pocketchess.callback()
local study = assert(plugin.study)
assert(ui.top == study)
items.pocketchess.callback()
assert(ui.top == study)
study:paintTo(bb, 0, 0)
assert(painted == 64 and labels["White to move"] and study.cell >= 130)
assert(study:square(1, 1) == "a8")
assert(study.controls.y + study.controls.h * 2 <= 1680)
local function tapButton(index)
    local button = study.buttons[index][1]
    study:onTap(nil, { pos = { x = button.x + 2, y = button.y + 2 } })
end

assert(labels.Hint and labels.Refresh and not labels.Reveal)
tapButton(1)
assert(study.hinted == "e7" and study.selected == nil)
study:paintTo(bb, 0, 0)
assert(labels.Reveal and not next(dots))

local function tapSquare(square)
    for row = 1, 8 do
        for col = 1, 8 do
            if study:square(col, row) == square then
                study:onTap(nil, { pos = {
                    x = study.board.x + (col - 0.5) * study.cell,
                    y = study.board.y + (row - 0.5) * study.cell,
                } })
                return
            end
        end
    end
    error("Square not found: " .. square)
end

tapSquare("e7")
study:paintTo(bb, 0, 0)
local board, cell = study.board, study.cell
local function hasDot(file, rank, offset)
    offset = offset or math.floor(cell / 2)
    return dots[(board.x + (file - 1) * cell + offset) .. "," ..
        (board.y + (8 - rank) * cell + offset)]
end
assert(hasDot(5, 8) and hasDot(7, 7, 2 * math.floor(cell / 14)))
assert(not hasDot(5, 6) and study.hint_used)
tapButton(3)
assert(ui.refresh[1] == study and ui.refresh[2] == "full" and ui.refresh[3] == nil)
assert(study.selected == "e7" and study.hint_used and study.session.stage == 1)
tapSquare("e8")
assert(study.session.solved and not study.hint_used)
assert(study:onKeyPress("RPgFwd") and study.session.index == 2)
assert(study:onKeyPress("RPgBack") and study.session.index == 1)
assert(study:onKeyPress("Back") and not ui.top and not plugin.study)

items.pocketchess.callback()
study = assert(plugin.study)
assert(study.session.solved)
study:onNext()
study:paintTo(bb, 0, 0)
tapButton(1)
tapSquare("e2")
tapSquare("e3")
assert(study.hint_used and not study.session.solved)
study:paintTo(bb, 0, 0)
tapButton(1)
assert(study.session.revealed and not study.session.solved and not study.hint_used)
assert(ui.top.text:find("Re8#", 1, true))
ui.top = study
study:onNext()
study:paintTo(bb, 0, 0)
assert(labels["Black to move"] and study:square(1, 1) == "h1")

while study.session.puzzle.id ~= "3gFmO" do
    assert(study.session.index < #study.session.puzzles)
    study:onNext()
end
study:paintTo(bb, 0, 0)
tapSquare("e7")
tapSquare("e8")
assert(study.promotion and study.session.stage == 1)
study:paintTo(bb, 0, 0)
assert(labels.Queen and labels.Rook and labels.Bishop and labels.Knight)
local knight = study.buttons[4][1]
study:onTap(nil, { pos = { x = knight.x + 2, y = knight.y + 2 } })
assert(not study.promotion and study.session.stage == 2)
Screen.getWidth, Screen.getHeight = Screen.getHeight, Screen.getWidth
study:paintTo(bb, 0, 0)
assert(study.landscape and study.controls.y + study.controls.h * 2 <= 1264)
plugin:onCloseWidget()
assert(not ui.top and not plugin.study)
