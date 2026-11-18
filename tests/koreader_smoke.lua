-- Run as a late KOReader user patch in an isolated Linux emulator profile.
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local Geom = require("ui/geometry")
local Key = require("device/key")
local MenuSorter = require("ui/menusorter")
local PluginLoader = require("pluginloader")
local UIManager = require("ui/uimanager")

local function run()
    local manager = assert(FileManager.instance, "KOReader did not start its file manager")
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
        local more = MenuSorter:findById(manager.menu.tab_item_table, "more_tools")
        assert(MenuSorter:findById(more.sub_item_table, "pocketchess") == items.pocketchess)
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
    tap(board.x + math.floor(study.cell * 4.5), board.y + math.floor(study.cell * 1.5))
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
