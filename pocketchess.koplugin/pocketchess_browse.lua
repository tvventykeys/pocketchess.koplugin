local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Browse = {}

local themes = {
    { _("Any theme") }, { _("Mate"), "mate" }, { _("Fork"), "fork" },
    { _("Pin"), "pin" }, { _("Endgame"), "endgame" }, { _("Middlegame"), "middlegame" },
}

local ratings = {
    { _("Any rating"), 80, 1500 },
    { _("Under 1200"), 80, 1199 },
    { _("1200–1399"), 1200, 1399 },
    { _("1400–1500"), 1400, 1500 },
}

function Browse.show(study)
    local session = study.session
    local function selectCollection(expanded, theme, min_rating, max_rating)
        if not session:selectCollection(expanded, theme, min_rating, max_rating) then
            UIManager:show(InfoMessage:new{ text = _("No puzzles match these filters.") })
            return
        end
        study:clearSelection()
        study.hint_used = nil
        study:save()
        study:redraw()
    end

    local function chooseRating(theme)
        local dialog
        local buttons = {}
        for _, band in ipairs(ratings) do
            buttons[#buttons + 1] = { {
                text = band[1],
                callback = function()
                    UIManager:close(dialog)
                    selectCollection(true, theme[2], band[2], band[3])
                end,
            } }
        end
        dialog = ButtonDialog:new{ title = theme[1], buttons = buttons, modal = true }
        UIManager:show(dialog)
    end

    local dialog
    local buttons = { { {
        text = _("Original 20 puzzles"),
        callback = function()
            UIManager:close(dialog)
            selectCollection(false)
        end,
    } } }
    for index = 1, #themes, 2 do
        local row = {}
        for _, theme in ipairs({ themes[index], themes[index + 1] }) do
            row[#row + 1] = {
                text = theme[1],
                callback = function()
                    UIManager:close(dialog)
                    chooseRating(theme)
                end,
            }
        end
        buttons[#buttons + 1] = row
    end
    dialog = ButtonDialog:new{ title = _("Browse Lichess puzzles"), buttons = buttons, modal = true }
    UIManager:show(dialog)
end

return Browse
