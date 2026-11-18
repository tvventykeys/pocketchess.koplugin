local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
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
    local expansion = require("pocketchess_expansion").open(self.path .. "/lichess-expansion.sqlite3")
    if not expansion then
        UIManager:show(InfoMessage:new{
            text = _("Could not open the puzzle pack. Reinstall Pocket Chess Studies from the ZIP."),
        })
        return
    end
    local puzzles = {}
    for _, puzzle in ipairs(Puzzles) do puzzles[#puzzles + 1] = puzzle end
    for _, puzzle in ipairs(expansion.entries) do puzzles[#puzzles + 1] = puzzle end
    local path = DataStorage:getSettingsDir() .. "/pocketchess-progress.txt"
    local state, recovered = Progress.load(path, puzzles)
    self.study = Study:new{
        asset_path = self.path .. "/pieces/",
        host = self.ui,
        session = Session.new(puzzles, state, expansion),
        progress_path = path,
        message = recovered and _("Damaged progress was reset.") or nil,
        closed = function()
            expansion:close()
            self.study = nil
        end,
    }
    UIManager:show(self.study, "full")
end

function PocketChess:onCloseWidget()
    if self.study then self.study:onClose() end
end

return PocketChess
