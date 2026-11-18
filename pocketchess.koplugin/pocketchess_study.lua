local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Progress = require("pocketchess_progress")
local _ = require("gettext")

local Screen = Device.screen
local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local light = Blitbuffer.ColorRGB32(239, 211, 173, 255)
local dark = Blitbuffer.ColorRGB32(157, 103, 67, 255)
local promotion_names = { q = _("Queen"), r = _("Rook"), b = _("Bishop"), n = _("Knight") }
local edge_swipes = {
    "one_finger_swipe_left_edge_up",
    "one_finger_swipe_left_edge_down",
    "one_finger_swipe_right_edge_up",
    "one_finger_swipe_right_edge_down",
}
local frontlight_events = {
    onIncreaseFlIntensity = true, onDecreaseFlIntensity = true,
    onIncreaseFlWarmth = true, onDecreaseFlWarmth = true,
    onSetFlIntensity = true, onSetFlWarmth = true,
    onToggleFrontlight = true, onShowFlDialog = true,
}

local Study = InputContainer:extend{
    modal = true,
    covers_fullscreen = true,
    stop_events_propagation = true,
}

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function contains(r, point)
    return point.x >= r.x and point.x < r.x + r.w
        and point.y >= r.y and point.y < r.y + r.h
end

local function fill(bb, r, color)
    bb:paintRect(r.x, r.y, r.w, r.h, color)
end

local function text(bb, r, label, size, color, bold)
    local widget = TextWidget:new{
        text = label, face = Font:getFace("cfont", size),
        bold = bold, fgcolor = color or BLACK, padding = 0, max_width = r.w,
    }
    local dim = widget:getSize()
    widget:paintTo(bb, r.x + math.floor((r.w - dim.w) / 2),
        r.y + math.floor((r.h - dim.h) / 2))
    widget:free()
end

function Study:init()
    self:onPhysicalKeyboardConnected()
    self.ges_events.Tap = { GestureRange:new{ ges = "tap" } }
    self.images = {}
    -- Reuse KOReader's registered zones and their current Gesture Manager actions.
    local zones = {}
    for _, id in ipairs(edge_swipes) do
        local zone = self.host._zones and self.host._zones[id]
        if zone then
            zones[#zones + 1] = {
                id = id, ges = zone.def.ges, screen_zone = zone.def.screen_zone,
                handler = zone.handler,
            }
        end
    end
    if #zones > 0 then self:registerTouchZones(zones) end
end

function Study:onPhysicalKeyboardConnected()
    local keys = Device.input.group
    self.key_events = {
        Close = { { keys.Back } },
        Previous = { { keys.PgBack }, { "Left" } },
        Next = { { keys.PgFwd }, { "Right" } },
    }
end

function Study:freePieces()
    for _, image in pairs(self.images) do image:free() end
    self.images = {}
end

function Study:layout(w, h)
    if self.width == w and self.height == h then return end
    self.width, self.height = w, h
    self:freePieces()
    if self.touch_zone_dg then self:updateTouchZonesOnScreenResize{ w = w, h = h } end

    local margin = Screen:scaleBySize(12)
    local line = Screen:scaleBySize(29)
    local button = Screen:scaleBySize(48)
    local gutter = Screen:scaleBySize(15)
    self.landscape = w > h
    local max_board
    if self.landscape then
        max_board = math.min(h - line - gutter - 2 * margin, math.floor(w * 0.58) - gutter)
    else
        max_board = math.min(w - 2 * margin - gutter,
            h - 4 * line - 2 * button - gutter - 5 * margin)
    end
    self.cell = math.floor(max_board / 8)
    local side = self.cell * 8
    local board_x = self.landscape and (margin + gutter) or math.floor((w - side + gutter) / 2)
    local board_y = self.landscape and math.floor((h - side - gutter) / 2) or line * 2 + margin
    self.board = rect(board_x, board_y, side, side)
    self.gutter = gutter

    local panel_x = self.landscape and (board_x + side + margin) or margin
    local panel_w = w - panel_x - margin
    local panel_y = self.landscape and math.max(margin, math.floor((h - 4 * line - 2 * button) / 2)) or margin
    self.title = rect(panel_x, panel_y, panel_w, line)
    self.turn = rect(panel_x, panel_y + line, panel_w, line)
    local controls_y = self.landscape and (panel_y + 2 * line) or (board_y + side + gutter + margin)
    self.counter = rect(panel_x, controls_y, panel_w, line)
    self.status = rect(panel_x, controls_y + line, panel_w, line)
    self.controls = rect(panel_x, controls_y + 2 * line, panel_w, button)
