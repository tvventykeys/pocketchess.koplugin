local DataStorage = require("datastorage")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Progress = require("pocketchess_progress")
local Puzzles = require("pocketchess_puzzles")
local Session = require("pocketchess_session")
local _ = require("gettext")

local PocketChess = InputContainer:extend{
    name = "pocketchess",
    is_doc_only = false,
}

function PocketChess:init()
    self.ui.menu:registerToMainMenu(self)
end

function PocketChess:addToMainMenu(menu_items)
    menu_items.pocketchess = {
        text = _("Pocket Chess Studies"),
        sorting_hint = "tools",
        callback = function() self:openStudies() end,
    }
end

function PocketChess:openStudies()
    if self.study then return end
    local Study = require("pocketchess_study")
    local path = DataStorage:getSettingsDir() .. "/pocketchess-progress.txt"
    local state, recovered = Progress.load(path, Puzzles)
    self.study = Study:new{
        asset_path = self.path .. "/pieces/",
        session = Session.new(Puzzles, state),
        progress_path = path,
        message = recovered and _("Damaged progress was reset.") or nil,
        closed = function() self.study = nil end,
    }
    UIManager:show(self.study, "full")
end

function PocketChess:onCloseWidget()
    if self.study then self.study:onClose() end
end

return PocketChess
