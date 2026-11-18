-- Run as a late KOReader user patch in an isolated Linux emulator profile.
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local Geom = require("ui/geometry")
local Key = require("device/key")
local MenuSorter = require("ui/menusorter")
local PluginLoader = require("pluginloader")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")

local function run()
    local manager = assert(ReaderUI.instance or FileManager.instance, "KOReader did not open its main screen")
    local plugin = assert(PluginLoader:getPluginInstance("pocketchess"), "PluginLoader did not load Pocket Chess")
    local baseline = UIManager:getTopmostVisibleWidget()

    local function checkClosed(study)
        assert(not plugin.study and not UIManager:isWidgetShown(study))
        assert(UIManager:isWidgetShown(manager) and not manager.menu.menu_container)
        local top = UIManager:getTopmostVisibleWidget()
        assert(top == manager or top == baseline, "Closing changed the underlying KOReader screen")
    end

    local function open()
        manager.menu:onShowMenu()
        local menu = manager.menu.menu_container[1]
        local items = manager.menu.menu_items
        assert(items.pocketchess and items.pocketchess.text == "Pocket Chess Studies")
        local tools = assert(MenuSorter:findById(manager.menu.tab_item_table, "tools"))
        local entry
        for _, item in ipairs(tools) do
            if item.id == "pocketchess" then entry = item end
        end
        assert(entry == items.pocketchess, "Pocket Chess must appear directly in Tools")
        if os.getenv("POCKETCHESS_SMOKE_NO_MORE_TOOLS") then
            assert(not MenuSorter:findById(tools, "more_tools"))
        end
        menu:onMenuSelect(items.pocketchess)
        assert(UIManager:getTopmostVisibleWidget() == plugin.study, "Study should cover the main menu")
        UIManager:_repaint()
        return assert(plugin.study)
    end

    local function tap(x, y)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y } }))
    end

    local function press(key)
        UIManager:sendEvent(Event:new("KeyPress", Key:new(key, {})))
    end

    local study = open()
    assert(#study.session.puzzles == 20020 and #study.session.collection == 20 and study.cell >= 100)
    assert(Device.screen:isColorEnabled())
    local board = study.board
    local light = Device.screen.bb:getPixel(board.x + 2, board.y + 2)
    local dark = Device.screen.bb:getPixel(board.x + study.cell + 2, board.y + 2)
    assert(light:getR() > dark:getR() and dark:getR() > dark:getG())
    local capture = os.getenv("POCKETCHESS_SMOKE_PNG")
    if capture then Device.screen.bb:writePNG(capture) end

    local brightness, warmth
    local listener = manager.devicelistener
    local increaseBrightness = listener.onIncreaseFlIntensity
    local increaseWarmth = listener.onIncreaseFlWarmth
    listener.onIncreaseFlIntensity = function(self, gesture)
        brightness = gesture
        return increaseBrightness(self, gesture)
    end
    listener.onIncreaseFlWarmth = function(self, gesture)
        warmth = gesture
        return increaseWarmth(self, gesture)
    end
    local function edgeSwipe(x)
        UIManager:sendEvent(Event:new("Gesture", {
            ges = "swipe", direction = "north", distance = 160,
            pos = Geom:new{ x = x, y = math.floor(Device.screen:getHeight() / 2) },
        }))
    end
    edgeSwipe(Device.screen:getWidth() / 2)
    assert(not brightness and not warmth)
    edgeSwipe(2)
    edgeSwipe(Device.screen:getWidth() - 2)
    assert(brightness.ges == "swipe" and warmth.ges == "swipe")
    local mappings = manager.gestures.gestures
    local left_up = mappings.one_finger_swipe_left_edge_up
    local right_up = mappings.one_finger_swipe_right_edge_up
    mappings.one_finger_swipe_left_edge_up = { increase_frontlight_warmth = 7 }
    edgeSwipe(2)
    assert(warmth == 7, "Study did not respect the configured left edge assignment")
    warmth = nil
    local start = Geom:new{ x = 2, y = 400 }
    local ending = Geom:new{ x = 3, y = 230 }
    UIManager:sendEvent(Event:new("Gesture", { ges = "pan", start_pos = start, pos = ending }))
    UIManager:sendEvent(Event:new("Gesture", { ges = "pan_release", pos = ending }))
    assert(warmth == 7, "Slow edge drag did not use the configured action")
    mappings.one_finger_swipe_left_edge_up = left_up
    mappings.one_finger_swipe_right_edge_up = nil
    warmth = nil
    edgeSwipe(Device.screen:getWidth() - 2)
    assert(warmth and warmth.ges == "swipe", "Unassigned edge did not use default warmth")
    mappings.one_finger_swipe_right_edge_up = right_up
    listener.onIncreaseFlIntensity = increaseBrightness
    listener.onIncreaseFlWarmth = increaseWarmth

    local light_button = study.buttons[4][1]
    tap(light_button.x + 10, light_button.y + 10)
    local controls = UIManager:getTopmostVisibleWidget()
    assert(controls.name == "FrontLightWidget" and controls.modal and controls.has_nl)
    UIManager:_repaint()
    local previous_brightness, previous_warmth = controls.fl.cur, controls.nl.cur
    local target_brightness = previous_brightness == controls.fl.max and previous_brightness - 1
        or previous_brightness + 1
    local target_warmth = previous_warmth == controls.nl.max and previous_warmth - 1 or previous_warmth + 1
    controls:setBrightness(target_brightness)
    controls:setWarmth(target_warmth, true)
    assert(controls.powerd:frontlightIntensity() == target_brightness)
    assert(controls.powerd:toNativeWarmth(controls.powerd:frontlightWarmth()) == target_warmth)
    controls:onClose()
    assert(UIManager:getTopmostVisibleWidget() == study and study.session.index == 1)

    local hint = study.buttons[1][1]
    tap(hint.x + 10, hint.y + 10)
    assert(study.hinted == "e7" and study.selected == nil)
    UIManager:_repaint()
    local dot_x = board.x + math.floor(study.cell * 3.5)
    local dot_y = board.y + math.floor(study.cell * 1.5)
    local dot_before = Device.screen.bb:getPixel(dot_x, dot_y):getR()
    tap(board.x + math.floor(study.cell * 4.5), board.y + math.floor(study.cell * 1.5))
    UIManager:_repaint()
    assert(Device.screen.bb:getPixel(dot_x, dot_y):getR() < dot_before, "Legal move dot did not render")
    local refresh = study.buttons[3][1]
    tap(refresh.x + 10, refresh.y + 10)
    local update = assert(UIManager._refresh_stack[1], "Refresh did not queue an update")
    assert(update.mode == "full" and update.region.w == Device.screen:getWidth()
        and update.region.h == Device.screen:getHeight())
    assert(study.selected == "e7" and study.session.stage == 1)
    UIManager:_repaint()
    tap(board.x + math.floor(study.cell * 4.5), board.y + math.floor(study.cell * 0.5))
    assert(study.session.solved)

    press("RPgFwd")
    assert(study.session.index == 2 and study.auto_advance == nil)
    assert(UIManager._refresh_stack[1].mode == "full")
    press("LPgBack")
    assert(study.session.index == 1)
    press(Device.input.group.Back[1])
    checkClosed(study)
    study = open()
    assert(study.session.solved and study.session.index == 1, "Solved progress did not reload")
    local browse = study.buttons[#study.buttons - 1][1]
    tap(browse.x + 10, browse.y + 10)
    local themes = UIManager:getTopmostVisibleWidget()
    themes.buttons[3][1].callback() -- Fork
    local ratings = UIManager:getTopmostVisibleWidget()
    ratings.buttons[3][1].callback() -- 1200–1399
    local pack = study.session
    assert(#pack.collection > 1 and #pack.collection < 20000)
    for _, entry in ipairs(pack.collection) do
        assert(entry.themes:find(" fork ", 1, true) and entry.rating >= 1200 and entry.rating <= 1399)
        assert(not entry.steps, "Puzzle positions should be read as needed")
    end
    local first_id = pack.puzzle.id
    press("RPgFwd")
    assert(pack.puzzle.id ~= first_id and pack.index == 2 and pack.step.move)
    local resumed_id = pack.puzzle.id
    study:play(pack.step.move)
    assert(pack.stage == 2)
    study:onClose()
    study = open()
    assert(study.session.puzzle.id == resumed_id and study.session.stage == 2)
    study:onBrowse()
    UIManager:getTopmostVisibleWidget().buttons[1][1].callback()
    assert(study.session.index == 1 and study.session.solved and #study.session.collection == 20)
    UIManager:_repaint()
    local close = study.buttons[#study.buttons][1]
    tap(close.x + 10, close.y + 10)
    checkClosed(study)
    study = open()
    study:onRetry()
    study:play(study.session.step.move)
    assert(study.session.index == 1 and study.session.solved and study.auto_advance)
    local setDirty = UIManager.setDirty
    local refreshed
    UIManager.setDirty = function(self, widget, mode, region, ...)
        if widget == study and mode == "full" and region == nil then refreshed = true end
        return setDirty(self, widget, mode, region, ...)
    end
    return function()
        UIManager.setDirty = setDirty
        assert(study.session.index == 2 and refreshed, "Auto-advance did not load and refresh the next puzzle")
        study:onClose()
        checkClosed(study)
    end
end

local function finish(ok, err)
    if ok then
        print("Pocket Chess KOReader smoke passed")
    else
        io.stderr:write(err, "\n")
    end
    UIManager:quit(ok and 0 or 1)
end

UIManager:scheduleIn(0.1, function()
    local ok, verify = xpcall(run, debug.traceback)
    if not ok then return finish(false, verify) end
    UIManager:scheduleIn(2.2, function() finish(xpcall(verify, debug.traceback)) end)
end)