end

function Study:square(column, row)
    if self.session.puzzle.steps[1].fen:match(" b ") then
        return string.char(105 - column) .. row
    end
    return string.char(96 + column) .. (9 - row)
end

function Study:pieceImage(piece)
    if not self.images[piece] then
        local color = piece == piece:upper() and "w" or "b"
        local side = math.floor(self.cell * 0.94)
        self.images[piece] = ImageWidget:new{
            file = self.asset_path .. color .. piece:upper() .. ".svg",
            width = side, height = side, alpha = true,
        }
    end
    return self.images[piece]
end

function Study:paintBoard(bb)
    local board, cell, gutter = self.board, self.cell, self.gutter
    local use_color = Screen:isColorEnabled()
    local destinations = self.session:legalDestinations(self.selected)
    local dot_radius = math.max(2, math.floor(cell / 14))
    for row = 1, 8 do
        for col = 1, 8 do
            local square = self:square(col, row)
            local x, y = board.x + (col - 1) * cell, board.y + (row - 1) * cell
            local color = (row + col) % 2 == 0 and light or dark
            if use_color then
                bb:paintRectRGB32(x, y, cell, cell, Screen.night_mode and color:invert() or color)
            else
                bb:paintRect(x, y, cell, cell, color:getColor8())
            end
            local piece = self.session.pieces[square]
            if piece then
                local icon = self:pieceImage(piece)
                local inset = math.floor((cell - icon:getSize().w) / 2)
                icon:paintTo(bb, x + inset, y + inset)
            end
            if destinations[square] then
                local offset = piece and 2 * dot_radius or math.floor(cell / 2)
                bb:paintCircle(x + offset, y + offset, dot_radius, WHITE)
                bb:paintCircle(x + offset, y + offset, math.max(1, dot_radius - 2), BLACK)
            end
            if square == self.selected or square == self.hinted then
                local t = math.max(2, math.floor(cell / 18))
                bb:paintBorder(x + 1, y + 1, cell - 2, cell - 2, t * 2, WHITE)
                bb:paintBorder(x + 1, y + 1, cell - 2, cell - 2, t, BLACK)
            end
            if col == 1 then
                text(bb, rect(x - gutter, y, gutter, cell), square:sub(2), 13)
            end
            if row == 8 then
                text(bb, rect(x, y + cell, cell, gutter), square:sub(1, 1), 13)
            end
        end
    end
end

