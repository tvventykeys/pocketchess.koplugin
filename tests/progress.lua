local Progress = require("pocketchess_progress")
local Session = require("pocketchess_session")
local Puzzles = require("pocketchess_puzzles")
local path = test_dir .. "/pocketchess-progress.txt"

local state, recovered = Progress.load(path, Puzzles)
assert(state.current == Puzzles[1].id and not recovered)
local game = Session.new(Puzzles, state)
assert(game:play(game.step.move) == "correct" and game.solved)
assert(game:navigate(1) and game:reveal())
assert(game:navigate(4))
assert(game:play(game.step.move) == "correct" and not game.solved and game.stage == 2)
assert(Progress.save(path, state))

local loaded = Session.new(Puzzles, Progress.load(path, Puzzles))
assert(loaded.index == 6 and loaded.stage == 2)
assert(loaded:navigate(-4) and loaded.revealed and not loaded.solved)
assert(loaded:navigate(-1) and loaded.solved and not loaded.revealed)

local id = Puzzles[1].id
local header = "pocketchess-progress-v1\n" .. id .. "\n"
local function write(content)
    local file = assert(io.open(path, "wb"))
    assert(file:write(content))
    assert(file:close())
end
for _, malformed in ipairs({
    "",
    "return os.remove('" .. path .. "')\n",
    header .. id .. " 1 1 0",
    header .. id .. " 99 1 0\n",
    header .. id .. " 2 0 0\n",
    header .. id .. " 1 0 1\n",
    header .. id .. " 1 1 0\n" .. id .. " 1 1 0\n",
    header .. "\n",
    header .. string.rep("a", 1000),
}) do
    write(malformed)
    local reset, damaged = Progress.load(path, Puzzles)
    assert(damaged and reset.current == id and next(reset.entries) == nil)
end

assert(Progress.save(path, state))
local original = os.rename
os.rename = function() return nil, "simulated rename failure" end
state.current = id
assert(not Progress.save(path, state))
os.rename = original
assert(Progress.load(path, Puzzles).current == Puzzles[6].id)
assert(io.open(path .. ".tmp", "rb") == nil)
