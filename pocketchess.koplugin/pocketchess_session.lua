-- Puzzle positions and legal moves are compiled with python-chess.
local Session = {}
Session.__index = Session

function Session.new(puzzles, progress, expansion)
    local self = setmetatable({ puzzles = puzzles, progress = progress, expansion = expansion }, Session)
    local current_is_expansion = false
    for _, puzzle in ipairs(puzzles) do
        if puzzle.id == progress.current then
            current_is_expansion = not puzzle.steps
            break
        end
    end
    self:selectCollection(current_is_expansion)
    return self
end

function Session:selectCollection(use_expansion, theme, min_rating, max_rating)
    local matching, current_index = {}, 1
    for _, item in ipairs(self.puzzles) do
        if (not item.steps) == use_expansion
            and (not theme or item.themes:find(" " .. theme .. " ", 1, true))
            and (not min_rating or item.rating >= min_rating and item.rating <= max_rating) then
            matching[#matching + 1] = item
            if item.id == self.progress.current then current_index = #matching end
        end
    end
    if #matching == 0 then return false end
    self.collection = matching
    self.index = current_index
    self:loadPuzzle()
    return true
end

function Session:loadPuzzle()
    local entry = self.collection[self.index]
    self.puzzle = entry
    if not entry.steps then
        self.puzzle = { id = entry.id, rating = entry.rating, steps = self.expansion:loadSteps(entry.id) }
    end
    self.progress.current = self.puzzle.id
    local saved = self.progress.entries[self.puzzle.id]
    self.stage = saved and saved.stage or 1
    self.solved = saved and saved.solved or false
    self.revealed = saved and saved.revealed or false
    self:updatePosition()
end

function Session:updatePosition()
    self.step = self.puzzle.steps[self.stage]
    local placement, side = self.step.fen:match("^(%S+) ([wb])")
    self.side = side
    self.pieces = {}
    local file, rank = 1, 8
    for char in placement:gmatch(".") do
        if char == "/" then
            file, rank = 1, rank - 1
        elseif tonumber(char) then
            file = file + tonumber(char)
        else
            self.pieces[string.char(96 + file) .. rank] = char
            file = file + 1
        end
    end
end

function Session:remember()
    self.progress.entries[self.puzzle.id] = {
        stage = self.stage, solved = self.solved, revealed = self.revealed,
    }
end

function Session:navigate(offset)
    local index = self.index + offset
    if index < 1 or index > #self.collection then return false end
    self.index = index
    self:loadPuzzle()
    return true
end

function Session:retry()
    self.stage = 1
    self.revealed = false
    self:updatePosition()
    self:remember()
end

function Session:hint()
    return self.step.move and self.step.move:sub(1, 2)
end

function Session:owns(square)
    local piece = self.pieces[square]
    return piece and (piece == piece:upper()) == (self.side == "w")
end

function Session:legalDestinations(from)
    local destinations = {}
    if from and self.step.legal then
        for move in self.step.legal:gmatch("%S+") do
            if move:sub(1, 2) == from then
                destinations[move:sub(3, 4)] = true
            end
        end
    end
    return destinations
end

function Session:promotions(from, to)
    local choices = {}
    if self.step.legal then
        for _, piece in ipairs({ "q", "r", "b", "n" }) do
            if self.step.legal:find(" " .. from .. to .. piece .. " ", 1, true) then
                choices[#choices + 1] = piece
            end
        end
    end
    return choices
end

function Session:play(move)
    local step = self.step
    if not step.move then return "finished" end
    if not step.legal:find(" " .. move .. " ", 1, true) then return "illegal" end
    if move ~= step.move then return "incorrect" end
    self.stage = self.stage + 1
    self:updatePosition()
    if not self.step.move then self.solved = true end
    self:remember()
    return "correct", step.san, step.reply
end

function Session:reveal()
    local line = {}
    for stage = self.stage, #self.puzzle.steps - 1 do
        local step = self.puzzle.steps[stage]
        line[#line + 1] = step.san
        if step.reply then line[#line + 1] = step.reply end
    end
    if #line == 0 then return nil end
    self.stage = #self.puzzle.steps
    self.revealed = true
    self:updatePosition()
    self:remember()
    return table.concat(line, "  ")
end

return Session
