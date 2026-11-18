-- Puzzle positions and legal moves are compiled with python-chess.
local Session = {}
Session.__index = Session

function Session.new(puzzles, progress)
    local self = setmetatable({ puzzles = puzzles, progress = progress, index = 1 }, Session)
    for index, item in ipairs(puzzles) do
        if item.id == progress.current then self.index = index end
    end
    self:loadPuzzle()
    return self
end

function Session:loadPuzzle()
    self.puzzle = self.puzzles[self.index]
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
    if index < 1 or index > #self.puzzles then return false end
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
