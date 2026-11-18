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
    assert(#study.session.puzzles == 20 and study.cell >= 100)
    assert(Device.screen:isColorEnabled())
    local board = study.board
    local light = Device.screen.bb:getPixel(board.x + 2, board.y + 2)
    local dark = Device.screen.bb:getPixel(board.x + study.cell + 2, board.y + 2)
    assert(light:getR() > dark:getR() and dark:getR() > dark:getG())
    local capture = os.getenv("POCKETCHESS_SMOKE_PNG")
    if capture then Device.screen.bb:writePNG(capture) end

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
    assert(study.session.index == 2)
    press("LPgBack")
    assert(study.session.index == 1)
    press(Device.input.group.Back[1])
    checkClosed(study)
    study = open()
    assert(study.session.solved and study.session.index == 1, "Solved progress did not reload")
    local close = study.buttons[#study.buttons][1]
    tap(close.x + 10, close.y + 10)
    checkClosed(study)
end

UIManager:scheduleIn(0.1, function()
    local ok, err = xpcall(run, debug.traceback)
    if ok then
        print("Pocket Chess KOReader smoke passed")
    else
        io.stderr:write(err, "\n")
    end
    UIManager:quit(ok and 0 or 1)
end)