function Study:buttonRow(bb, names, y)
    local r = self.controls
    local gap = Screen:scaleBySize(4)
    local width = math.floor((r.w - (#names - 1) * gap) / #names)
    for index, item in ipairs(names) do
        local bounds = rect(r.x + (index - 1) * (width + gap), y, width, r.h - gap)
        local ink = item.enabled == false and Blitbuffer.COLOR_DARK_GRAY or BLACK
        bb:paintBorder(bounds.x, bounds.y, bounds.w, bounds.h, 2, ink)
        text(bb, bounds, item[1], #names == 4 and 16 or 19, ink, true)
        if item.enabled ~= false then self.buttons[#self.buttons + 1] = { bounds, item[2] } end
    end
end

function Study:paintTo(bb, x, y)
    self:layout(Screen:getWidth(), Screen:getHeight())
    fill(bb, rect(x, y, self.width, self.height), WHITE)
    self:paintBoard(bb)

    local s = self.session
    local turn
    if s.step.move then
        turn = s.side == "w" and _("White to move") or _("Black to move")
    else
        turn = s.revealed and _("Solution revealed") or _("Puzzle solved")
    end
    text(bb, self.title, _("Pocket Chess Studies"), 25, BLACK, true)
    text(bb, self.turn, turn, 22, BLACK, true)
    text(bb, self.counter, string.format(_("Puzzle %d of %d  ·  Rating %d%s"),
        s.index, #s.collection, s.puzzle.rating, s.solved and _("  ·  Solved") or ""), 16)
    local status = self.save_failed and _("Could not save progress.")
        or self.message or _("Tap a piece, then its destination.")
    text(bb, self.status, status, 16)

    self.buttons = {}
    local first_y = self.controls.y
    local second_y = first_y + self.controls.h
    if self.promotion then
        local choices = {}
        for _, piece in ipairs(self.promotion.choices) do
            choices[#choices + 1] = { promotion_names[piece], function() self:promote(piece) end }
        end
        self:buttonRow(bb, choices, first_y)
        self:buttonRow(bb, { { _("Cancel"), function() self:cancelPromotion() end } }, second_y)
        return
    end
    self:buttonRow(bb, {
        { self.hint_used and _("Reveal") or _("Hint"),
            function() self:onHintOrReveal() end, enabled = s.step.move ~= nil },
        { _("Retry"), function() self:onRetry() end },
        { _("Refresh"), function() UIManager:setDirty(self, "full") end },
    }, first_y)
    self:buttonRow(bb, {
        { _("Previous"), function() self:onPrevious() end, enabled = s.index > 1 },
        { _("Next"), function() self:onNext() end, enabled = s.index < #s.collection },
        { _("Browse"), function() self:onBrowse() end },
        { _("Close"), function() self:onClose() end },
    }, second_y)
end

function Study:redraw()
    UIManager:setDirty(self, "ui")
end

function Study:save()
    self.needs_save = not Progress.save(self.progress_path, self.session.progress)
    self.save_failed = self.needs_save
end

function Study:onFlushSettings()
    if self.needs_save then self:save() end
end

function Study:clearSelection()
    self.selected, self.hinted, self.promotion, self.message = nil, nil, nil, nil
end

function Study:onHintOrReveal()
    if self.hint_used then return self:onReveal() end
    self:clearSelection()
    self.hinted = self.session:hint()
    self.hint_used = self.hinted ~= nil
    self:redraw()
end

function Study:onRetry()
    self.session:retry()
    self:clearSelection()
    self.hint_used = nil
    self:save()
    self:redraw()
end

function Study:onReveal()
    local line = self.session:reveal()
    if not line then return end
    self:clearSelection()
    self.hint_used = nil
    self:save()
    self:redraw()
    UIManager:show(InfoMessage:new{ text = _("Solution") .. "\n\n" .. line })
end

function Study:navigate(offset)
    if not self.promotion and self.session:navigate(offset) then
        self:clearSelection()
        self.hint_used = nil
        self:save()
        self:redraw()
    end
    return true
end

function Study:onPrevious() return self:navigate(-1) end
function Study:onNext() return self:navigate(1) end

function Study:onBrowse()
    require("pocketchess_browse").show(self)
end

function Study:play(move)
    local result, san, reply = self.session:play(move)
    self:clearSelection()
    if result == "correct" then
        self.hint_used = nil
        self.message = reply and string.format(_("Correct: %s  ·  Reply: %s"), san, reply)
            or string.format(_("Correct: %s"), san)
        self:save()
    elseif result == "incorrect" then
        self.message = _("Try another move.")
    elseif result == "illegal" then
        self.message = _("Illegal move.")
    end
    self:redraw()
end

function Study:promote(piece)
    self:play(self.promotion.from .. self.promotion.to .. piece)
end

function Study:cancelPromotion()
    self.promotion, self.message = nil, nil
    self:redraw()
end

function Study:onTap(_arg, gesture)
    local pos = gesture.pos
    for _, button in ipairs(self.buttons or {}) do
        if contains(button[1], pos) then
            button[2]()
            return true
        end
    end
    if self.promotion or not self.session.step.move or not self.board or not contains(self.board, pos) then
        return true
    end
    local col = math.floor((pos.x - self.board.x) / self.cell) + 1
    local row = math.floor((pos.y - self.board.y) / self.cell) + 1
    local square = self:square(col, row)
    self.message, self.hinted = nil, nil
    if self.session:owns(square) then
        self.selected = self.selected ~= square and square or nil
    elseif self.selected then
        local choices = self.session:promotions(self.selected, square)
        if #choices == 0 then
            self:play(self.selected .. square)
            return true
        end
        self.promotion = { from = self.selected, to = square, choices = choices }
        self.message = _("Choose a promotion piece.")
    end
    self:redraw()
    return true
end

function Study:onKeyPress(key)
    InputContainer.onKeyPress(self, key)
    return true
end

function Study:onKeyRepeat() return true end
function Study:onHome() return self:onClose() end

function Study:handleEvent(event)
    -- The reader underneath this modal isn't a recipient for Dispatcher events.
    local listener = self.host.devicelistener
    if listener and frontlight_events[event.handler] then
        listener:handleEvent(event)
        return true
    end
    return InputContainer.handleEvent(self, event)
end

function Study:onClose()
    UIManager:close(self, "full")
    return true
end

function Study:onCloseWidget()
    self:freePieces()
    self.closed()
end

return Study
